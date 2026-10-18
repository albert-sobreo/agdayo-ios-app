import SwiftUI

/// Building blocks shared by the Budget and Balances screens, so both use the
/// app's design language instead of plain list rows: cards on the off-white
/// canvas, Barlow Condensed numbers and headings, tracked small-caps labels.

/// A rounded card in the same style as the trip screen's section tiles.
struct MoneyCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassOrStickerCard(cornerRadius: AppRadius.smallerCard))
    }
}

/// "CATEGORIES" style header: Barlow Condensed, uppercase, tracked, with an
/// icon in the trip's color.
struct MoneySectionHeader: View {
    let title: String
    let iconName: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
            Text(title)
                .font(AppFont.barlowCondensed(22, weight: .semibold))
                .tracking(2)
                .textCase(.uppercase)
        }
        .foregroundStyle(.primary)
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A big amount in Barlow Condensed, shrinking rather than wrapping.
struct MoneyAmount: View {
    let text: String
    var size: CGFloat = 24
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(AppFont.barlowCondensed(size, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// A round icon badge in the trip's color.
struct MoneyIconBadge: View {
    let systemName: String
    let accentColor: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(accentColor)
            .frame(width: 40, height: 40)
            .background(accentColor.opacity(0.14), in: Circle())
    }
}

extension View {
    /// Edit-sheet forms: the app's canvas behind the grouped rows, and the
    /// trip's color for pickers, toggles and links.
    func brandForm(accent: Color) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(BrandPalette.canvas.ignoresSafeArea())
            .tint(accent)
    }

    /// Row chrome for the money lists: each row is a card of its own sitting on
    /// the canvas, with no list background or separator.
    func moneyRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}
