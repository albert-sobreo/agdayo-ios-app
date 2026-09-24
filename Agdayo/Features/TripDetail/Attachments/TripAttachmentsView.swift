import Photos
import SwiftUI

/// Trip photo attachments, backed by an iCloud Shared Album the user sets
/// up manually in Photos.app and links here by title — see
/// `Services/Photos/SharedAlbumService.swift` for why (PhotoKit can't create
/// a Shared Album or send invites from app code). Every invited member sees
/// the same photos on their own device once they link the same trip to the
/// same album title; nothing is ever synced through Agdayo's own backend.
///
/// Agdayo is view-only here — adding photos happens in Photos.app itself
/// (the "Open in Photos" button below), since PhotoKit editing of an
/// existing Shared Album from inside the app turned out to be unreliable in
/// practice. Members who aren't invited to the album yet can join via the
/// "Join Shared Album" link, if one's been added.
struct TripAttachmentsView: View {
    let trip: Trip

    @Environment(\.openURL) private var openURL
    @State private var isCheckingAuthorization = true
    @State private var isAuthorized = false
    @State private var linkedAlbum: PHAssetCollection?
    @State private var assets: [PHAsset] = []
    @State private var isChoosingAlbum = false
    @State private var availableAlbums: [PHAssetCollection] = []
    @State private var viewingAsset: PHAsset?
    @State private var isEditingInviteURL = false
    @State private var inviteURLDraft = ""

