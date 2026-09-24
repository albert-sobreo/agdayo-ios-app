import SwiftUI

/// Thin `UIActivityViewController` wrapper shared by every feature that
/// exports a generated image/file (the trips map, the visited-places map,
/// Home's past-trip recap cards, the travel-stats overlay) — one place for
/// the system share sheet instead of a copy per feature.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
