import SwiftUI

private struct OnboardingPage {
    let imageName: String
    let headline: String
    let subtext: String
    let photoCredit: String
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        imageName: "elnido",
        headline: "Plan Every Trip in One Place",
        subtext: "Itinerary, stays, transport, and budget, all organized for your next adventure.",
        photoCredit: "El Nido, Palawan. Photo by Eibner Saliba"
    ),
    OnboardingPage(
        imageName: "batanes",
        headline: "Travel Together",
        subtext: "Invite your companions with a join code and keep everyone in sync.",
        photoCredit: "Batanes. Photo by JR Padlan"
    ),
    OnboardingPage(
        imageName: "baguio",
        headline: "Split Costs, Settle Up Fairly",
        subtext: "Track who paid what and settle balances without the awkward math.",
        photoCredit: "Baguio, Benguet. Photo by Gian Paul Guinto"
    ),
]

/// Shown once, on first launch, before `RootTabView` — gated by
/// `hasCompletedOnboarding` in `AgdayoApp`. Independent of sign-in state
/// since the app itself doesn't require an account to start planning.
struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var pageIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $pageIndex) {
                ForEach(Array(onboardingPages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    ForEach(onboardingPages.indices, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == pageIndex ? 1 : 0.4))
                            .frame(width: index == pageIndex ? 20 : 8, height: 8)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: pageIndex)

                Button {
                    advance()
                } label: {
                    Text(isLastPage ? "Get Started" : "Next")
                }
                .buttonStyle(.appPrimary)
                .padding(.horizontal, 24)

                if !isLastPage {
                    Button("Skip") { onFinish() }
                        .font(AppFont.outfit(15, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.black)
    }

    private var isLastPage: Bool { pageIndex == onboardingPages.count - 1 }

    private func advance() {
        if isLastPage {
            onFinish()
        } else {
            withAnimation { pageIndex += 1 }
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        // Only the photo + gradient bleed to the true screen edges — the
        // credit and headline stay inside the safe area, laid out normally,
        // so they land below the status bar / Dynamic Island and above the
        // home indicator on every device instead of a guessed pixel offset.
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                Image(page.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Text(page.photoCredit)
                .font(AppFont.outfit(11, relativeTo: .caption2))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(.top) // safe-area default — clears the notch/Dynamic Island
                .padding(.top, 8) // small visual gap below that
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 10) {
                Text(page.headline)
                    .font(AppFont.outfit(28, weight: .bold, relativeTo: .title))
                    .foregroundStyle(.white)
                Text(page.subtext)
                    .font(AppFont.outfit(16, relativeTo: .body))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 28)
            .padding(.bottom) // safe-area default — clears the home indicator
            .padding(.bottom, 150) // clearance for the dots/button/skip overlay
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
