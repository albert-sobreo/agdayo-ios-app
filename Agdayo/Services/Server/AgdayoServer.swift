import CoreLocation
import FirebaseAuth
import Foundation

/// Agdayo's own server (the Cloudflare Worker in `worker/`). It holds the
/// Google key and answers with Google routes. Only accounts on the server's
/// allowlist get through, so the address is fine to keep in the repo.
enum AgdayoServer {
    static let baseURL = URL(string: "https://agdayo.albertcorpmail.workers.dev")!

    enum ServerError: LocalizedError {
        case signedOut
        case notAllowed
        case notFound
        case server(String)

        var errorDescription: String? {
            switch self {
            case .signedOut: return "Sign in to see transit steps."
            case .notAllowed: return "This account can't use the Agdayo server."
            case .notFound: return "Not found on the Agdayo server."
            case .server(let message): return message
            }
        }
    }

    /// A transit route from Google, or nil when Google has no route (often no
    /// transit data in that city). `arriveBy` asks for a route that gets
    /// there by that time.
    static func transitRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, arriveBy: Date?) async throws -> ServerRoute? {
        var body: [String: Any] = [
            "origin": ["latitude": origin.latitude, "longitude": origin.longitude],
            "destination": ["latitude": destination.latitude, "longitude": destination.longitude],
            "mode": "transit",
        ]
        // Google only has timetables for roughly the coming weeks; a past
        // time is meaningless, so plan for now in that case.
        if let arriveBy, arriveBy > .now {
            body["arrivalTime"] = ISO8601DateFormatter().string(from: arriveBy)
        }
        let data = try await post("/v1/route", body: body)
        return try decoder.decode(RouteResponse.self, from: data).route
    }

    /// Every saved country guide, by title.
    static func guides() async throws -> [GuideSummary] {
        struct Response: Decodable { let guides: [GuideSummary] }
        let data = try await send("GET", "/v1/guides")
        return try decoder.decode(Response.self, from: data).guides
    }

    /// The guide for a two-letter country code, or nil when there isn't one yet.
    static func guide(countryCode: String) async throws -> CountryGuide? {
        struct Response: Decodable { let guide: CountryGuide }
        do {
            let data = try await send("GET", "/v1/guides/\(countryCode.uppercased())")
            return try decoder.decode(Response.self, from: data).guide
        } catch ServerError.notFound {
            return nil
        }
    }

    private struct RouteResponse: Decodable {
        let route: ServerRoute?
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private static func post(_ path: String, body: [String: Any]) async throws -> Data {
        try await send("POST", path, body: try JSONSerialization.data(withJSONObject: body))
    }

    private static func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let user = Auth.auth().currentUser else { throw ServerError.signedOut }
        let token = try await user.getIDToken()
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 403 { throw ServerError.notAllowed }
            if status == 404 { throw ServerError.notFound }
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw ServerError.server(message ?? "The Agdayo server answered \(status).")
        }
        return data
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let text = try container.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Bad date: \(text)"))
        }
        return decoder
    }()

    /// ISO 8601 with or without fractional seconds. Google can send up to
    /// nine digits, which ISO8601DateFormatter rejects, so they're dropped.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

/// Mirrors `RouteResult` in worker/src/google.ts.
struct ServerRoute: Decodable {
    let mode: String
    let durationSeconds: Double
    let distanceMeters: Double
    let fare: Fare?
    let steps: [Step]
    /// True when Google had no timetable for the requested time and planned for now instead.
    let timeAdjusted: Bool
    let fetchedAt: Date

    struct Fare: Decodable {
        let currency: String
        let amount: Double
        let text: String?
    }

    struct Step: Decodable {
        /// "walk", "transit", "drive" or "bicycle".
        let kind: String
        let durationSeconds: Double
        let distanceMeters: Double
        let instruction: String?
        let transit: TransitLeg?
    }

    struct TransitLeg: Decodable {
        let lineName: String
        let lineShortName: String?
        let vehicle: String
        let color: String?
        let textColor: String?
        let headsign: String?
        let departureStop: String
        let arrivalStop: String
        let departureTime: Date?
        let arrivalTime: Date?
        let stopCount: Int?
    }

    /// When the first train or bus leaves, for a "Leave by" headline.
    var firstDeparture: Date? { steps.lazy.compactMap { $0.transit?.departureTime }.first }
}

/// Mirrors the summaries from `GET /v1/guides`.
struct GuideSummary: Decodable, Identifiable, Hashable {
    let countryCode: String
    let title: String
    let checkedAt: Date
    var id: String { countryCode }
}

/// Mirrors `Guide` in worker/src/guides.ts: a "Know before you go" guide,
/// usually researched and saved by Claude through the connector.
struct CountryGuide: Decodable {
    let countryCode: String
    let title: String
    let sections: [Section]
    let sources: [Source]
    let checkedAt: Date

    struct Section: Decodable, Identifiable {
        let id: String
        let title: String
        let items: [Item]
    }

    struct Item: Decodable {
        let text: String
        let source: String?
    }

    struct Source: Decodable {
        let title: String
        let url: String
    }
}
