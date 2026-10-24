import SwiftUI
import Photos

/// Thin `UIActivityViewController` wrapper shared by every feature that
/// exports a generated image/file (the trips map, the visited-places map,
/// Home's past-trip recap cards, the travel-stats overlay) — one place for
/// the system share sheet instead of a copy per feature.
///
/// Image files get an extra "Save to Photos" action: the system sheet only
/// offers one for a `UIImage`, not for a file URL, and exporting the file
/// keeps the PNG's transparency (the stats sticker) intact.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: [SaveToPhotosActivity()])
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Adds image files to the photo library, using add-only access, so the app
/// never needs to read the person's photos.
final class SaveToPhotosActivity: UIActivity {
    private var imageURLs: [URL] = []

    private static func isImageFile(_ item: Any) -> Bool {
        guard let url = item as? URL, url.isFileURL else { return false }
        return ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("app.agdayo.saveToPhotos") }
    override var activityTitle: String? { "Save to Photos" }
    override var activityImage: UIImage? { UIImage(systemName: "square.and.arrow.down") }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        activityItems.contains(where: Self.isImageFile)
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        imageURLs = activityItems.filter(Self.isImageFile).compactMap { $0 as? URL }
    }

    override func perform() {
        let urls = imageURLs
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                activityDidFinish(false)
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in urls {
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                    }
                }
                activityDidFinish(true)
            } catch {
                activityDidFinish(false)
            }
        }
    }
}
