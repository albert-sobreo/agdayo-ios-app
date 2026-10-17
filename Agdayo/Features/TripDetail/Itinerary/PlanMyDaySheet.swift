import SwiftUI
import SwiftData

/// "Plan my day": pick interests + pace, get a draft day built from real
/// nearby places (no AI — MapKit search + `DayPlanner`), review it, then add
/// the stops to the itinerary as regular activities.
struct PlanMyDaySheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var model: PlanMyDayModel
    @State private var hasSeededInterests = false

    /// - Parameter initialDay: The day to plan; when `nil` (opened from the
    ///   toolbar rather than an empty-day row) the first day with nothing
    ///   planned, falling back to the trip's first day.
    init(trip: Trip, initialDay: Date? = nil) {
        self.trip = trip
        let calendar = Calendar.current
        let day: Date
        if let initialDay {
            day = calendar.startOfDay(for: initialDay)
        } else {
            let used = Set(trip.activities.map { calendar.startOfDay(for: $0.date) })
            day = trip.calendarDays.first { !used.contains($0) } ?? calendar.startOfDay(for: trip.startDate)
        }
        _model = State(initialValue: PlanMyDayModel(trip: trip, day: day, interests: [.food, .culture]))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .setup:
                    setupView
                case .loading:
                    loadingView
                case .results:
                    resultsView
                case .failed(let message):
                    EmptyStateView(
                        iconName: "mappin.slash",
                        title: "Couldn't Plan This Day",
                        message: message,
                        actionTitle: "Change Plan",
                        action: { model.backToSetup() }
                    )
                }
            }
            .navigationTitle("Plan My Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if model.phase == .results {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Shuffle", systemImage: "shuffle") {
                            withAnimation { model.shuffle() }
                        }
                    }
                }
            }
            .onAppear(perform: seedInterestsFromProfile)
        }
    }

    // MARK: Setup

    private var setupView: some View {
        Form {
            Section("Day") {
                Picker("Day", selection: $model.day) {
                    ForEach(Array(trip.calendarDays.enumerated()), id: \.element) { index, day in
                        Text("Day \(index + 1) · \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                            .tag(day)
                    }
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(Interest.allCases) { interest in
                        interestChip(interest)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("What are you into?")
            }

            Section {
                Picker("Pace", selection: $model.pace) {
                    ForEach(Pace.allCases) { pace in
                        Text(pace.displayName).tag(pace)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("How busy?")
            } footer: {
                Text(paceDescription(model.pace))
            }

            Section {
                Button {
                    Task { await model.plan() }
                } label: {
                    Text("Plan")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func interestChip(_ interest: Interest) -> some View {
        let isSelected = model.interests.contains(interest)
        return Button {
            if isSelected {
                model.interests.remove(interest)
            } else {
                model.interests.insert(interest)
            }
        } label: {
            Label(interest.displayName, systemImage: interest.iconName)
                .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? .white : trip.theme.accentColor)
                .background(
                    isSelected ? trip.theme.accentColor : trip.theme.lightTintColor,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func paceDescription(_ pace: Pace) -> String {
        switch pace {
        case .relaxed: return "A sight, lunch, and dinner."
        case .balanced: return "Two sights with lunch and dinner."
        case .packed: return "Three sights, lunch, a coffee break, and an evening out."
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            ShimmerText(
                text: "Finding places near \(trip.location)…",
                font: AppFont.outfit(15, weight: .semibold, relativeTo: .body)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Results

    private var resultsView: some View {
        List {
            Section {
                Button("Change interests or pace", systemImage: "slider.horizontal.3") {
                    model.backToSetup()
                }
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
            }

            Section {
                ForEach(model.stops) { stop in
                    stopRow(stop)
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                withAnimation { model.remove(stop) }
                            }
                        }
                }
            } header: {
                Text("Your day")
            } footer: {
                if model.plannedCount == 0 {
                    Text("Nothing matched nearby. Try other interests, or a different pace.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.commit(modelContext: modelContext)
                dismiss()
            } label: {
                Text(model.plannedCount == 1 ? "Add 1 stop to day" : "Add \(model.plannedCount) stops to day")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .disabled(model.plannedCount == 0)
            .padding()
            .background(.bar)
        }
    }

    private func stopRow(_ stop: PlannedStop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeLabel(for: stop.slot))
                .font(AppFont.barlowCondensed(18, weight: .semibold))
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(trip.theme.accentColor)

            if let candidate = stop.candidate {
                Image(systemName: candidate.kind.activityIconName)
                    .foregroundStyle(trip.theme.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                    Text(subtitle(for: candidate))
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No match nearby")
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.secondary)
                    Text("Try other interests for this slot.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for candidate: Candidate) -> String {
        let kind = candidate.kind.rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
        guard let locality = candidate.locality else { return kind }
        return "\(kind) · \(locality)"
    }

    private func timeLabel(for slot: SlotTemplate) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: calendar.startOfDay(for: model.day)) ?? model.day
        return date.formatted(.dateTime.hour().minute())
    }

    // MARK: Defaults

    /// Pre-selects interests from the profile's preferred vacation types the
    /// first time the sheet appears — the traveler can still change them.
    private func seedInterestsFromProfile() {
        guard !hasSeededInterests else { return }
        hasSeededInterests = true
        guard let types = profiles.first?.preferredVacationTypes, !types.isEmpty else { return }
        var seeded = Set<Interest>()
        for type in types {
            switch type {
            case .beaches, .parks, .mountains, .province:
                seeded.insert(.nature)
            case .cities:
                seeded.formUnion([.culture, .shopping])
            case .other:
                break
            }
        }
        if !seeded.isEmpty {
            model.interests = seeded
        }
    }
}
