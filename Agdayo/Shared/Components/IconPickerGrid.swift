import SwiftUI

struct IconPickerGrid: View {
    @Binding var selectedIcon: String
    let accentColor: Color

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ActivityIconLibrary.categories, id: \.name) { category in
                    IconPickerCategorySection(
                        title: category.name,
                        icons: category.icons,
                        columns: columns,
                        selectedIcon: $selectedIcon,
                        accentColor: accentColor
                    )
                }
            }
            .padding()
        }
    }
}

private struct IconPickerCategorySection: View {
    let title: String
    let icons: [String]
    let columns: [GridItem]
    @Binding var selectedIcon: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    IconPickerButton(
                        icon: icon,
                        isSelected: icon == selectedIcon,
                        accentColor: accentColor
                    ) {
                        selectedIcon = icon
                    }
                }
            }
        }
    }
}

private struct IconPickerButton: View {
    let icon: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(isSelected ? accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? accentColor : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