    var body: some View {
        Group {
            if isCheckingAuthorization {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isAuthorized {
                EmptyStateView(
                    iconName: "photo.on.rectangle.angled",
                    title: "Photos Access Needed",
                    message: "Allow access to Photos to link a Shared Album for this trip's attachments.",
                    actionTitle: "Grant Access",
                    action: { Task { await requestAccess() } }
                )
            } else if let linkedAlbum {
                albumGrid(linkedAlbum)
            } else {
                notLinkedContent
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if linkedAlbum != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openPhotosApp()
                    } label: {
                        Label("Open in Photos", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
        .task {
            await checkAuthorization()
        }
        .sheet(isPresented: $isChoosingAlbum) {
            NavigationStack {
                albumPickerSheet
            }
        }
        .sheet(item: $viewingAsset) { asset in
            AttachmentPagingView(assets: assets, initialAsset: asset)
        }
        .alert("Shared Album Invite Link", isPresented: $isEditingInviteURL) {
            TextField("Paste link here", text: $inviteURLDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save") { saveInviteURL() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("In Photos, open this Shared Album, tap the people icon, then Share Album > Public Website. Copy that link and paste it here so members without access can join.")
        }
    }

    @ViewBuilder
    private var notLinkedContent: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                iconName: "photo.badge.plus",
                title: "No Shared Album Linked",
                message: "Create a Shared Album in Photos, invite your trip-mates, then pick it below. Everyone linked to the same album sees the same photos.",
                actionTitle: "Choose Shared Album",
                action: { presentAlbumPicker() }
            )
        }
    }

    @ViewBuilder
    private func albumGrid(_ album: PHAssetCollection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inviteLinkBanner
                if assets.isEmpty {
                    EmptyStateView(
                        iconName: "photo",
                        title: "No Photos Yet",
                        message: "Open \"\(album.localizedTitle ?? "the shared album")\" in Photos to add some."
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Button {
                                viewingAsset = asset
                            } label: {
                                AttachmentThumbnail(asset: asset)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable {
            resolveLinkedAlbum()
        }
    }

    /// Always shown when an album is linked — either an actionable "join"
    /// link for members who don't have access yet, or a prompt for whoever
    /// linked the album to add one, since there's no PhotoKit API to
    /// generate or fetch that link automatically.
    @ViewBuilder
    private var inviteLinkBanner: some View {
        HStack {
            if let inviteURLString = trip.sharedAlbumInviteURL, let url = URL(string: inviteURLString) {
                Button {
                    openURL(url)
                } label: {
                    Label("Join Shared Album", systemImage: "person.crop.circle.badge.plus")
                        .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                }
                Spacer()
                Button {
                    inviteURLDraft = inviteURLString
                    isEditingInviteURL = true
                } label: {
                    Image(systemName: "pencil")
                }
            } else {
                Text("Members without access yet can join via a link.")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Invite Link") {
                    inviteURLDraft = ""
                    isEditingInviteURL = true
                }
                .font(AppFont.outfit(13, weight: .semibold, relativeTo: .caption))
            }
        }
        .padding()
        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var albumPickerSheet: some View {
        List {
            if availableAlbums.isEmpty {
                Text("No Shared Albums found on this device. Create one in Photos first.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableAlbums, id: \.localIdentifier) { album in
                    Button {
                        link(to: album)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.localizedTitle ?? "Untitled Album")
                                .font(AppFont.outfit(16, weight: .medium, relativeTo: .body))
                                .foregroundStyle(.primary)
                            Text("\(SharedAlbumService.assets(in: album).count) photo(s)")
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Shared Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isChoosingAlbum = false }
            }
        }
    }

    private func checkAuthorization() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            isAuthorized = true
        }
        isCheckingAuthorization = false
        if isAuthorized {
            resolveLinkedAlbum()
        }
    }

    private func requestAccess() async {
        isAuthorized = await SharedAlbumService.requestAuthorization()
        if isAuthorized {
            resolveLinkedAlbum()
        }
    }

    private func resolveLinkedAlbum() {
        guard let title = trip.sharedAlbumTitle else { return }
        linkedAlbum = SharedAlbumService.album(titled: title)
        loadAssets()
    }

    private func loadAssets() {
        guard let linkedAlbum else { assets = []; return }
        var results: [PHAsset] = []
        SharedAlbumService.assets(in: linkedAlbum).enumerateObjects { asset, _, _ in results.append(asset) }
        assets = results
    }

    private func presentAlbumPicker() {
        availableAlbums = SharedAlbumService.fetchSharedAlbums()
        isChoosingAlbum = true
    }

    private func link(to album: PHAssetCollection) {
        trip.sharedAlbumTitle = album.localizedTitle
        trip.updatedAt = .now
        linkedAlbum = album
        loadAssets()
        isChoosingAlbum = false
        pushSharedAlbumFields()
    }

    private func saveInviteURL() {
        let trimmed = inviteURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.sharedAlbumInviteURL = trimmed.isEmpty ? nil : trimmed
        trip.updatedAt = .now
        pushSharedAlbumFields()
    }

    /// `photos-redirect://` is a long-standing, widely used URL scheme for
    /// jumping straight to the Photos app — there's no public API to deep
    /// link into a *specific* album, so the empty-album message and the
    /// invite-link banner above carry the rest of the instructions.
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        openURL(url)
    }

    /// Same "only push if this trip is actually shared" pattern as every
    /// other trip-field edit (see `TripSettingsView.save()`).
    private func pushSharedAlbumFields() {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let name = trip.name
        let location = trip.location
        let theme = trip.theme.rawValue
        let startDate = trip.startDate
        let endDate = trip.endDate
        let overallBudget = trip.overallBudget
        let currency = trip.currency
        let tripDescription = trip.tripDescription
        let latitude = trip.latitude
        let longitude = trip.longitude
        let sharedAlbumTitle = trip.sharedAlbumTitle
        let sharedAlbumInviteURL = trip.sharedAlbumInviteURL
        Task {
            try? await TripMembershipService.updateTripRecord(
                tripID: tripID, name: name, location: location,
                theme: theme, startDate: startDate, endDate: endDate,
                overallBudget: overallBudget, currency: currency, tripDescription: tripDescription,
                latitude: latitude, longitude: longitude, sharedAlbumTitle: sharedAlbumTitle,
                sharedAlbumInviteURL: sharedAlbumInviteURL
            )
        }
    }
}

/// Loads its thumbnail asynchronously — `SharedAlbumService.thumbnail`
/// dispatches to PhotoKit, which is too slow to call synchronously per cell.
private struct AttachmentThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task {
                image = await SharedAlbumService.thumbnail(for: asset, targetSize: CGSize(width: geometry.size.width * 2, height: geometry.size.height * 2))
            }
        }
    }
}

/// Full-screen viewer that pages across every photo in the album, starting
/// at whichever thumbnail was tapped. Built on `ScrollView` +
/// `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` rather than
/// `TabView(.page)` — the latter is known to glitch for this exact use case
/// (blank/flashing pages, content losing laziness), while this scroll-based
/// approach pages smoothly and only renders nearby photos via `LazyHStack`.
private struct AttachmentPagingView: View {
    let assets: [PHAsset]
    let initialAsset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    init(assets: [PHAsset], initialAsset: PHAsset) {
        self.assets = assets
        self.initialAsset = initialAsset
        _selection = State(initialValue: initialAsset.localIdentifier)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AttachmentFullImageView(asset: asset)
                            .containerRelativeFrame(.horizontal)
                            .id(asset.localIdentifier)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .scrollIndicators(.hidden)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AttachmentFullImageView: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            image = await SharedAlbumService.thumbnail(for: asset, targetSize: CGSize(width: 1600, height: 1600))
        }
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}
