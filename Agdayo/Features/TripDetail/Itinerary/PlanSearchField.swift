import SwiftUI

/// A search field with a visible Search button, so searching never depends
/// on finding the keyboard's return key.
struct PlanSearchField: View {
    let prompt: String
    @Binding var text: String
    var isSearching = false
    /// Hide the button when the caller searches as you type.
    var showsSearchButton = true
    let accent: Color
    let onSearch: () -> Void
    var onClear: () -> Void = {}

    private var canSearch: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .submitLabel(.search)
                    .onSubmit { if canSearch { onSearch() } }
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button {
                        text = ""
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            if showsSearchButton {
            Button(action: onSearch) {
                Group {
                    if isSearching {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text("Search")
                    }
                }
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .frame(minWidth: 52)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(accent.opacity(canSearch || isSearching ? 1 : 0.4), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSearch)
            } else if isSearching {
                ProgressView().controlSize(.small)
            }
        }
    }
}
