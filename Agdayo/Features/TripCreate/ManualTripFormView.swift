import SwiftUI
import SwiftData
import MapKit
import FirebaseAuth

private enum CreateTripStep {
    case destination, dates, details
}

struct ManualTripFormView: View {
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var step: CreateTripStep = .destination

    @State private var name = ""
    @State private var location = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var theme: TripTheme = .peach
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var overallBudget = ""
    @State private var currency = "PHP"
    @State private var tripDescription = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !location.trimmingCharacters(in: .whitespaces).isEmpty
            && startDate != nil && endDate != nil
    }

    var body: some View {
        Group {
            switch step {
            case .destination:
                DestinationStepView(location: $location, latitude: $latitude, longitude: $longitude) {
                    withAnimation { step = .dates }
                }
            case .dates:
                DateStepView(
                    startDate: $startDate,
                    endDate: $endDate,
                    onBack: { withAnimation { step = .destination } },
                    onNext: { withAnimation { step = .details } }
                )
            case .details:
                DetailsStepView(
                    name: $name,
                    theme: $theme,
                    overallBudget: $overallBudget,
                    currency: $currency,
                    tripDescription: $tripDescription,
                    canSave: isValid,
                    onBack: { withAnimation { step = .dates } },
                    onSave: save
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        guard let startDate, let endDate else { return }
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespaces),
            location: location.trimmingCharacters(in: .whitespaces),
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            overallBudget: Double(overallBudget) ?? 0,
            currency: currency,
            tripDescription: tripDescription,
            latitude: latitude,
            longitude: longitude
        )
        modelContext.insert(trip)
        if let uid = authService.firebaseUser?.uid {
            // `ownerUID` is only set once the Firestore write actually
            // succeeds — setting it optimistically beforehand would make a
            // failed (e.g. offline) upload look "already synced," so
            // `RootTabView`'s backfill would never retry it.
            Task { @MainActor in
                do {
                    try await TripMembershipService.createTripRecord(
                        tripID: trip.id, ownerUID: uid, name: trip.name, location: trip.location,
                        theme: trip.theme.rawValue, startDate: trip.startDate, endDate: trip.endDate,
                        overallBudget: trip.overallBudget, currency: trip.currency, tripDescription: trip.tripDescription,
                        latitude: trip.latitude, longitude: trip.longitude
                    )
                    trip.ownerUID = uid
                } catch {
                    // Left local-only; RootTabView's backfill retries next
                    // sign-in-state change or app foreground.
                }
            }
        }
        onSaved()
    }
}

private struct DestinationStepView: View {
    @Binding var location: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    var onSelect: () -> Void

    @State private var model = LocationSearchModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Where are you planning your next trip?")
                .font(AppFont.outfit(28, weight: .bold, relativeTo: .largeTitle))
                .padding(.horizontal)
                .padding(.top, 12)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search destinations", text: $location)
                    .focused($isFocused)
                    .onChange(of: location) { _, newValue in
                        model.queryFragment = newValue
                    }
                if !location.isEmpty {
                    Button {
                        location = ""
                        model.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            if model.results.isEmpty {
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.results, id: \.self) { result in
                            Button {
                                pick(result)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(Color.appPrimary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .foregroundStyle(.primary)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(AppFont.outfit(12, relativeTo: .caption))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("destinationSearchResult")
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .onAppear { isFocused = true }
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        isFocused = false
        Task {
            do {
                let item = try await model.resolve(completion)
                location = completion.title
                latitude = item.placemark.coordinate.latitude
                longitude = item.placemark.coordinate.longitude
            } catch {
                location = completion.title
                latitude = nil
                longitude = nil
            }
            onSelect()
        }
    }
}

private struct DateStepView: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    var onBack: () -> Void
    var onNext: () -> Void

    private var summary: String {
        guard let startDate else { return "Add your travel dates" }
        guard let endDate else {
            return startDate.formatted(date: .abbreviated, time: .omitted) + " – pick an end date"
        }
        let nights = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted)) · \(nights) night\(nights == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When's your trip?")
                .font(AppFont.outfit(32, weight: .bold, relativeTo: .largeTitle))
                .padding(.horizontal)
                .padding(.top, 12)

            Text(summary)
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            TripDateRangeCalendar(startDate: $startDate, endDate: $endDate)

            WizardBottomBar(
                nextTitle: "Next",
                isNextEnabled: startDate != nil && endDate != nil,
                onBack: onBack,
                onNext: onNext
            )
        }
    }
}

private struct DetailsStepView: View {
    @Binding var name: String
    @Binding var theme: TripTheme
    @Binding var overallBudget: String
    @Binding var currency: String
    @Binding var tripDescription: String
    let canSave: Bool
    var onBack: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Trip") {
                    TextField("Trip Name", text: $name)
                }

                Section("Theme") {
                    ThemeSwatchPicker(selectedTheme: $theme)
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

            WizardBottomBar(
                nextTitle: "Create Trip",
                isNextEnabled: canSave,
                onBack: onBack,
                onNext: onSave
            )
        }
    }
}

private struct WizardBottomBar: View {
    let nextTitle: String
    let isNextEnabled: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)

            Button(nextTitle, action: onNext)
                .buttonStyle(.appPrimary)
                .disabled(!isNextEnabled)
        }
        .padding()
        .background(.bar)
    }
}

private struct ThemeSwatchPicker: View {
    @Binding var selectedTheme: TripTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                    .accessibilityAddTraits(selectedTheme == theme ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 4)
    }
}
