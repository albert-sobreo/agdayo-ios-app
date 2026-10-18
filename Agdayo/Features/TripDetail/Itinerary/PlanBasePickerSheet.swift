import SwiftUI
import MapKit

/// Lets the traveler choose which town or city a day should be planned
/// around — for multi-city trips and far day trips.
struct PlanBasePickerSheet: View {
    let accent: Color
    let onPick: (PlanBase) -> Void
    let onUseAutomatic: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onUseAutomatic()
                        dismiss()
                    } label: {
                        Label("Use the automatic suggestion", systemImage: "wand.and.stars")
                            .foregroundStyle(.black)
                    }
                }

                Section {
                    ForEach(results, id: \.self) { item in
                        Button {
                            pick(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(for: item))
                                    .foregroundStyle(.black)
                                if let subtitle = subtitle(for: item) {
                                    Text(subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.black)
                                }
                            }
                        }
                    }
                } header: {
                    if hasSearched && results.isEmpty && !isSearching {
                        Text("No places found")
                            .foregroundStyle(.black)
                    }
                }
            }
            .overlay { if isSearching { ProgressView() } }
            // At the bottom, with a visible Search button, so nothing depends
            // on the keyboard's return key.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlanSearchField(
                    prompt: "Town or city, e.g. Tagaytay",
                    text: $query,
                    isSearching: isSearching,
                    showsSearchButton: false,
                    accent: accent,
                    onSearch: { Task { await search() } },
                    onClear: {
                        results = []
                        hasSearched = false
                    }
                )
                .padding()
                .background(.bar)
            }
            .foregroundStyle(.black)
            // Search as you type: wait for a short pause, and let the next
            // keystroke cancel the previous lookup (`task(id:)` does that).
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 2 else {
                    results = []
                    hasSearched = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await search()
            }
            .navigationTitle("Plan around…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.black)
                }
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false; if !Task.isCancelled { hasSearched = true } }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let found = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        // A newer keystroke may have replaced this lookup while it ran.
        guard !Task.isCancelled else { return }
        results = found
    }

    private func title(for item: MKMapItem) -> String {
        item.placemark.locality ?? item.name ?? "Unknown place"
    }

    private func subtitle(for item: MKMapItem) -> String? {
        let parts = [item.name, item.placemark.administrativeArea, item.placemark.country]
            .compactMap { $0 }
            .filter { $0 != title(for: item) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func pick(_ item: MKMapItem) {
        onPick(PlanBase(name: title(for: item), coordinate: item.placemark.coordinate, reason: "Chosen by you"))
        dismiss()
    }
}
