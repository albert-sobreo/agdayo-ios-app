import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.outfit(17, weight: .semibold, relativeTo: .headline))
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.card))
    }
}
