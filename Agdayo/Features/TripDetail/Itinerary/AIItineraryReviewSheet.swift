import SwiftUI
import SwiftData
import MapKit

/// Prompt → generate → review flow for AI itinerary generation. Never
/// bulk-inserts the model's output directly: every time block shows 2-3
/// alternative options (ranked closest-to-previous-pick first by
/// `ItineraryDistanceRanking`), with the top option pre-checked as
/// "Recommended" and a real ETA shown. Each option has its own checkbox, so
/// picking more than one from the same block is fine (e.g. two nearby
/// attractions worth doing back to back) — selected activities within a
/// block are automatically staggered on commit so their times don't collide.
@available(iOS 26.0, *)
struct AIItineraryReviewSheet: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var prompt: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var days: [GeneratedDay] = []
    /// uid = "\(dayIndex)-\(blockIndex)"; value is the set of selected
    /// option indices within that block's `options` (empty = nothing from
    /// this block).
    @State private var selectedOptionIndices: [String: Set<Int>] = [:]
    /// uid = "\(blockID)-\(optionIndex)"
    @State private var etaCaptions: [String: String] = [:]
    /// Keyed by `option.location` — populated as a side effect of ETA
    /// lookups, then reused at commit time so committed activities land on
    /// the map instead of getting `nil` coordinates.
    @State private var resolvedCoordinates: [String: CLLocationCoordinate2D] = [:]

    /// Minimum gap between two activities picked from the same time block,
    /// so committing more than one doesn't schedule them at the same instant.
    private static let staggerInterval: TimeInterval = 90 * 60

    private var selectedCount: Int {
        selectedOptionIndices.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    promptView
                } else {
                    reviewView
                }
            }
            .navigationTitle("Generate Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !days.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add \(selectedCount) to Itinerary") {
                            commit()
                        }
                        .disabled(selectedCount == 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var promptView: some View {
        Form {
            Section {
                TextField("e.g. \"3 days, food-focused, low budget\"", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("What kind of trip?")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(AppFont.outfit(13, relativeTo: .footnote))
                }
            }

            Section {
                if isGenerating {
                    VStack(spacing: 10) {
                        ShimmerText(
                            text: "Finding real places near \(trip.location)…",
                            font: AppFont.outfit(15, weight: .semibold, relativeTo: .body)
                        )
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    Button {
                        Task { await generate() }
                    } label: {
                        Text("Generate")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var reviewView: some View {
        List {
            ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, day in
                Section(dayHeader(day)) {
                    ForEach(Array(day.timeBlocks.enumerated()), id: \.offset) { blockIndex, block in
                        blockSection(block, blockID: "\(dayIndex)-\(blockIndex)")
                    }
                }
            }

            Section {
                if isGenerating {
                    HStack {
                        Spacer()
                        ShimmerText(
                            text: "Regenerating…",
                            font: AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline)
                        )
                        Spacer()
                    }
                } else {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func blockSection(_ block: GeneratedTimeBlock, blockID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(block.label.uppercased())
                Text("· \(block.time)")
            }
            .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(.secondary)

            ForEach(Array(block.options.enumerated()), id: \.offset) { optionIndex, option in
                optionRow(option, optionIndex: optionIndex, blockID: blockID)
            }
        }
        .padding(.vertical, 4)
    }

    private func optionRow(_ option: GeneratedActivity, optionIndex: Int, blockID: String) -> some View {
        let isSelected = selectedOptionIndices[blockID]?.contains(optionIndex) ?? false
        let isRecommended = optionIndex == 0
        let etaKey = "\(blockID)-\(optionIndex)"
        return Button {
            toggleSelection(optionIndex: optionIndex, blockID: blockID)
            if isSelected == false {
                Task { await loadETA(for: option, key: etaKey) }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.appPrimary : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: clampedIconName(option.iconName))
                            .foregroundStyle(trip.theme.accentColor)
                        Text(option.title)
                            .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        if isRecommended {
                            PillTag(text: "Recommended", background: trip.theme.lightTintColor, foreground: trip.theme.accentColor)
                        }
                    }
                    if !option.location.isEmpty {
                        Text(option.location)
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(option.cost.formattedCurrency(code: validCurrencyCode(option.costCurrency)))
                        if isSelected, let eta = etaCaptions[etaKey] {
                            Text("· \(eta)")
                        }
                    }
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(optionIndex: Int, blockID: String) {
        var current = selectedOptionIndices[blockID] ?? []
        if current.contains(optionIndex) {
            current.remove(optionIndex)
        } else {
            current.insert(optionIndex)
        }
        selectedOptionIndices[blockID] = current
    }

    private func dayHeader(_ day: GeneratedDay) -> String {
        guard let date = Self.isoDateFormatter.date(from: day.date) else { return day.date }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func clampedIconName(_ iconName: String) -> String {
        ActivityIconLibrary.allIcons.contains(iconName) ? iconName : "mappin.and.ellipse"
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        do {
            let generatedDays = try await ItineraryGenerationService.generate(for: trip, prompt: prompt)
            days = generatedDays
            initializeSelections(for: generatedDays)
            await loadInitialETAs(for: generatedDays)
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    /// Every block defaults to just its recommended (closest-ranked) option
    /// checked — committing with zero taps still produces a geographically
    /// coherent day. Users can check additional options per block.
    private func initializeSelections(for days: [GeneratedDay]) {
        var next: [String: Set<Int>] = [:]
        for (dayIndex, day) in days.enumerated() {
            for (blockIndex, block) in day.timeBlocks.enumerated() where !block.options.isEmpty {
                next["\(dayIndex)-\(blockIndex)"] = [0]
            }
        }
        selectedOptionIndices = next
        etaCaptions = [:]
    }

    private func loadInitialETAs(for days: [GeneratedDay]) async {
        var anchor = trip.coordinate
        for (dayIndex, day) in days.enumerated() {
            for (blockIndex, block) in day.timeBlocks.enumerated() {
                guard let first = block.options.first else { continue }
                let blockID = "\(dayIndex)-\(blockIndex)"
                if let anchor {
                    await loadETA(for: first, key: "\(blockID)-0", anchor: anchor)
                }
                anchor = await ItineraryDistanceRanking.resolveCoordinate(for: first.location, near: trip.coordinate ?? anchor ?? CLLocationCoordinate2D(latitude: 0, longitude: 0))
            }
        }
    }

    private func loadETA(for option: GeneratedActivity, key: String, anchor: CLLocationCoordinate2D? = nil) async {
        guard let tripCenter = trip.coordinate else { return }
        let from = anchor ?? tripCenter
        guard let to = await ItineraryDistanceRanking.resolveCoordinate(for: option.location, near: tripCenter) else { return }
        resolvedCoordinates[option.location] = to
        guard let estimate = try? await TravelEstimateService.estimate(from: from, to: to, transportType: .automobile) else { return }
        etaCaptions[key] = formattedETA(estimate)
    }

    /// The model is asked for a 3-letter code but isn't guaranteed to comply —
    /// fall back to the trip's own currency if what it returned looks invalid.
    private func validCurrencyCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.count == 3 ? trimmed : trip.currency
    }

    private func formattedETA(_ estimate: TravelEstimate) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        let time = formatter.string(from: estimate.duration) ?? "\(Int(estimate.duration / 60)) min"
        return "\(time) away"
    }

    private func commit() {
        for (dayIndex, day) in days.enumerated() {
            for (blockIndex, block) in day.timeBlocks.enumerated() {
                let blockID = "\(dayIndex)-\(blockIndex)"
                let indices = (selectedOptionIndices[blockID] ?? []).sorted()
                guard !indices.isEmpty else { continue }
                let baseDate = Self.combine(dateString: day.date, timeString: block.time) ?? trip.startDate
                for (position, optionIndex) in indices.enumerated() {
                    guard optionIndex < block.options.count else { continue }
                    let scheduledDate = baseDate.addingTimeInterval(TimeInterval(position) * Self.staggerInterval)
                    insertActivity(from: block.options[optionIndex], date: scheduledDate)
                }
            }
        }
        dismiss()
    }

    private func insertActivity(from option: GeneratedActivity, date: Date) {
        let coordinate = resolvedCoordinates[option.location]
        let currencyCode = validCurrencyCode(option.costCurrency)
        let activity = Activity(
            title: option.title,
            activityDescription: option.description,
            location: option.location,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            date: date,
            cost: option.cost > 0 ? option.cost : nil,
            costCurrency: option.cost > 0 ? currencyCode : nil,
            iconName: clampedIconName(option.iconName),
            trip: trip
        )
        modelContext.insert(activity)
        pushIfShared(activity)
        if option.cost > 0, currencyCode != trip.currency {
            applyExchangeRate(for: activity, from: currencyCode)
        }
    }

    /// Snapshots a conversion rate onto the activity so it still counts
    /// toward budget totals/balances (see `Activity.costAndRate`), which
    /// otherwise excludes any cost whose currency doesn't match the trip's
    /// and has no rate recorded.
    private func applyExchangeRate(for activity: Activity, from currencyCode: String) {
        let tripCurrency = trip.currency
        Task {
            guard let rate = await CurrencyConversionService.fetchRate(from: currencyCode, to: tripCurrency) else { return }
            activity.exchangeRateToTripCurrency = rate
            pushIfShared(activity)
        }
    }

    private func pushIfShared(_ activity: Activity) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let activityID = activity.id
        let dto = activity.dto
        Task {
            try? await FirestoreCollectionSync.push(tripID: tripID, collection: "activities", docID: activityID, data: dto)
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static func combine(dateString: String, timeString: String) -> Date? {
        guard let day = isoDateFormatter.date(from: dateString) else { return nil }
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }
}
