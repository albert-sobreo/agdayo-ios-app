import SwiftUI
import MapKit

/// Reusable location search + autocomplete field. On selection, resolves the
/// chosen completion to a real coordinate via MKLocalSearch before calling
/// `onSelect`, replacing the web app's Google Places Autocomplete usage.
struct LocationSearchField: View {
    let placeholder: String
    @Binding var text: String
    var regionBiasCenter: CLLocationCoordinate2D?
    var onSelect: (_ name: String, _ coordinate: CLLocationCoordinate2D?) -> Void

    @State private var model = LocationSearchModel()
    @State private var isResolving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .onChange(of: text) {
                        model.queryFragment = text
                    }
                if isResolving {
                    ProgressView()
                }
            }
            if isFocused && !model.results.isEmpty {
                LocationSearchResultsList(results: model.results, onPick: pick)
            }
        }
        .onAppear {
            if let regionBiasCenter {
                model.setRegionBias(center: regionBiasCenter)
            }
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        text = completion.title
        isFocused = false
        model.clearResults()
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                let item = try await model.resolve(completion)
                onSelect(completion.title, item.placemark.coordinate)
            } catch {
                onSelect(completion.title, nil)
            }
        }
    }
}

private struct LocationSearchResultsList: View {
    let results: [MKLocalSearchCompletion]
    let onPick: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(results, id: \.self) { result in
                Button {
                    onPick(result)
                } label: {
                    LocationSearchResultRow(title: result.title, subtitle: result.subtitle)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct LocationSearchResultRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
