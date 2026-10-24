import SwiftUI
import SwiftData
import FirebaseAuth

/// Starts a vote: either a free-form question with options, or a proposed
/// activity the group votes Yes/No on.
struct PollEditSheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var kind: PollKind = .question
    @State private var question = ""
    @State private var optionDrafts: [OptionDraft] = [OptionDraft(), OptionDraft()]

    // Proposal fields
    @State private var location = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var proposedDate: Date
    @State private var iconName = "mappin.and.ellipse"

    private static let maxOptions = 6

    private struct OptionDraft: Identifiable {
        let id = UUID()
        var text = ""
    }

    init(trip: Trip) {
        self.trip = trip
        _proposedDate = State(initialValue: trip.startDate)
    }

    private var dateRange: ClosedRange<Date> {
        let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: trip.endDate) ?? trip.endDate
        return trip.startDate...end
    }

    private var trimmedOptions: [String] {
        optionDrafts.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var isValid: Bool {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return kind == .activityProposal || trimmedOptions.count >= 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Type", selection: $kind) {
                        Text("Question").tag(PollKind.question)
                        Text("Activity").tag(PollKind.activityProposal)
                    }
                    .pickerStyle(.segmented)

                    switch kind {
                    case .question:
                        questionCards
                    case .activityProposal:
                        proposalCards
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .brandForm(accent: trip.theme.accentColor)
            .navigationTitle(kind == .question ? "New Poll" : "Propose Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var questionCards: some View {
        FormCard(title: "Question", icon: "questionmark.bubble", accent: trip.theme.accentColor) {
            FormField("Ask the group") {
                TextField("e.g. Which beach on day 2?", text: $question, axis: .vertical)
                    .lineLimit(1...3)
            }
        }

        FormCard(title: "Options", icon: "list.bullet", accent: trip.theme.accentColor) {
            ForEach($optionDrafts) { $draft in
                FormField {
                    HStack {
                        TextField("Option", text: $draft.text)
                        if optionDrafts.count > 2 {
                            Button {
                                optionDrafts.removeAll { $0.id == draft.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove option")
                        }
                    }
                }
            }
            if optionDrafts.count < Self.maxOptions {
                Button {
                    optionDrafts.append(OptionDraft())
                } label: {
                    Label("Add Option", systemImage: "plus.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var proposalCards: some View {
        FormCard(title: "Activity", icon: "mappin.and.ellipse", accent: trip.theme.accentColor) {
            FormField("Title") {
                TextField("e.g. Island hopping", text: $question)
            }
            FormField("Location") {
                LocationSearchField(
                    placeholder: "Location",
                    text: $location,
                    onSelect: { name, coordinate in
                        location = name
                        latitude = coordinate?.latitude
                        longitude = coordinate?.longitude
                    }
                )
            }
        }

        FormCard(title: "When", icon: "clock", accent: trip.theme.accentColor) {
            FormField {
                DatePicker("Date & Time", selection: $proposedDate, in: dateRange, displayedComponents: [.date, .hourAndMinute])
            }
        }

        FormCard(title: "Icon", icon: "square.grid.2x2", accent: trip.theme.accentColor) {
            IconPickerGrid(selectedIcon: $iconName, accentColor: trip.theme.accentColor)
                .frame(height: 260)
        }

        Text("Members vote Yes or No. If you approve it, it's added to the itinerary at this date and time.")
            .font(AppFont.outfit(12, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func save() {
        let poll = TripPoll(
            kind: kind,
            question: question.trimmingCharacters(in: .whitespaces),
            options: kind == .question ? trimmedOptions : ["Yes", "No"],
            createdByUID: authService.firebaseUser?.uid ?? "local",
            location: kind == .activityProposal ? location : "",
            latitude: kind == .activityProposal ? latitude : nil,
            longitude: kind == .activityProposal ? longitude : nil,
            iconName: iconName,
            proposedDate: kind == .activityProposal ? proposedDate : nil,
            trip: trip
        )
        modelContext.insert(poll)
        TripPollService.pushIfShared(poll, in: trip)
        dismiss()
    }
}
