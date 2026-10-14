import SwiftUI

/// DESIGN DRAFT — paired with `BrowseTripTemplatesView`. Read-only preview
/// of a template's itinerary before "copying" it into a real trip. The
/// day-by-day content below is hardcoded sample data, standing in for the
/// planned `tripTemplates/{id}.itinerary` field — see memory:
/// project-v2-trip-templates.
private struct TemplateActivityPreview: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let location: String
    let iconName: String
    let cost: Double
}

private struct TemplateDayPreview: Identifiable {
    let id = UUID()
    let dayNumber: Int
    let activities: [TemplateActivityPreview]
}

struct TripTemplateDetailView: View {
    let template: TemplateSample

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingCopySheet = false

    private var headline: Color {
        template.theme.accentColor.mix(with: .black, by: 0.35)
    }

    /// Stand-in itinerary — a real build would read this straight off the
    /// template document instead of generating it.
    private var sampleDays: [TemplateDayPreview] {
        (1...template.suggestedDays).map { day in
            TemplateDayPreview(dayNumber: day, activities: [
                TemplateActivityPreview(time: "8:00 am", title: "Breakfast at a local favorite", location: template.location, iconName: "fork.knife", cost: 250),
                TemplateActivityPreview(time: "10:00 am", title: day == 1 ? "Arrival & check-in" : "Explore a nearby landmark", location: template.location, iconName: "camera.fill", cost: 0),
                TemplateActivityPreview(time: "1:00 pm", title: "Lunch stop", location: template.location, iconName: "takeoutbag.and.cup.and.straw.fill", cost: 300),
                TemplateActivityPreview(time: "3:00 pm", title: "Afternoon activity", location: template.location, iconName: "figure.hiking", cost: 500)
            ])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                heroCard
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sampleDays) { day in
                        daySection(day)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 100)
        }
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isPresentingCopySheet = true
            } label: {
                Text("Use This Template")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $isPresentingCopySheet) {
            // DRAFT: the real copy sheet would let you pick a start date
            // and uncheck individual days before creating a real Trip —
            // see memory: project-v2-trip-templates.
            Text("Copy sheet goes here — pick a start date, uncheck any days you don't want, then create the trip.")
                .font(AppFont.outfit(14, relativeTo: .body))
                .multilineTextAlignment(.center)
                .padding()
                .presentationDetents([.medium])
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                PillTag(text: "\(template.suggestedDays) DAYS", background: template.theme.lightTintColor, foreground: headline)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(BrandPalette.rose)
                    Text(String(format: "%.1f", template.averageRating))
                    Text("(\(template.ratingCount) ratings)")
                        .foregroundStyle(.secondary)
                }
                .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
            }

            Text(template.name.uppercased())
                .font(AppFont.barlowCondensed(32, weight: .semibold, relativeTo: .largeTitle))
                .tracking(2)
                .foregroundStyle(headline)

            Text(template.location.uppercased())
                .font(AppFont.barlowCondensed(18, weight: .regular))
                .tracking(2)
                .foregroundStyle(headline.opacity(0.8))

            HStack(spacing: AppSpacing.lg) {
                heroStat(label: "Est. Budget", value: template.estimatedBudget.formattedCurrency(code: template.currency))
                heroStat(label: "Best Time", value: template.bestTimeToVisit)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Used by \(template.copyCount) travelers")
            }
            .font(AppFont.outfit(12, relativeTo: .caption))
            .foregroundStyle(headline.opacity(0.7))
        }
        .padding()
        .background(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                template.theme.headerBackground
                FadedDestinationImage(url: template.imageURL, width: 280)
            }
        }
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .trackedLabel(9, color: headline.opacity(0.65))
            Text(value)
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(headline)
        }
    }

    private func daySection(_ day: TemplateDayPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Day \(day.dayNumber)".uppercased())
                .font(AppFont.outfit(13, weight: .bold, relativeTo: .footnote))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(day.activities) { activity in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: activity.iconName)
                            .font(.subheadline)
                            .foregroundStyle(template.theme.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                            Text("\(activity.time) · \(activity.location)")
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if activity.cost > 0 {
                            Text(activity.cost.formattedCurrency(code: template.currency))
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
                }
            }
        }
    }
}

#Preview("Template Detail") {
    NavigationStack {
        TripTemplateDetailView(template: TemplateSample.samples[1])
    }
}
