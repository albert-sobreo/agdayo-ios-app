import SwiftUI
import SwiftData

/// The "Generate More Activities" entry point for an existing trip — reuses
/// the trip's existing name/location/dates/budget, so only a free-text
/// request is needed before generating and reviewing new suggestions.
struct AIGenerateMoreActivitiesView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @State private var availability = AIAvailability()
    @State private var additionalDetails = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedItinerary: GeneratedItinerary?
    @State private var isShowingReview = false

    var body: some View {
        NavigationStack {
            Group {
                if let message = availability.unavailableMessage {
                    EmptyStateView(iconName: "sparkles", title: "AI Unavailable", message: message)
                } else {
                    form
                }
            }
            .navigationTitle("Generate More Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isShowingReview) {
                if let generatedItinerary {
                    AIReviewResultsView(
                        tripName: trip.name,
                        location: trip.location,
                        theme: trip.theme,
                        startDate: trip.startDate,
                        endDate: trip.endDate,
                        overallBudget: trip.overallBudget,
                        currency: trip.currency,
                        existingTrip: trip,
                        itinerary: generatedItinerary,
                        onSaved: { dismiss() }
                    )
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section("What would you like to add?") {
                TextField("e.g. \"more food spots on day 2\"", text: $additionalDetails, axis: .vertical)
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
                        Text("Generate Suggestions")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isGenerating)
                .buttonStyle(.appPrimary)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            }
        }
    }

    private func generate() {
        isGenerating = true
        generationError = nil
        let details = additionalDetails
        let profile = profiles.first
        Task {
            defer { isGenerating = false }
            do {
                let itinerary = try await AIGenerationService().generateItinerary(
                    tripName: trip.name,
                    location: trip.location,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    budget: trip.overallBudget,
                    currency: trip.currency,
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
