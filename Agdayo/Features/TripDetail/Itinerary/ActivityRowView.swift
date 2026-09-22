import SwiftUI

/// Timeline row: a fixed-width rail (time label, dot, connecting line — always
/// peach per the web app's TimelineDot, not theme-aware) beside the activity card.
struct ActivityRowView: View {
    let title: String
    let location: String
    let cost: Double?
    let costCurrency: String?
    let costNote: String?
    let iconName: String
    let time: Date
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelineRail(time: time, isLast: isLast)
            ActivityCardContent(
                title: title,
                location: location,
                cost: cost,
                costCurrency: costCurrency,
                costNote: costNote,
                iconName: iconName
            )
            .padding(.bottom, 12)
        }
    }
}

private struct TimelineRail: View {
    let time: Date
    let isLast: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(time, format: .dateTime.hour().minute())
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Circle()
                .fill(Color(hex: 0xF0A693))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color(hex: 0xFBB5A3), lineWidth: 2))
            if !isLast {
                Rectangle()
                    .fill(Color(hex: 0xFDD3C7))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 56)
    }
}

private struct ActivityCardContent: View {
    let title: String
    let location: String
    let cost: Double?
    let costCurrency: String?
    let costNote: String?
    let iconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(Color(hex: 0xF0A693))
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            if !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let cost {
                HStack(spacing: 4) {
                    Label(cost.formattedCurrency(code: costCurrency ?? "PHP"), systemImage: "wallet.pass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let costNote, !costNote.isEmpty {
                        Text(costNote)
                            .font(.caption)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .stickerCard(cornerRadius: AppRadius.denseCard)
    }
}
