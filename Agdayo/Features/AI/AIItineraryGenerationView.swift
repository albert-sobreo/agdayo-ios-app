import SwiftUI
import SwiftData

struct AIItineraryGenerationView: View {
    var onSaved: () -> Void = {}

    @Query private var profiles: [UserProfile]
    @State private var availability = AIAvailability()

    @State private var tripName = ""
    @State private var location = ""
    @State private var theme: TripTheme = .peach
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var overallBudget = ""
    @State private var currency = "PHP"
    @State private var additionalDetails = ""

    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedItinerary: GeneratedItinerary?
    @State private var isShowingReview = false

    private var isValid: Bool {
        !tripName.trimmingCharacters(in: .whitespaces).isEmpty
            && !location.trimmingCharacters(in: .whitespaces).isEmpty
            && startDate <= endDate
    }

    var body: some View {
        Group {
            if let message = availability.unavailableMessage {
                EmptyStateView(iconName: "sparkles", title: "AI Unavailable", message: message)
            } else {
                form
            }
        }
        .navigationTitle("Generate with AI")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingReview) {
            if let generatedItinerary {
                AIReviewResultsView(
                    tripName: tripName.trimmingCharacters(in: .whitespaces),
                    location: location.trimmingCharacters(in: .whitespaces),
                    theme: theme,
                    startDate: startDate,
                    endDate: endDate,
                    overallBudget: Double(overallBudget) ?? 0,
                    currency: currency,
                    itinerary: generatedItinerary,
                    onSaved: onSaved
                )
            }
        }
    }

    private var form: some View {
        Form {
            Section("Trip") {
                TextField("Trip Name", text: $tripName)
                LocationSearchField(placeholder: "Destination", text: $location, onSelect: { name, _ in location = name })
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

            Section("What are you looking for?") {
                TextField("e.g. \"food-focused, relaxed pace\"", text: $additionalDetails, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let generationError {
                Section {
                    Text(generationError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Button {
                    generate()
                } label: {
                    if isGenerating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Generate Itinerary")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isValid || isGenerating)
                .buttonStyle(.appPrimary)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            }
        }
    }

    private func generate() {
        isGenerating = true
        generationError = nil
        let name = tripName
        let dest = location
        let start = startDate
        let end = endDate
        let budget = Double(overallBudget) ?? 0
        let curr = currency
        let details = additionalDetails
        let profile = profiles.first
        Task {
            defer { isGenerating = false }
            do {
                let itinerary = try await AIGenerationService().generateItinerary(
                    tripName: name,
                    location: dest,
                    startDate: start,
                    endDate: end,
                    budget: budget,
                    currency: curr,
                    additionalDetails: details,
                    profile: profile
                )
                generatedItinerary = itinerary
                isShowingReview = true
            } catch {
                generationError = "Couldn't generate suggestions right now. Please try again."
            }
        }
    }
}
