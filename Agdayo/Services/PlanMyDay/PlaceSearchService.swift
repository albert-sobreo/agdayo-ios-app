import CoreLocation
import MapKit

private actor PlaceSearchCache {
    private var storage: [String: [Candidate]] = [:]

    func results(for key: String) -> [Candidate]? { storage[key] }
    func store(_ results: [Candidate], for key: String) { storage[key] = results }
}

/// MapKit side of Plan My Day: per-kind searches across the whole chosen
/// radius (cached), plus resolving the trip center and hotel anchor. The
/// planner only ever sees the `Candidate`s that come out.
enum PlaceSearchService {

    static let defaultRadius: CLLocationDistance = 10_000
    private static let perSearchLimit = 25

    private static let cache = PlaceSearchCache()

    // MARK: Candidates

    /// One kind at a time (MapKit throttles bursts), each kind fanned out
    /// over several spots in the area. Non-empty results are cached per area
    /// so regenerating doesn't re-hit MapKit.
    static func fetchCandidates(
        kinds: Set<PlaceKind>,
        near center: CLLocationCoordinate2D,
        radius: CLLocationDistance = defaultRadius,
        city: String? = nil,
        broad: Bool = false
    ) async -> [Candidate] {
        var all: [Candidate] = []
        var seen = Set<String>()
        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            for candidate in await results(for: kind, near: center, radius: radius, city: city, broad: broad)
            where seen.insert(Candidate.key(candidate.name)).inserted {
                all.append(candidate)
            }
        }
        return all
    }

    private static func results(for kind: PlaceKind, near center: CLLocationCoordinate2D, radius: CLLocationDistance, city: String?, broad: Bool) async -> [Candidate] {
        let key = "\(kind.rawValue)|\(city ?? "")|\(broad)|\(Int(radius))|\((center.latitude * 100).rounded())|\((center.longitude * 100).rounded())"
        if let cached = await cache.results(for: key) { return cached }

        // A single search returns only the ~25 places nearest to the point it
        // is centered on, so a few sample points leave whole neighborhoods
        // uncovered. Category search therefore runs over a grid of overlapping
        // cells across the whole radius; the relevance search (which ranks by
        // prominence) runs at a handful of spots.
        // Common kinds get full coverage; niche ones (a spa, a zoo, a hiking
        // trail) are sparse, so a handful of cells is enough and keeps the
        // number of requests down when many interests are selected.
        let grid = broad ? [] : gridPoints(around: center, radius: radius, limit: kind.isCommon ? 24 : 6)
        let spots = broad ? [] : Array(samplePoints(around: center, radius: radius).prefix(kind.isCommon ? 5 : 1))

        enum Job {
            case category(center: CLLocationCoordinate2D, radius: CLLocationDistance)
            case relevance(center: CLLocationCoordinate2D, radius: CLLocationDistance)
        }
        let jobs: [Job] = spots.map { .relevance(center: $0.center, radius: $0.radius) }
            + grid.map { .category(center: $0.center, radius: $0.radius) }

        func run(_ job: Job) async -> [Candidate] {
            switch job {
            case .relevance(let center, let radius):
                return await relevanceResults(for: kind, near: center, radius: radius)
            case .category(let center, let radius):
                let places = await TripPlaceDiscovery.searchCategory(
                    filter: kind.mapKitCategories,
                    displayCategory: kind.rawValue,
                    center: center,
                    radius: radius,
                    limit: perSearchLimit
                )
                return places.map {
                    Candidate(
                        name: $0.name, kind: kind, coordinate: $0.coordinate,
                        locality: $0.locality, prominence: chainPenalty(for: $0.name, kind: kind),
                        mapItemIdentifier: $0.mapItemIdentifier,
                        city: $0.city
                    )
                }
            }
        }

        // Apple's ranked answer to a Maps-style query that names the city
        // ("things to do in Makati") — the best popularity signal MapKit has.
        // A province or country is too big for a radius around its center, so
        // only the ranked, name-based search applies there.
        // For a large area (Tokyo, a province) Maps answers "things to do in
        // Tokyo" poorly, but answers "things to do in Shinjuku" well. So its
        // districts are found first and each is searched by name.
        let ranked: [Candidate]
        if broad {
            ranked = await districtResults(for: kind, around: center, reach: min(radius, 30_000))
        } else {
            ranked = await rankedResults(for: kind, in: city, near: center, radius: radius)
        }

        // A few at a time: MapKit throttles bursts and silently drops results.
        let gridBatches = await withTaskGroup(of: [Candidate].self, returning: [[Candidate]].self) { group in
            var collected: [[Candidate]] = []
            var next = 0
            let limit = 6
            while next < min(limit, jobs.count) {
                let job = jobs[next]
                group.addTask { await run(job) }
                next += 1
            }
            while let batch = await group.next() {
                collected.append(batch)
                if next < jobs.count {
                    let job = jobs[next]
                    group.addTask { await run(job) }
                    next += 1
                }
            }
            return collected
        }

        let batches = [ranked] + gridBatches

        // Same place from several searches keeps its best prominence.
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var merged: [String: Candidate] = [:]
        for candidate in batches.joined() {
            let distance = origin.distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
            guard distance <= radius else { continue }
            let id = Candidate.key(candidate.name)
            if let existing = merged[id], existing.prominence >= candidate.prominence { continue }
            merged[id] = candidate
        }

        let candidates = Array(merged.values)
        if !candidates.isEmpty {
            await cache.store(candidates, for: key)
        }
        return candidates
    }

    /// Searches the way the Apple Maps app would ("best restaurants in
    /// Makati") and keeps Apple's own ranking: the first answer to each query
    /// scores highest. A place that several phrasings agree on scores higher
    /// still. Needs the city name — without it the engine falls back to
    /// matching street names ("Museum Drive").
    private static func rankedResults(
        for kind: PlaceKind,
        in city: String?,
        near center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async -> [Candidate] {
        guard let city, !city.isEmpty else { return [] }
        var best: [String: Candidate] = [:]
        var hits: [String: Int] = [:]

        for query in kind.rankedQueries(in: city) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }

            // Items without a category are guides/streets, not places to go.
            let usable = response.mapItems.filter { item in
                guard let name = item.name, let category = item.pointOfInterestCategory else { return false }
                return kind.accepts(category) && !looksLikeARoad(name)
            }
            let total = max(usable.count - 1, 1)
            for (index, item) in usable.enumerated() {
                guard let name = item.name else { continue }
                let id = Candidate.key(name)
                hits[id, default: 0] += 1
                let rank = 0.5 + 0.5 * (1 - Double(index) / Double(total))
                let locality = [item.placemark.subLocality, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
                let candidate = Candidate(
                    name: name,
                    kind: PlaceKind.from(category: item.pointOfInterestCategory),
                    coordinate: item.placemark.coordinate,
                    locality: locality.isEmpty ? nil : locality,
                    prominence: rank + chainPenalty(for: name, kind: kind),
                    mapItemIdentifier: item.identifier?.rawValue,
                    city: item.placemark.locality
                )
                if let existing = best[id], existing.prominence >= candidate.prominence { continue }
                best[id] = candidate
            }
        }

        // Agreement between phrasings is a vote for the place.
        return best.map { id, candidate in
            let bonus = Double((hits[id] ?? 1) - 1) * 0.15
            return Candidate(
                id: candidate.id, name: candidate.name, kind: candidate.kind,
                coordinate: candidate.coordinate, locality: candidate.locality,
                prominence: candidate.prominence + bonus,
                mapItemIdentifier: candidate.mapItemIdentifier, city: candidate.city
            )
        }
    }

    // MARK: Districts of a large area

    struct District {
        let name: String
        let key: String
        let latitude: Double
        let longitude: Double
        let hits: Int
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    private actor DistrictCache {
        var storage: [String: [District]] = [:]
        func districts(for key: String) -> [District]? { storage[key] }
        func store(_ districts: [District], for key: String) { storage[key] = districts }
    }

    private static let districtCache = DistrictCache()

    /// The districts (wards, cities, towns) around a point, found by asking
    /// Maps for places in rings around it and reading which district each
    /// belongs to. Busiest first; spellings of the same name are merged.
    static func districts(around center: CLLocationCoordinate2D, reach: CLLocationDistance, limit: Int = 18) async -> [District] {
        let cacheKey = "\((center.latitude * 100).rounded())|\((center.longitude * 100).rounded())|\(Int(reach))"
        if let cached = await districtCache.districts(for: cacheKey) { return cached }

        // Fine rings near the center, where the main districts are packed
        // together (each probe only reaches the one or two next to it), and
        // wider ones toward the edge, where places are sparse.
        var probes: [(CLLocationCoordinate2D, CLLocationDistance)] = [(center, reach * 0.07)]
        let rings: [(fraction: Double, count: Int)] = [(0.06, 6), (0.12, 8), (0.2, 12), (0.3, 12), (0.45, 8), (0.65, 8), (0.9, 8)]
        for ring in rings {
            let radius = max(reach * 0.07, reach * ring.fraction * 0.35)
            for step in 0..<ring.count {
                let radians = Double(step) / Double(ring.count) * 2 * .pi
                let dLat = cos(radians) * reach * ring.fraction / 111_320
                let dLon = sin(radians) * reach * ring.fraction / (111_320 * max(cos(center.latitude * .pi / 180), 0.1))
                probes.append((CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon), radius))
            }
        }

        var hits: [(raw: String, coordinate: CLLocationCoordinate2D)] = []
        await withTaskGroup(of: [(raw: String, coordinate: CLLocationCoordinate2D)].self) { group in
            var next = 0
            while next < min(6, probes.count) {
                let probe = probes[next]
                group.addTask { await localityHits(around: probe.0, radius: probe.1) }
                next += 1
            }
            while let batch = await group.next() {
                hits += batch
                if next < probes.count {
                    let probe = probes[next]
                    group.addTask { await localityHits(around: probe.0, radius: probe.1) }
                    next += 1
                }
            }
        }

        let grouped = Dictionary(grouping: hits) { Candidate.cityKey($0.raw) }
        let found = mergeScripts(grouped.compactMap { key, places -> District? in
            guard !key.isEmpty, places.count >= 3 else { return nil }
            let lat = places.map(\.coordinate.latitude).reduce(0, +) / Double(places.count)
            let lon = places.map(\.coordinate.longitude).reduce(0, +) / Double(places.count)
            return District(name: queryName(from: places.map(\.raw)), key: key, latitude: lat, longitude: lon, hits: places.count)
        })
        // Busy and close to the center first: raw counts alone favor the outskirts,
        // where most of the probe points are.
        .sorted { lhs, rhs in
            func score(_ d: District) -> Double {
                let meters = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    .distance(from: CLLocation(latitude: d.latitude, longitude: d.longitude))
                let scaled = meters / 6_000
                return Double(d.hits) / (1 + scaled * scaled)
            }
            return score(lhs) > score(rhs)
        }
        .prefix(limit)
        .map { $0 }

        if !found.isEmpty { await districtCache.store(found, for: cacheKey) }
        return found
    }

    /// Maps names one ward in more than one script ("Shinjuku" and "新宿区").
    /// A non-Latin district sitting within 3 km of a Latin one is the same
    /// place: fold its count into the Latin one and drop the duplicate.
    private static func mergeScripts(_ districts: [District]) -> [District] {
        var latin = districts.filter { !NameLanguage.hasNonLatinLetters($0.name) }
        var rest: [District] = []
        for district in districts where NameLanguage.hasNonLatinLetters(district.name) {
            let origin = CLLocation(latitude: district.latitude, longitude: district.longitude)
            let nearest = latin.indices.min { lhs, rhs in
                origin.distance(from: CLLocation(latitude: latin[lhs].latitude, longitude: latin[lhs].longitude))
                    < origin.distance(from: CLLocation(latitude: latin[rhs].latitude, longitude: latin[rhs].longitude))
            }
            if let nearest,
               origin.distance(from: CLLocation(latitude: latin[nearest].latitude, longitude: latin[nearest].longitude)) <= 3_000 {
                let l = latin[nearest]
                latin[nearest] = District(name: l.name, key: l.key, latitude: l.latitude, longitude: l.longitude, hits: l.hits + district.hits)
            } else {
                rest.append(district)
            }
        }
        return latin + rest
    }

    /// Every place Maps returns around a probe point, with the district it
    /// reports (the last comma part, so "中原区, 川崎市" reads as "川崎市").
    private static func localityHits(around center: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [(raw: String, coordinate: CLLocationCoordinate2D)] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let locality = item.placemark.locality,
                  let last = locality.split(separator: ",").last else { return nil }
            let raw = String(last).trimmingCharacters(in: .whitespaces)
            return raw.isEmpty ? nil : (raw, item.placemark.coordinate)
        }
    }

    /// The spelling to search with: the most common Latin-script variant if
    /// there is one ("Shinjuku-Ku" -> "Shinjuku"), else the most common one.
    private static func queryName(from variants: [String]) -> String {
        let latin = variants.filter { !NameLanguage.hasNonLatinLetters($0) }
        let pool = latin.isEmpty ? variants : latin
        let counts = Dictionary(grouping: pool, by: { $0 }).mapValues(\.count)
        var name = counts.max { $0.value < $1.value }?.key ?? pool[0]
        for suffix in ["-Ku", "-ku", "-Shi", "-shi"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name
    }

    /// Ranked places for one kind in each district of a large area. Each
    /// district is asked about by name, so it returns its own best places
    /// (not one or two per district out of a single city-wide answer), and
    /// the district name labels the group so spellings can't split it.
    private static func districtResults(for kind: PlaceKind, around center: CLLocationCoordinate2D, reach: CLLocationDistance) async -> [Candidate] {
        let areas = await districts(around: center, reach: reach)
        guard !areas.isEmpty else { return [] }

        var all: [Candidate] = []
        await withTaskGroup(of: [Candidate].self) { group in
            var next = 0
            func add(_ area: District) {
                group.addTask { await districtKindResults(kind, in: area) }
            }
            while next < min(6, areas.count) { add(areas[next]); next += 1 }
            while let batch = await group.next() {
                all += batch
                if next < areas.count { add(areas[next]); next += 1 }
            }
        }
        return all
    }

    private static func districtKindResults(_ kind: PlaceKind, in area: District) async -> [Candidate] {
        guard let query = kind.rankedQueries(in: area.name).first else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: area.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        let origin = CLLocation(latitude: area.latitude, longitude: area.longitude)
        let usable = response.mapItems.filter { item in
            guard let name = item.name, let category = item.pointOfInterestCategory else { return false }
            let c = item.placemark.coordinate
            // Keep what is actually in this district.
            return kind.accepts(category) && !looksLikeARoad(name)
                && origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) <= 8_000
        }
        let total = max(usable.count - 1, 1)
        return usable.enumerated().compactMap { index, item in
            guard let name = item.name else { return nil }
            let locality = [item.placemark.subLocality, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
            let rank = 0.5 + 0.5 * (1 - Double(index) / Double(total))
            return Candidate(
                name: name,
                kind: PlaceKind.from(category: item.pointOfInterestCategory),
                coordinate: item.placemark.coordinate,
                locality: locality.isEmpty ? nil : locality,
                prominence: rank + chainPenalty(for: name, kind: kind),
                mapItemIdentifier: item.identifier?.rawValue,
                city: area.name
            )
        }
    }

    /// Street corners, junctions and underpasses that MapKit files as landmarks.
    static func looksLikeARoad(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let endings = [" st", " street", " ave", " avenue", " drive", " dr", " road", " rd", " blvd", " boulevard",
                       " junction", " underpass", " flyover", " overpass", " intersection", " highway"]
        return endings.contains { lowered.hasSuffix($0) }
    }

    /// Overlapping search cells covering the radius: a square grid trimmed to
    /// the circle, nearest-to-center first, capped so a kind stays a
    /// reasonable number of requests. Spacing grows with the radius.
    static func gridPoints(
        around center: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        limit: Int = 24
    ) -> [(center: CLLocationCoordinate2D, radius: CLLocationDistance)] {
        let spacing = max(1_500, radius / 3)
        let cellRadius = spacing * 0.8
        let dLat = spacing / 111_320
        let dLon = spacing / (111_320 * max(cos(center.latitude * .pi / 180), 0.1))
        let rings = Int((radius / spacing).rounded(.up))

        var cells: [(center: CLLocationCoordinate2D, radius: CLLocationDistance, offset: Double)] = []
        for row in -rings...rings {
            for column in -rings...rings {
                let offset = hypot(Double(row), Double(column)) * spacing
                guard offset <= radius else { continue }
                cells.append((
                    CLLocationCoordinate2D(
                        latitude: center.latitude + Double(row) * dLat,
                        longitude: center.longitude + Double(column) * dLon
                    ),
                    cellRadius,
                    offset
                ))
            }
        }
        return cells
            .sorted { $0.offset < $1.offset }
            .prefix(limit)
            .map { ($0.center, $0.radius) }
    }

    /// The center plus four spots 60% of the way out (N/E/S/W), each searched
    /// at half the radius so the circles overlap and cover the area.
    private static func samplePoints(
        around center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) -> [(center: CLLocationCoordinate2D, radius: CLLocationDistance)] {
        // Small areas don't need splitting.
        guard radius > 3_000 else { return [(center, radius)] }
        let offset = radius * 0.6
        let dLat = offset / 111_320
        let dLon = offset / (111_320 * max(cos(center.latitude * .pi / 180), 0.1))
        let sub = radius * 0.5
        return [
            (center, sub),
            (CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude), sub),
            (CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude), sub),
            (CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + dLon), sub),
            (CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude - dLon), sub),
        ]
    }

    /// Natural-language search ("best museums"), which MapKit orders by
    /// relevance/prominence rather than distance. Rank position becomes the
    /// prominence score.
    private static func relevanceResults(for kind: PlaceKind, near center: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [Candidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = kind.relevanceQuery
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        let usable = response.mapItems.filter { item in
            item.name != nil && kind.accepts(item.pointOfInterestCategory)
        }
        let total = max(usable.count - 1, 1)
        return usable.enumerated().compactMap { index, item in
            guard let name = item.name else { return nil }
            let locality = [item.placemark.subLocality, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
            let rank = 1 - Double(index) / Double(total)
            return Candidate(
                name: name, kind: kind, coordinate: item.placemark.coordinate,
                locality: locality.isEmpty ? nil : locality,
                prominence: rank + chainPenalty(for: name, kind: kind),
                mapItemIdentifier: item.identifier?.rawValue,
                city: item.placemark.locality
            )
        }
    }

    /// The full Apple Maps place for a candidate (phone, hours, photos… in
    /// the native place card). Falls back to a bare pin if MapKit can't
    /// look it up again.
    static func mapItem(for candidate: Candidate) async -> MKMapItem {
        if let raw = candidate.mapItemIdentifier,
           let identifier = MKMapItem.Identifier(rawValue: raw),
           let item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem {
            return item
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: candidate.coordinate))
        item.name = candidate.name
        return item
    }

    /// Free-text search for one specific place, near the day's base — for
    /// when the traveler knows where they want to go.
    static func search(query: String, near center: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [Candidate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let locality = [item.placemark.subLocality, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
            return Candidate(
                name: name,
                kind: PlaceKind.from(category: item.pointOfInterestCategory),
                coordinate: item.placemark.coordinate,
                locality: locality.isEmpty ? nil : locality,
                mapItemIdentifier: item.identifier?.rawValue,
                city: item.placemark.locality
            )
        }
    }

    /// Generic fast-food/convenience chains make poor suggestions when
    /// travelers want to experience a place; push them down the ranking.
    private static let chains = [
        "jollibee", "mcdonald", "kfc", "burger king", "chowking", "mang inasal", "greenwich",
        "shakey", "pizza hut", "domino", "wendy", "subway", "starbucks", "dunkin", "tim hortons",
        "7-eleven", "7 eleven", "ministop", "family mart", "familymart", "lawson", "bonchon",
        "yellow cab", "army navy", "potato corner", "mcdo", "krispy kreme", "coffee bean", "seattle's best",
        "jolibee", "sbarro", "earl of sandwich", "california pizza kitchen", "kenny rogers", "red ribbon",
        "goldilocks", "tgi friday", "chili's", "gong cha", "tealive", "mister donut", "figaro", "ministop",
    ]

    static func chainPenalty(for name: String, kind: PlaceKind) -> Double {
        guard [.restaurant, .cafe, .bakery, .store].contains(kind) else { return 0 }
        let lowered = name.lowercased()
        return chains.contains { lowered.contains($0) } ? -0.8 : 0
    }
}

extension PlaceKind {
    /// Kinds nearly every day plan needs; the rest are niche and searched lighter.
    var isCommon: Bool {
        switch self {
        case .restaurant, .cafe, .bakery, .landmark, .museum, .park, .store, .nightlife: return true
        default: return false
        }
    }

    /// The kind a MapKit category belongs to; landmark when it's none of ours.
    static func from(category: MKPointOfInterestCategory?) -> PlaceKind {
        guard let category else { return .landmark }
        return PlaceKind.allCases.first { $0.mapKitCategories.contains(category) } ?? .landmark
    }

    var mapKitCategories: [MKPointOfInterestCategory] {
        switch self {
        case .landmark: return [.landmark, .nationalMonument, .castle, .fortress]
        case .museum: return [.museum]
        case .theater: return [.theater]
        case .park: return [.park]
        case .beach: return [.beach]
        case .nationalPark: return [.nationalPark]
        case .store: return [.store]
        case .zoo: return [.zoo]
        case .aquarium: return [.aquarium]
        case .amusementPark: return [.amusementPark]
        case .foodMarket: return [.foodMarket]
        case .nightlife: return [.nightlife]
        case .restaurant: return [.restaurant]
        case .cafe: return [.cafe]
        case .bakery: return [.bakery]
        case .spa: return [.spa]
        case .brewery: return [.brewery, .winery, .distillery]
        case .musicVenue: return [.musicVenue]
        case .movieTheater: return [.movieTheater]
        case .hiking: return [.hiking, .rockClimbing]
        case .campground: return [.campground, .marina]
        case .waterSports: return [.surfing, .kayaking, .swimming, .fishing]
        case .sports: return [.golf, .stadium, .skatePark, .skating, .tennis]
        case .recreation: return [.bowling, .miniGolf, .goKart, .fairground]
        }
    }

    /// Maps-style phrasings that put the city in the query. Bare plurals
    /// ("restaurants in Makati") match street names, so these use phrasings
    /// that return real places.
    func rankedQueries(in city: String) -> [String] {
        switch self {
        case .restaurant: return ["best restaurants in \(city)", "popular restaurants in \(city)"]
        case .cafe: return ["cafes in \(city)", "best coffee shops in \(city)"]
        case .bakery: return ["bakeries in \(city)", "best bakery in \(city)"]
        case .landmark: return ["things to do in \(city)", "famous landmarks in \(city)"]
        case .museum: return ["best museums in \(city)", "art museum in \(city)"]
        case .theater: return ["theaters in \(city)", "performing arts in \(city)"]
        case .park: return ["parks in \(city)", "gardens in \(city)"]
        case .beach: return ["best beaches in \(city)"]
        case .nationalPark: return ["nature reserves in \(city)", "national park near \(city)"]
        case .store: return ["shopping malls in \(city)", "markets in \(city)"]
        case .zoo: return ["zoo in \(city)"]
        case .aquarium: return ["aquarium in \(city)"]
        case .amusementPark: return ["theme parks in \(city)"]
        case .foodMarket: return ["food markets in \(city)", "weekend market in \(city)"]
        case .nightlife: return ["best bars in \(city)", "nightlife in \(city)"]
        case .spa: return ["best spa in \(city)", "massage in \(city)"]
        case .brewery: return ["craft beer in \(city)", "breweries in \(city)"]
        case .musicVenue: return ["live music in \(city)", "concert venues in \(city)"]
        case .movieTheater: return ["cinemas in \(city)"]
        case .hiking: return ["hiking trails near \(city)", "best hikes in \(city)"]
        case .campground: return ["camping near \(city)"]
        case .waterSports: return ["water sports in \(city)", "kayaking in \(city)"]
        case .sports: return ["sports venues in \(city)", "golf in \(city)"]
        case .recreation: return ["bowling in \(city)", "things to do for fun in \(city)"]
        }
    }

    /// Natural-language query used for the relevance-ranked search.
    var relevanceQuery: String {
        switch self {
        case .landmark: return "top tourist attractions and landmarks"
        case .museum: return "best museums"
        case .theater: return "theaters and performing arts"
        case .park: return "popular parks and gardens"
        case .beach: return "best beaches"
        case .nationalPark: return "national parks and nature reserves"
        case .store: return "popular shopping malls and markets"
        case .zoo: return "zoo"
        case .aquarium: return "aquarium"
        case .amusementPark: return "theme park and amusement park"
        case .foodMarket: return "food markets and local food"
        case .nightlife: return "popular bars and nightlife"
        case .spa: return "best spa and massage"
        case .brewery: return "craft beer and wine bars"
        case .musicVenue: return "live music venues"
        case .movieTheater: return "cinemas"
        case .hiking: return "hiking trails"
        case .campground: return "camping"
        case .waterSports: return "water sports"
        case .sports: return "sports venues"
        case .recreation: return "bowling and game centers"
        case .restaurant: return "best local restaurants"
        case .cafe: return "popular cafes"
        case .bakery: return "best bakeries"
        }
    }

    /// Whether a natural-language result is plausibly this kind. Food kinds
    /// must match their category exactly (otherwise "best restaurants"
    /// returns hotels); sight kinds only reject obvious non-destinations.
    func accepts(_ category: MKPointOfInterestCategory?) -> Bool {
        switch self {
        case .restaurant, .cafe, .bakery, .nightlife, .foodMarket, .store,
             .spa, .brewery, .musicVenue, .movieTheater, .hiking, .campground, .waterSports, .sports, .recreation:
            guard let category else { return false }
            return mapKitCategories.contains(category)
        default:
            guard let category else { return self == .landmark }
            if mapKitCategories.contains(category) { return true }
            let rejected: [MKPointOfInterestCategory] = [
                .hotel, .parking, .gasStation, .atm, .bank, .evCharger, .carRental, .laundry,
                .pharmacy, .hospital, .school, .police, .postOffice, .fireStation, .restaurant,
                .cafe, .bakery, .store, .foodMarket, .nightlife,
            ]
            return self == .landmark && !rejected.contains(category)
        }
    }

    /// Always a name from `ActivityIconLibrary.allIcons`, so planned stops
    /// render like any hand-added activity.
    var activityIconName: String {
        switch self {
        case .restaurant, .foodMarket: return "fork.knife"
        case .cafe, .bakery: return "cup.and.saucer"
        case .nightlife: return "wineglass"
        case .theater: return "theatermasks"
        case .landmark, .museum: return "camera"
        case .zoo, .aquarium, .amusementPark: return "ticket"
        case .park, .beach, .nationalPark: return "figure.walk.motion"
        case .store: return "mappin.and.ellipse"
        case .spa: return "star"
        case .brewery: return "wineglass"
        case .musicVenue: return "music.note"
        case .movieTheater: return "ticket"
        case .hiking: return "figure.walk"
        case .campground: return "tent"
        case .waterSports: return "figure.walk.motion"
        case .sports: return "bicycle"
        case .recreation: return "gamecontroller"
        }
    }
}
