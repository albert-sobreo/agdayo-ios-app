import Photos
import UIKit

/// Read-only PhotoKit wrapper for the trip-attachments feature. Deliberately
/// cannot create a Shared Album or send invites — that's an Apple platform
/// limitation with no workaround — and deliberately doesn't add photos
/// either: adding new photos happens in Photos.app itself (via the "Open in
/// Photos" button in `TripAttachmentsView`), since PhotoKit editing of an
/// existing Shared Album turned out to be unreliable in practice (see git
/// history for the abandoned attempts). This only ever reads.
enum SharedAlbumService {
    static func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Every iCloud Shared Album on this device, across both the
    /// user-created and "smart" fetch buckets PhotoKit exposes.
    static func fetchSharedAlbums() -> [PHAssetCollection] {
        var albums: [PHAssetCollection] = []
        let options = PHFetchOptions()
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: options)
        userAlbums.enumerateObjects { collection, _, _ in albums.append(collection) }
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .albumCloudShared, options: options)
        smartAlbums.enumerateObjects { collection, _, _ in albums.append(collection) }
        return albums
    }

    /// Matches by `localizedTitle`, not `localIdentifier` — the identifier
    /// doesn't reliably carry across devices for a shared album, but every
    /// invited member sees the same title in Photos.app.
    static func album(titled title: String) -> PHAssetCollection? {
        fetchSharedAlbums().first { $0.localizedTitle == title }
    }

    static func assets(in collection: PHAssetCollection) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: collection, options: options)
    }

    /// `.highQualityFormat` (not `.opportunistic`) so the completion handler
    /// fires exactly once — `.opportunistic` can call back twice (a fast low-
    /// quality preview, then the final image), which would trip a second
    /// `resume` on this continuation.
    static func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
