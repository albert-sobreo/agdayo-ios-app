import SwiftUI

/// An Airbnb-style vertically-scrolling multi-month calendar for picking a
/// trip's start/end date by tapping two days, with the range between them
/// highlighted. Pure `Calendar`/`DateComponents` math — no new dependency.
struct TripDateRangeCalendar: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?

    private let calendar = Calendar.current
    private let monthsToShow = 36

    private var months: [Date] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        return (0..<monthsToShow).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(months, id: \.self) { month in
                    MonthGrid(month: month, startDate: startDate, endDate: endDate, onTap: handleTap)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func handleTap(_ day: Date) {
        let today = calendar.startOfDay(for: .now)
        guard day >= today else { return }

        if startDate == nil {
            startDate = day
        } else if endDate == nil {
            if let startDate, day > startDate {
                endDate = day
            } else {
                startDate = day
            }
        } else {
            startDate = day
            endDate = nil
        }
    }
}

private struct MonthGrid: View {
    let month: Date
    let startDate: Date?
    let endDate: Date?
    let onTap: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var firstOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private var leadingEmptyDays: Int {
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var days: [Date] {
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: firstOfMonth) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(.headline, design: .rounded).weight(.semibold))

            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<leadingEmptyDays, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, startDate: startDate, endDate: endDate, onTap: onTap)
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let startDate: Date?
    let endDate: Date?
    let onTap: (Date) -> Void

    private let calendar = Calendar.current

    private var isPast: Bool {
        day < calendar.startOfDay(for: .now)
    }

    private var isStart: Bool {
        guard let startDate else { return false }
        return calendar.isDate(day, inSameDayAs: startDate)
    }

    private var isEnd: Bool {
        guard let endDate else { return false }
        return calendar.isDate(day, inSameDayAs: endDate)
    }

    /// Includes the endpoints themselves so the highlight bar runs behind
    /// their circles too, not just the days strictly between them.
    private var isWithinSelection: Bool {
        guard let startDate, let endDate else { return false }
        return day >= calendar.startOfDay(for: startDate) && day <= calendar.startOfDay(for: endDate)
    }

    /// This day's column (0 = first weekday of the row) — needed to round
    /// off each calendar row's own edges, since the highlight bar breaks at
    /// the end of a row and resumes at the start of the next.
    private var weekdayIndex: Int {
        let weekday = calendar.component(.weekday, from: day)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var roundsLeadingEdge: Bool { isStart || weekdayIndex == 0 }
    private var roundsTrailingEdge: Bool { isEnd || weekdayIndex == 6 }

    var body: some View {
        Button {
            onTap(day)
        } label: {
            GeometryReader { geo in
                // `Circle()` auto-insets to stay round (diameter = height,
                // centered) whenever the cell is wider than tall — which it
                // always is here. Insetting the highlight's rounded edges by
                // that same margin keeps its cap flush with the circle's
                // actual edge instead of poking out past it.
                let diameter = geo.size.height
                let margin = max(0, (geo.size.width - diameter) / 2)

                ZStack {
                    if isWithinSelection {
                        UnevenRoundedRectangle(
                            topLeadingRadius: roundsLeadingEdge ? diameter / 2 : 0,
                            bottomLeadingRadius: roundsLeadingEdge ? diameter / 2 : 0,
                            bottomTrailingRadius: roundsTrailingEdge ? diameter / 2 : 0,
                            topTrailingRadius: roundsTrailingEdge ? diameter / 2 : 0
                        )
                        .fill(Color.appPrimary.opacity(0.15))
                        .padding(.leading, roundsLeadingEdge ? margin : 0)
                        .padding(.trailing, roundsTrailingEdge ? margin : 0)
                        .transaction { $0.animation = nil }
                    }
                    if isStart || isEnd {
                        Circle().fill(Color.appPrimary)
                    }
                    Text("\(calendar.component(.day, from: day))")
                        .font(.callout.weight(isStart || isEnd ? .bold : .regular))
                        .foregroundStyle(isStart || isEnd ? .white : (isPast ? .secondary : .primary))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isPast)
    }
}
