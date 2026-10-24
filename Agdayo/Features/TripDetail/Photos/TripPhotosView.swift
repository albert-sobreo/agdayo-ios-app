import SwiftUI
import Photos
import PhotosUI

/// The trip's photos live in an iCloud Shared Album, made and managed with
/// Apple's own screens. Agdayo only remembers the album's link so everyone on
/// the trip can find it — it never reads, stores or uploads the photos.
///
/// Creating an album and adding to it use system sheets that need iOS 27; on
/// earlier versions an existing album can still be opened and its link shared.
struct TripPhotosView: View {
    let trip: Trip

    @Environment(\.openURL) private var openURL

    @State private var isCreatingAlbum = false
    @State private var isCustomizingAlbum = false
    @State private var isPickingPhotos = false
    @State private var isPostingPhotos = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    /// Photos' own ID for the album, which only exists on the device that made it
    /// (other devices have a different ID for the same album).
    @State private var localAlbumID: String?

    init(trip: Trip) {
        self.trip = trip
        _localAlbumID = State(initialValue: UserDefaults.standard.string(forKey: Self.albumIDKey(for: trip)))
    }

    private static func albumIDKey(for trip: Trip) -> String {
        "tripAlbumIdentifier.\(trip.id.uuidString)"
    }

    private var accent: Color { trip.theme.accentColor }

    private var albumURL: URL? {
        trip.albumURL.flatMap(URL.init(string:))
    }

