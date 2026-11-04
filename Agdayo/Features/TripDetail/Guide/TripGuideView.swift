import CoreLocation
import SwiftUI

/// "Know before you go" for the trip's country: getting around, money, plugs
/// and so on. Guides are written by Claude through the Agdayo connector and
/// stored on the Agdayo server; this screen only reads them.
struct TripGuideView: View {
    let trip: Trip

    @Environment(\.openURL) private var openURL
    @State private var state: LoadState = .loading
    @State private var otherGuides: [GuideSummary] = []
    @State private var countryName: String?

    private enum LoadState {
        case loading
        case loaded(CountryGuide)
        case missing
        case failed(String)
    }

    var body: some View {
        List {
            switch state {
            case .loading:
                HStack {
                    ProgressView()
                    Text("Loading the guide…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                }
            case .missing:
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No guide for \(countryName ?? trip.location) yet")
                            .font(AppFont.outfit(17, weight: .semibold, relativeTo: .headline))
                        Text("Ask Claude, with the Agdayo connector on: “Write a Know before you go guide for \(countryName ?? trip.location) and save it to Agdayo.”")
                            .font(AppFont.outfit(15, relativeTo: .body))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            case .loaded(let guide):
                GuideSections(guide: guide, accentColor: trip.theme.accentColor)
            }

            if !otherGuides.isEmpty {
                Section("Other guides") {
                    ForEach(otherGuides) { summary in
                        NavigationLink(summary.title) {
                            StoredGuideView(summary: summary, accentColor: trip.theme.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Know before you go")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        let code = await countryCode()
        do {
            async let all = AgdayoServer.guides()
            if let code, let guide = try await AgdayoServer.guide(countryCode: code) {
                state = .loaded(guide)
            } else {
                state = .missing
            }
            otherGuides = try await all.filter { $0.countryCode != code }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// The trip's ISO country code, from its pinned location.
    private func countryCode() async -> String? {
        guard let coordinate = trip.coordinate else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        countryName = placemark.country
        return placemark.isoCountryCode
    }
}

/// A guide picked from "Other guides".
private struct StoredGuideView: View {
    let summary: GuideSummary
    let accentColor: Color
    @State private var guide: CountryGuide?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let guide {
                GuideSections(guide: guide, accentColor: accentColor)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                guide = try await AgdayoServer.guide(countryCode: summary.countryCode)
                if guide == nil { errorMessage = "This guide was removed." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct GuideSections: View {
    let guide: CountryGuide
    let accentColor: Color
    @Environment(\.openURL) private var openURL

    var body: some View {
        ForEach(guide.sections) { section in
            Section {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(accentColor).frame(width: 6, height: 6)
                        Text(item.text)
                            .font(AppFont.outfit(15, relativeTo: .body))
                        if let source = item.source, let url = URL(string: source) {
                            Spacer(minLength: 4)
                            Button {
                                openURL(url)
                            } label: {
                                Image(systemName: "link").font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Source")
                        }
                    }
                }
            } header: {
                Label(section.title, systemImage: Self.symbol(for: section.id))
            }
        }
        Section {
            ForEach(Array(guide.sources.enumerated()), id: \.offset) { _, source in
                if let url = URL(string: source.url) {
                    Link(source.title, destination: url)
                        .font(AppFont.outfit(14, relativeTo: .subheadline))
                }
            }
        } header: {
            if !guide.sources.isEmpty { Text("Sources") }
        } footer: {
            Text("Facts checked \(guide.checkedAt.formatted(date: .abbreviated, time: .omitted)). Rules and prices change, so double-check anything important.")
        }
    }

    /// Icons for the section keys Claude is asked to use.
    static func symbol(for id: String) -> String {
        switch id {
        case "getting-around", "transport": return "tram.fill"
        case "money", "payments", "currency": return "banknote"
        case "plugs", "power": return "powerplug"
        case "sim", "internet", "connectivity": return "simcard"
        case "etiquette", "culture", "customs": return "hands.sparkles"
        case "safety", "emergency": return "cross.case"
        case "entry", "visa", "arrival": return "airplane.arrival"
        case "food", "eating": return "fork.knife"
        case "weather", "climate": return "sun.max"
        default: return "info.circle"
        }
    }
}
