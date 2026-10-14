import SwiftUI

/// DESIGN DRAFT — a visual mockup for the planned "Browse Trip Ideas"
/// feature (see memory: project-v2-trip-templates). Backed by hardcoded
/// sample data below, not the real `tripTemplates` Firestore collection —
/// not wired into any navigation yet. Safe to delete/replace wholesale once
/// the real feature is built.
///
/// `imageURL` points at a real Unsplash photo for now, just so this draft
/// looks right — a real build would swap these for licensed/self-hosted
/// destination images rather than hotlinking Unsplash's CDN indefinitely.
struct TemplateSample: Identifiable {
    let id = UUID()
    let name: String
    let location: String
    let imageURL: URL?
    let theme: TripTheme
    let suggestedDays: Int
    let tags: [String]
    let bestTimeToVisit: String
    let estimatedBudget: Double
    let currency: String
    let averageRating: Double
    let ratingCount: Int
    let copyCount: Int
}

extension TemplateSample {
    static let samples: [TemplateSample] = [
        TemplateSample(
            name: "Baguio Weekend Escape", location: "Baguio, Benguet",
            imageURL: URL(string: "https://images.unsplash.com/photo-1697111314630-8db2d3f5187d?fm=jpg&q=60&w=1200&auto=format&fit=crop"),
            theme: .emerald,
            suggestedDays: 3, tags: ["Mountain", "Budget"], bestTimeToVisit: "Nov–Feb ideal",
            estimatedBudget: 6500, currency: "PHP", averageRating: 4.7, ratingCount: 128, copyCount: 842
        ),
        TemplateSample(
            name: "Palawan Island Hopping", location: "El Nido, Palawan",
            imageURL: URL(string: "https://images.unsplash.com/photo-1531761535209-180857e963b9?fm=jpg&q=60&w=1200&auto=format&fit=crop"),
            theme: .teal,
            suggestedDays: 5, tags: ["Beach", "Island Hopping"], bestTimeToVisit: "Dec–May ideal",
            estimatedBudget: 18500, currency: "PHP", averageRating: 4.9, ratingCount: 356, copyCount: 1920
        ),
        TemplateSample(
            name: "Siargao Surf Trip", location: "General Luna, Siargao",
            imageURL: URL(string: "https://images.unsplash.com/photo-1559099078-8ab4ed4eefed?fm=jpg&q=60&w=1200&auto=format&fit=crop"),
            theme: .blue,
            suggestedDays: 4, tags: ["Beach", "Surf"], bestTimeToVisit: "Aug–Nov for swell",
            estimatedBudget: 14000, currency: "PHP", averageRating: 4.6, ratingCount: 94, copyCount: 503
        ),
        TemplateSample(
            name: "Vigan Heritage Walk", location: "Vigan, Ilocos Sur",
            imageURL: URL(string: "https://images.unsplash.com/photo-1587659584959-fb5849fb6d26?fm=jpg&q=60&w=1200&auto=format&fit=crop"),
            theme: .amber,
            suggestedDays: 2, tags: ["Heritage", "Food Trip"], bestTimeToVisit: "Nov–Apr ideal",
            estimatedBudget: 4200, currency: "PHP", averageRating: 4.5, ratingCount: 61, copyCount: 210
        )
    ]

    static let allTags = ["All"] + Array(Set(samples.flatMap(\.tags))).sorted()
}

private enum TemplateSort: String, CaseIterable {
    case popular = "Popular"
    case topRated = "Top Rated"
}

struct BrowseTripTemplatesView: View {
    @State private var selectedTag = "All"
    @State private var sort: TemplateSort = .popular
    @State private var selectedTemplate: TemplateSample?

    private var filteredTemplates: [TemplateSample] {
        let base = selectedTag == "All"
            ? TemplateSample.samples
            : TemplateSample.samples.filter { $0.tags.contains(selectedTag) }
        switch sort {
        case .popular:
            return base.sorted { $0.copyCount > $1.copyCount }
        case .topRated:
            return base.sorted { $0.averageRating > $1.averageRating }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    tagFilterRow
                    VStack(spacing: 12) {
                        ForEach(filteredTemplates) { template in
                            Button {
                                selectedTemplate = template
                            } label: {
                                TemplateCard(template: template)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(BrandPalette.canvas.ignoresSafeArea())
            .navigationTitle("Browse Trip Ideas")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(TemplateSort.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                    }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                NavigationStack {
                    TripTemplateDetailView(template: template)
                }
            }
        }
    }

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TemplateSample.allTags, id: \.self) { tag in
                    let isSelected = tag == selectedTag
                    Button {
                        selectedTag = tag
                    } label: {
                        Text(tag.uppercased())
                            .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                            .tracking(1)
                            .foregroundStyle(isSelected ? .white : BrandPalette.maroon)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? BrandPalette.maroon : BrandPalette.cardSurface,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct TemplateCard: View {
    let template: TemplateSample

    private var headline: Color {
        template.theme.accentColor.mix(with: .black, by: 0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(template.location.uppercased())
                    .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(BrandPalette.rose)
                    Text(String(format: "%.1f", template.averageRating))
                        .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                    Text("(\(template.ratingCount))")
                        .font(AppFont.outfit(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                }
            }

            Text(template.name.uppercased())
                .font(AppFont.barlowCondensed(24, weight: .semibold, relativeTo: .headline))
                .tracking(1)
                .foregroundStyle(headline)
                .lineLimit(2)

            HStack(spacing: 6) {
                ForEach(template.tags, id: \.self) { tag in
                    PillTag(text: tag, background: template.theme.lightTintColor, foreground: headline)
                }
            }

            HStack(spacing: 0) {
                statColumn(label: "Days", value: "\(template.suggestedDays)D")
                verticalDivider
                statColumn(label: "Est. Budget", value: template.estimatedBudget.formattedCurrency(code: template.currency))
                verticalDivider
                statColumn(label: "Best Time", value: template.bestTimeToVisit)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("\(template.copyCount) travelers used this")
            }
            .font(AppFont.outfit(11, relativeTo: .caption2))
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                template.theme.headerBackground
                FadedDestinationImage(url: template.imageURL)
            }
        }
        // Deliberately sharp corners (cornerRadius: 0) — flat rectangle
        // cards, unlike the rounded `TripCardView`/showcase cards for the
        // user's own trips, is the visual cue that this is curated content,
        // not something they made. Keeps the glass/sticker material so it
        // still reads as tappable, just squared off.
        .modifier(GlassOrStickerCard(cornerRadius: 0))
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(template.theme.accentColor.opacity(0.3))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 10)
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .trackedLabel(8, color: headline.opacity(0.7))
            Text(value.uppercased())
                .font(AppFont.barlowCondensed(14, weight: .semibold))
                .foregroundStyle(headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A destination photo, faded and masked toward the leading edge so it
/// reads as a subtle backdrop behind a card's text rather than competing
/// with it — same idea as `MapBackgroundDecoration` on the real showcase
/// trip card, just a real place photo instead of a map snapshot.
struct FadedDestinationImage: View {
    let url: URL?
    var width: CGFloat = 220

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: width)
        .clipped()
        .opacity(0.4)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .black, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

#Preview("Browse Trip Ideas") {
    BrowseTripTemplatesView()
}
