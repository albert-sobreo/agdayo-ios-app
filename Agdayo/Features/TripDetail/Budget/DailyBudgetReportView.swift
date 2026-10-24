import SwiftUI
import SwiftData
import Charts

/// Spending day by day: a scrollable bar chart on top (one bar per trip day,
/// split by budget category), and the selected day's breakdown below it.
/// Days that haven't happened yet show what's planned, drawn fainter.
struct DailyBudgetReportView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    /// Live queries scoped to this trip rather than relationship traversals —
    /// see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var budgetCategories: [BudgetCategory]
    @Query private var activities: [Activity]
    @Query private var accommodations: [Accommodation]
    @Query private var transportSegments: [TransportSegment]
    @Query private var expenses: [Expense]

    @State private var selectedDay: Date?
    @State private var rawSelection: Date?
    @State private var isSuggesting = false

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _budgetCategories = Query(filter: #Predicate<BudgetCategory> { $0.trip?.id == tripID })
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _expenses = Query(filter: #Predicate<Expense> { $0.trip?.id == tripID })
    }

    private var accent: Color { trip.theme.accentColor }

    private var report: BudgetReport {
        DailyBudgetService.report(
            trip: trip,
            activities: activities,
            accommodations: accommodations,
            transportSegments: transportSegments,
            expenses: expenses
        )
    }

    /// The day shown below the chart: the one tapped, else today if it's a trip
    /// day, else the first day with spending.
    private func activeDay(in report: BudgetReport) -> Date? {
        if let selectedDay, report.days.contains(where: { $0.day == selectedDay }) { return selectedDay }
        let today = Calendar.current.startOfDay(for: .now)
        if report.days.contains(where: { $0.day == today }) { return today }
        return report.days.first { $0.total > 0 }?.day ?? report.days.first?.day
    }

    // MARK: Chart data

    private struct ChartBar: Identifiable {
        let day: Date
        let category: String
        let amount: Double
        let isPlanned: Bool
        var id: String { "\(day.timeIntervalSince1970)-\(category)" }
    }

    private func bars(in report: BudgetReport) -> [ChartBar] {
        report.days.flatMap { day in
            DailyBudgetService.slices(for: day.items, categories: budgetCategories).map {
                ChartBar(day: day.day, category: $0.name, amount: $0.amount, isPlanned: day.isPlanned)
            }
        }
    }

    /// Category names in legend order — the ones with the most spending first.
    private func legendNames(for bars: [ChartBar]) -> [String] {
        let totals = Dictionary(grouping: bars, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }
        return totals.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Soft, distinct colors; the trip's own color goes to the biggest category.
    private func color(for name: String, in legend: [String]) -> Color {
        switch name {
        case CategorySlice.uncategorizedName: return Color(.systemGray3)
        case CategorySlice.memberBudgetsName: return Color(.systemGray4)
        default:
            let palette: [Color] = [
                accent,
                Color(red: 0.96, green: 0.62, blue: 0.47),
                Color(red: 0.42, green: 0.72, blue: 0.66),
                Color(red: 0.98, green: 0.78, blue: 0.42),
                Color(red: 0.63, green: 0.56, blue: 0.86),
                Color(red: 0.46, green: 0.66, blue: 0.91),
                Color(red: 0.89, green: 0.54, blue: 0.71),
                Color(red: 0.60, green: 0.73, blue: 0.43)
            ]
            let real = legend.filter { $0 != CategorySlice.uncategorizedName && $0 != CategorySlice.memberBudgetsName }
            let index = real.firstIndex(of: name) ?? 0
            return palette[index % palette.count]
        }
    }

    // MARK: Suggestions

    /// Costed items in no budget category and on no one's personal budget.
    private var suggestionInputs: [CategorySuggestionInput] {
        var inputs: [CategorySuggestionInput] = []
        for activity in activities where (activity.cost ?? 0) > 0 && activity.budgetCategoryID == nil && activity.budgetMemberUID == nil {
            inputs.append(CategorySuggestionInput(id: activity.id, kind: .activity, title: activity.title, iconName: activity.iconName))
        }
        for segment in transportSegments where segment.cost > 0 && segment.budgetCategoryID == nil && segment.budgetMemberUID == nil {
            let route = segment.arrivalLocation.isEmpty ? "" : " to \(segment.arrivalLocation)"
            inputs.append(CategorySuggestionInput(id: segment.id, kind: .transport, title: segment.mode.displayName + route, iconName: segment.mode.iconName))
        }
        for stay in accommodations where stay.totalCost > 0 && stay.budgetCategoryID == nil && stay.budgetMemberUID == nil {
            inputs.append(CategorySuggestionInput(id: stay.id, kind: .stay, title: stay.name, iconName: "bed.double"))
        }
        return inputs
    }

    private var suggestions: [CategorySuggestion] {
        BudgetCategorySuggester.suggest(
            for: suggestionInputs,
            categories: budgetCategories.map { (id: $0.id, name: $0.name) }
        )
    }

    /// Saves accepted suggestions onto their items and syncs them.
    private func apply(_ suggestions: [CategorySuggestion]) {
        for suggestion in suggestions {
            switch suggestion.kind {
            case .activity:
                guard let activity = activities.first(where: { $0.id == suggestion.id }) else { continue }
                activity.budgetCategoryID = suggestion.categoryID
                ActivitySaver.pushIfShared(activity, in: trip)
            case .transport:
                guard let segment = transportSegments.first(where: { $0.id == suggestion.id }) else { continue }
                segment.budgetCategoryID = suggestion.categoryID
                guard trip.ownerUID != nil else { continue }
                let (tripID, segmentID, dto) = (trip.id, segment.id, segment.dto)
                Task { try? await FirestoreCollectionSync.push(tripID: tripID, collection: "transportSegments", docID: segmentID, data: dto) }
            case .stay:
                guard let stay = accommodations.first(where: { $0.id == suggestion.id }) else { continue }
                stay.budgetCategoryID = suggestion.categoryID
                guard trip.ownerUID != nil else { continue }
                let (tripID, stayID, dto) = (trip.id, stay.id, stay.dto)
                Task { try? await FirestoreCollectionSync.push(tripID: tripID, collection: "accommodations", docID: stayID, data: dto) }
            }
        }
    }

    // MARK: Body

    var body: some View {
        let report = report
        let bars = bars(in: report)
        let legend = legendNames(for: bars)
        let active = activeDay(in: report)
        let suggestions = suggestions

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !suggestions.isEmpty {
                    suggestionBanner(count: suggestions.count)
                }

                chartCard(report: report, bars: bars, legend: legend, active: active)

                if let active, let day = report.days.first(where: { $0.day == active }) {
                    dayDetail(day, report: report, legend: legend)
                }

                if !report.undated.isEmpty {
                    undatedCard(report.undated)
                }

                if report.skippedWithoutRate > 0 {
                    Text("\(report.skippedWithoutRate) item\(report.skippedWithoutRate == 1 ? "" : "s") in another currency without an exchange rate \(report.skippedWithoutRate == 1 ? "isn't" : "aren't") included, same as on the Budget page.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationTitle("Daily Report")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: rawSelection) { _, newValue in
            guard let newValue else { return }
            let day = Calendar.current.startOfDay(for: newValue)
            if report.days.contains(where: { $0.day == day }) {
                withAnimation(.easeOut(duration: 0.2)) { selectedDay = day }
            }
        }
        .sheet(isPresented: $isSuggesting) {
            CategorySuggestionSheet(suggestions: suggestions, accentColor: accent, onApply: apply)
        }
    }

    // MARK: Pieces

    private func suggestionBanner(count: Int) -> some View {
        MoneyCard {
            HStack(spacing: 12) {
                Image(systemName: "tag")
                    .font(.title3)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) item\(count == 1 ? "" : "s") can be sorted into a category")
                        .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                    Text("Guessed from the type and name. You choose what to apply.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Review") { isSuggesting = true }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
        }
    }

    private func chartCard(report: BudgetReport, bars: [ChartBar], legend: [String], active: Date?) -> some View {
        let calendar = Calendar.current
        let visibleDays = max(3, min(report.days.count, 7))
        // Opens with the selected day in view rather than always at the trip's first day.
        let firstDay = report.days.first?.day ?? .now
        let scrollStart = active.flatMap { calendar.date(byAdding: .day, value: -(visibleDays / 2), to: $0) } ?? firstDay
        let tallest = max(report.days.map(\.total).max() ?? 0, report.dailyAllowance ?? 0)
        let totals = report.days.filter { $0.total > 0 }

        return MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Spending per day")
                        .font(AppFont.barlowCondensed(22, weight: .semibold))
                    Spacer()
                    if let allowance = report.dailyAllowance {
                        HStack(spacing: 6) {
                            DashedLine()
                                .stroke(BrandPalette.maroon.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .frame(width: 18, height: 1.5)
                            Text("\(allowance.formattedCurrency(code: trip.currency)) a day")
                                .font(AppFont.outfit(11, weight: .medium, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if bars.isEmpty {
                    Text("Nothing with a cost yet. Add costs to activities, stays, transport or expenses to see them here.")
                        .font(AppFont.outfit(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    Chart {
                        // A soft panel behind the selected day.
                        if let active {
                            RectangleMark(x: .value("Day", active, unit: .day), width: .ratio(0.92))
                                .foregroundStyle(accent.opacity(0.10))
                                .cornerRadius(12)
                        }

                        ForEach(bars) { bar in
                            BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Spent", bar.amount), width: .ratio(0.58))
                                .foregroundStyle(by: .value("Category", bar.category))
                                .cornerRadius(6, style: .continuous)
                                .opacity(bar.isPlanned ? 0.5 : 1)
                        }

                        // Each day's total, just above its bar.
                        ForEach(totals) { day in
                            PointMark(x: .value("Day", day.day, unit: .day), y: .value("Total", day.total))
                                .opacity(0)
                                .annotation(position: .top, spacing: 2) {
                                    Text(day.total, format: .number.notation(.compactName))
                                        .font(AppFont.outfit(10, weight: .semibold, relativeTo: .caption2))
                                        .foregroundStyle(
                                            report.dailyAllowance.map { day.total > $0 } == true
                                                ? BrandPalette.maroon
                                                : Color.secondary
                                        )
                                }
                        }

                        if let allowance = report.dailyAllowance {
                            RuleMark(y: .value("Daily allowance", allowance))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(BrandPalette.maroon.opacity(0.7))
                        }
                    }
                    .chartForegroundStyleScale(domain: legend, range: legend.map { color(for: $0, in: legend) })
                    .chartLegend(.hidden)
                    // Headroom so the total above the tallest bar isn't cut off.
                    .chartYScale(domain: 0...max(tallest * 1.22, 1))
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: Double(visibleDays) * 86_400)
                    .chartScrollPosition(initialX: scrollStart)
                    .chartXSelection(value: $rawSelection)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { value in
                            AxisValueLabel(centered: true) {
                                if let date = value.as(Date.self) {
                                    let isSelected = active.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                                    VStack(spacing: 1) {
                                        Text(date, format: .dateTime.weekday(.abbreviated))
                                            .font(AppFont.outfit(10, weight: .medium, relativeTo: .caption2))
                                            .textCase(.uppercase)
                                        Text(date, format: .dateTime.day())
                                            .font(AppFont.barlowCondensed(17, weight: isSelected ? .bold : .medium))
                                    }
                                    .foregroundStyle(isSelected ? accent : Color.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.secondary.opacity(0.35))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .number.notation(.compactName))
                                        .font(AppFont.outfit(10, relativeTo: .caption2))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 230)

                    legendView(legend)

                    if report.days.contains(where: \.isPlanned) {
                        Text("Faded bars are planned days that haven't happened yet.")
                            .font(AppFont.outfit(11, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// A compact row of colored dots and category names under the chart.
    private func legendView(_ legend: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(legend, id: \.self) { name in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: name, in: legend))
                            .frame(width: 9, height: 9)
                        Text(name)
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func dayDetail(_ day: DayBudget, report: BudgetReport, legend: [String]) -> some View {
        let slices = DailyBudgetService.slices(for: day.items, categories: budgetCategories)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(AppFont.barlowCondensed(26, weight: .semibold))
                    if let allowance = report.dailyAllowance {
                        let difference = day.total - allowance
                        Text(difference > 0
                             ? "\(difference.formattedCurrency(code: trip.currency)) over the daily allowance"
                             : "\((-difference).formattedCurrency(code: trip.currency)) under the daily allowance")
                            .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
                            .foregroundStyle(difference > 0 ? BrandPalette.maroon : Color.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    MoneyAmount(text: day.total.formattedCurrency(code: trip.currency), size: 28)
                    if day.isPlanned {
                        PillTag(text: "Planned", background: accent.opacity(0.15), foreground: accent)
                    }
                }
            }

            if slices.isEmpty {
                Text("Nothing with a cost on this day.")
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(slices) { slice in
                    sliceCard(slice, dayTotal: day.total, legend: legend)
                }
            }
        }
    }

    private func sliceCard(_ slice: CategorySlice, dayTotal: Double, legend: [String]) -> some View {
        let share = dayTotal > 0 ? slice.amount / dayTotal : 0
        return MoneyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: slice.name, in: legend))
                        .frame(width: 10, height: 10)
                    Text(slice.name)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                    Spacer()
                    MoneyAmount(text: slice.amount.formattedCurrency(code: trip.currency), size: 20)
                }
                ForEach(slice.items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.iconName)
                            .foregroundStyle(accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(AppFont.outfit(14, relativeTo: .subheadline))
                            Text([item.kind.label, item.subtitle].compactMap { $0 }.joined(separator: " · "))
                                .font(AppFont.outfit(11, relativeTo: .caption2))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount.formattedCurrency(code: trip.currency))
                            .font(AppFont.outfit(13, weight: .medium, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func undatedCard(_ items: [BudgetLineItem]) -> some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("No date", systemImage: "calendar.badge.questionmark")
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                    Spacer()
                    MoneyAmount(text: items.reduce(0) { $0 + $1.amount }.formattedCurrency(code: trip.currency), size: 20)
                }
                Text("Expenses without a date count toward the budget but can't be placed on a day.")
                    .font(AppFont.outfit(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    HStack {
                        Text(item.title)
                            .font(AppFont.outfit(14, relativeTo: .subheadline))
                        Spacer()
                        Text(item.amount.formattedCurrency(code: trip.currency))
                            .font(AppFont.outfit(13, weight: .medium, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// A horizontal line for dashed strokes in the chart's key.
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Shows the guesses and lets the person choose which to save.
private struct CategorySuggestionSheet: View {
    let suggestions: [CategorySuggestion]
    let accentColor: Color
    let onApply: ([CategorySuggestion]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var accepted: Set<UUID>

    init(suggestions: [CategorySuggestion], accentColor: Color, onApply: @escaping ([CategorySuggestion]) -> Void) {
        self.suggestions = suggestions
        self.accentColor = accentColor
        self.onApply = onApply
        _accepted = State(initialValue: Set(suggestions.map(\.id)))
    }

    private var chosen: [CategorySuggestion] {
        suggestions.filter { accepted.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions) { suggestion in
                        Button {
                            if accepted.contains(suggestion.id) { accepted.remove(suggestion.id) } else { accepted.insert(suggestion.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: accepted.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(accepted.contains(suggestion.id) ? accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(AppFont.outfit(15, weight: .medium, relativeTo: .body))
                                        .foregroundStyle(.primary)
                                    Text("→ \(suggestion.categoryName)")
                                        .font(AppFont.outfit(12, relativeTo: .caption))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Guessed from each item's type and name. Uncheck any that are wrong.")
                }
            }
            .navigationTitle("Suggested Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Apply \(chosen.count)") {
                    onApply(chosen)
                    dismiss()
                }
                .buttonStyle(.appPrimary)
                .disabled(chosen.isEmpty)
                .padding()
                .background(.bar)
            }
        }
    }
}
