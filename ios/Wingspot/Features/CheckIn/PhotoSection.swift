import Account
import Persistence
import PhotosUI
import SwiftUI

/// The photos part of a check-in form: pick several photos at once, see them as thumbnails and remove the ones you don't
/// want. Each picture is shrunk and stripped of metadata on the device before it is kept, and the original isn't stored.
/// The photos keep the order they were picked in, and the first one is the cover. Create and edit forms all use this.
struct PhotoSection: View {
    @Binding var photos: [PreparedPhoto]
    @Binding var isPreparing: Bool
    /// How many photos the check-in can still take in all: the most there are, less the ones it already has.
    var limit = CheckInStore.maxPhotos
    /// The photos the check-in already has on the server, for the edit screens.
    var existing: [FeedPhoto] = []
    /// The existing photos the person removed with the cross. They are only marked: the edit screen deletes them when it is
    /// saved, and cancelling it leaves everything as it was.
    var removedExisting: Binding<Set<UUID>> = .constant([])
    /// Whether the existing photos show a cross.
    var removable = false

    @State private var items: [PhotosPickerItem] = []
    @State private var failedCount = 0

    /// Every existing photo that was removed makes room for one more.
    private var capacity: Int { limit + removedExisting.wrappedValue.count }
    private var shownExisting: [FeedPhoto] { existing.filter { !removedExisting.wrappedValue.contains($0.id) } }

    var body: some View {
        Section {
            if !photos.isEmpty || !shownExisting.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shownExisting) { photo in
                            existingThumbnail(photo)
                        }
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                            thumbnail(photo, index: index)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if photos.count < capacity {
                // The label closure can't read state from the view, so the text is chosen before it.
                let title: LocalizedStringResource = isPreparing ? "Preparing…" : (capacity - photos.count > 1 ? "Add photos" : "Add a photo")
                PhotosPicker(selection: $items, maxSelectionCount: capacity - photos.count, selectionBehavior: .ordered, matching: .images) {
                    Label { Text(title) } icon: { Image(systemName: "photo.on.rectangle") }
                }
                .disabled(isPreparing)
            }
        } header: {
            Text("Photos")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Location and other details are removed from the photos before they are saved. They go up with your check-in when you are signed in.")
                if !removedExisting.wrappedValue.isEmpty {
                    Text("Removed photos are deleted when you save.")
                }
            }
        }
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            Task { await choose(picked) }
        }
        .alert("Couldn't use this picture", isPresented: Binding(get: { failedCount > 0 }, set: { if !$0 { failedCount = 0 } })) {
            Button("OK", role: .cancel) {}
        }
    }

    /// A photo the check-in already has: with a cross to delete it, when this screen can.
    private func existingThumbnail(_ photo: FeedPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            CachedImage(photo: photo) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color(.secondarySystemFill)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Photo")
            if removable {
                Button { removedExisting.wrappedValue.insert(photo.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.title3)
                        .padding(4)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove photo")
            }
        }
    }

    private func thumbnail(_ photo: PreparedPhoto, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let preview = UIImage(data: photo.jpeg) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Your photo")
            }
            Button { photos.remove(at: index) } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
                    .padding(4)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove photo")
        }
    }

    /// Loads the picked pictures one after the other, in the order they were picked, and removes their metadata, off the
    /// main thread. A picture that can't be used is skipped and the others are kept.
    private func choose(_ picked: [PhotosPickerItem]) async {
        isPreparing = true
        defer { isPreparing = false; items = [] }
        var failed = 0
        for item in picked where photos.count < capacity {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let prepared = try? await Task.detached(priority: .userInitiated, operation: { try PhotoPreparer.prepare(data) }).value
            else {
                failed += 1
                continue
            }
            photos.append(prepared)
        }
        failedCount = failed
    }
}
