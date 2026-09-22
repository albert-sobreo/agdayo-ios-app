import SwiftUI

struct StatusBadge: View {
    let status: TripStatus

    private var colors: (background: Color, foreground: Color) {
        switch status {
        case .upcoming: return (Color.appInfo.opacity(0.2), .appInfo)
        case .active: return (Color.appSuccess.opacity(0.2), .appSuccess)
        case .completed: return (Color.appSecondary.opacity(0.4), .secondary)
        }
    }

    var body: some View {
        PillTag(text: status.rawValue, background: colors.background, foreground: colors.foreground)
    }
}
