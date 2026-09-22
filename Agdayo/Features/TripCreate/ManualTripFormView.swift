import SwiftUI
import SwiftData

struct ManualTripFormView: View {
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var location = ""
    @State private var theme: TripTheme = .peach
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var overallBudget = ""
    @State private var currency = "PHP"
    @State private var tripDescription = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !location.trimmingCharacters(in: .whitespaces).isEmpty
            && startDate <= endDate
    }

    var body: some View {
        Form {
            Section("Trip") {
                TextField("Trip Name", text: $name)
                LocationSearchField(
                    placeholder: "Destination",
                    text: $location,
                    onSelect: { name, _ in location = name }
                )
            }

            Section("Theme") {
                ThemeSwatchPicker(selectedTheme: $theme)
            }

            Section("Dates") {
                DatePicker("Start", selection: $startDate, in: ...endDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
            }

            Section("Budget") {
                TextField("Overall Budget", text: $overallBudget)
                    .keyboardType(.decimalPad)
                Picker("Currency", selection: $currency) {
                    ForEach(CurrencyCode.common, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }

            Section("Description") {
                TextField("Optional notes about this trip", text: $tripDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Create Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
    }

    private func save() {
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespaces),
            location: location.trimmingCharacters(in: .whitespaces),
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            overallBudget: Double(overallBudget) ?? 0,
            currency: currency,
            tripDescription: tripDescription
        )
        modelContext.insert(trip)
        onSaved()
    }
}

private struct ThemeSwatchPicker: View {
    @Binding var selectedTheme: TripTheme

    var body: some View {
        HStack(spacing: 16) {
            ForEach(TripTheme.allCases) { theme in
                Button {
                    selectedTheme = theme
                } label: {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(.primary, lineWidth: selectedTheme == theme ? 2 : 0)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(selectedTheme == theme ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