    private var supportsAlbumSheets: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    /// Shared albums need an iCloud account. Without one, Apple's sheets show
    /// their own warning, so warn here first instead. The check can also read
    /// "signed out" when iCloud Drive is off but Shared Albums still work, so
    /// the person can always choose to try anyway.
    private func requiringICloud(_ action: @escaping () -> Void) {
        if FileManager.default.ubiquityIdentityToken != nil {
            action()
        } else {
            PlainAlert.present(
                title: "iCloud Needed",
                message: "Shared albums need you to be signed in to iCloud, with Shared Albums turned on in Settings → Photos. If you're sure it's set up, you can try anyway.",
                actions: [
                    PlainAlert.Action("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    },
                    PlainAlert.Action("Try Anyway", handler: action),
                    PlainAlert.Action("Cancel", isCancel: true)
                ]
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let albumURL {
                    albumCard(albumURL)
                } else {
                    setupCard
                }
                if !supportsAlbumSheets {
                    Text("Creating an album and adding photos from Agdayo needs iOS 27. You can still open the album and share its link.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                howItWorksCard
            }
            .padding()
        }
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $isPickingPhotos,
            selection: $pickedItems,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickedItems) { _, items in
            if !items.isEmpty { isPostingPhotos = true }
        }
        .sharedAlbumSheets(
            isCreating: $isCreatingAlbum,
            isCustomizing: $isCustomizingAlbum,
            isPosting: $isPostingPhotos,
            items: pickedItems,
            tripName: trip.name,
            localAlbumID: localAlbumID,
            onCreated: { url, identifier in
                trip.albumURL = url.absoluteString
                if let identifier {
                    UserDefaults.standard.set(identifier, forKey: Self.albumIDKey(for: trip))
                    localAlbumID = identifier
                }
                TripMembershipService.pushAlbumURL(trip: trip)
            },
            onPostingFinished: { pickedItems = [] },
            onError: { errorMessage = $0 }
        )
        .alert("Couldn't Finish", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Cards

    private var setupCard: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                header(title: "No Album Yet", subtitle: "Make a shared album for the whole group.")
                Text("Everyone on the trip can add their photos and videos to one iCloud Shared Album, and see everyone else's.")
                    .font(AppFont.outfit(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                if supportsAlbumSheets {
                    Button("Create Shared Album") { requiringICloud { isCreatingAlbum = true } }
                        .buttonStyle(.appPrimary)
                }
            }
        }
    }

    private func albumCard(_ url: URL) -> some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                header(title: "Trip Album", subtitle: "An iCloud Shared Album for this trip.")

                if supportsAlbumSheets {
                    Button("Add Photos") { requiringICloud { isPickingPhotos = true } }
                        .buttonStyle(.appPrimary)
                }

                HStack(spacing: 12) {
                    Button("Open in Photos") { openURL(url) }
                        .buttonStyle(.appSecondary)
                    ShareLink(item: url, message: Text("Join our \(trip.name) photo album")) {
                        Label("Invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.appSecondary)
                }

                // Only the device that created the album knows its Photos ID.
                if supportsAlbumSheets && localAlbumID != nil {
                    Button {
                        requiringICloud { isCustomizingAlbum = true }
                    } label: {
                        Label("Manage Album", systemImage: "slider.horizontal.3")
                            .font(AppFont.outfit(14, weight: .medium, relativeTo: .subheadline))
                    }
                    .tint(accent)
                }
            }
        }
    }

    private var howItWorksCard: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("How it works", systemImage: "info.circle")
                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Photos are stored in iCloud, not in Agdayo.")
                    Text("• Each person has to accept the album invite in the Photos app, and needs Shared Albums turned on in Settings → Photos.")
                    Text("• Being on the trip doesn't add someone to the album, or remove them from it. Manage who's in it from the album.")
                }
                .font(AppFont.outfit(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.barlowCondensed(22, weight: .semibold))
                Text(subtitle)
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - System shared-album sheets (iOS 27+)

private extension View {
    /// Adds Apple's shared-album create / add / manage sheets where the system
    /// has them, and does nothing on earlier iOS versions.
    @ViewBuilder
    func sharedAlbumSheets(
        isCreating: Binding<Bool>,
        isCustomizing: Binding<Bool>,
        isPosting: Binding<Bool>,
        items: [PhotosPickerItem],
        tripName: String,
        localAlbumID: String?,
        onCreated: @escaping (_ url: URL, _ identifier: String?) -> Void,
        onPostingFinished: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) -> some View {
        if #available(iOS 27.0, *) {
            modifier(SharedAlbumSheets(
                isCreating: isCreating, isCustomizing: isCustomizing, isPosting: isPosting,
                items: items, tripName: tripName, localAlbumID: localAlbumID,
                onCreated: onCreated, onPostingFinished: onPostingFinished, onError: onError
            ))
        } else {
            self
        }
    }
}

@available(iOS 27.0, *)
private struct SharedAlbumSheets: ViewModifier {
    @Binding var isCreating: Bool
    @Binding var isCustomizing: Bool
    @Binding var isPosting: Bool
    let items: [PhotosPickerItem]
    let tripName: String
    let localAlbumID: String?
    let onCreated: (URL, String?) -> Void
    let onPostingFinished: () -> Void
    let onError: (String) -> Void

    func body(content: Content) -> some View {
        content
            .photosSharedAlbumPostingSheet(
                isPresented: $isPosting,
                items: items,
                defaultAlbumIdentifier: localAlbumID,
                photoLibrary: .shared()
            ) { result in
                // Always close our side of the sheet, whatever happened, so no
                // stale "presented" flag is left behind.
                isPosting = false
                onPostingFinished()
                if case .failure(let error) = result { onError(error.localizedDescription) }
            }
            .photosSharedAlbumCreationSheet(
                isPresented: $isCreating,
                defaultTitle: tripName,
                photoLibrary: .shared()
            ) { result in
                isCreating = false
                // No result means the person closed the sheet without making an album.
                guard let result else { return }
                if let error = result.error {
                    onError(error.localizedDescription)
                } else if let url = result.albumURL {
                    onCreated(url, result.albumIdentifier)
                }
            }
            .photosSharedAlbumCustomizationSheet(
                isPresented: $isCustomizing,
                albumIdentifier: localAlbumID ?? "",
                photoLibrary: .shared()
            ) { _ in
                isCustomizing = false
            }
    }
}
