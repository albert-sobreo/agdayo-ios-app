import ActivityKit
import SwiftUI
import WidgetKit

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripLiveActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(hex: context.attributes.themeColorHex).opacity(0.12))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.tripName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(context.state.dayLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let date = context.state.nextActivityStartDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DetailRows(state: context.state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Circle()
                    .fill(Color(hex: context.attributes.themeColorHex))
                    .frame(width: 10, height: 10)
            } compactTrailing: {
                if let date = context.state.nextActivityStartDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .monospacedDigit()
                } else {
                    Image(systemName: "checkmark.circle")
                }
            } minimal: {
                Circle()
                    .fill(Color(hex: context.attributes.themeColorHex))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: TripLiveActivityAttributes
    let state: TripLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: attributes.themeColorHex))
                    .frame(width: 8, height: 8)
                Text(attributes.tripName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(state.dayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DetailRows(state: state)
        }
        .padding()
    }
}

private struct DetailRows: View {
    let state: TripLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = state.currentActivityName {
                row(label: "Now", title: name, location: state.currentActivityLocation)
            }
            if let name = state.nextActivityName {
                HStack(alignment: .top) {
                    row(label: "Next", title: name, location: state.nextActivityLocation)
                    Spacer()
                    if let date = state.nextActivityStartDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            if state.currentActivityName == nil, state.nextActivityName == nil {
                Text("No more activities planned for today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(label: String, title: String, location: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
            if let location, !location.isEmpty {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Local, string-keyed hex parser — this extension doesn't depend on the
/// main app's `Color(hex: UInt32)` init (`TripTheme+Color.swift`), since
/// that file isn't part of this target. `TripLiveActivityAttributes.
/// themeColorHex` is a plain hex string for exactly this reason.
private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
