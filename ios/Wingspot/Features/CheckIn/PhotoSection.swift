import Persistence
import PhotosUI
import SwiftUI

/// The "add one photo" part of a check-in form. The picture is shrunk and stripped of metadata on the device
/// before it is kept, and the original isn't stored.
struct PhotoSection: View {
    @Binding var photo: PreparedPhoto?
    @Binding var isPreparing: Bool

    @State private var item: PhotosPickerItem?
    @State private var failed = false

    var body: some View {
        Section {
            if let photo, let preview = UIImage(data: photo.jpeg) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Your photo")
                Button("Remove photo", role: .destructive) { self.photo = nil }
            } else {
                // The label closure can't read state from the view, so the text is chosen before it.
                let title: LocalizedStringKey = isPreparing ? "Preparing…" : "Add a photo"
                PhotosPicker(selection: $item, matching: .images) {
                    Label(title, systemImage: "photo")
                }
                .disabled(isPreparing)
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Location and other details are removed from the photo before it is saved. It goes up with your check-in when you are signed in.")
        }
        .onChange(of: item) { _, item in
            guard let item else { return }
            Task { await choose(item) }
        }
        .alert("Couldn't use this picture", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Loads the picked picture and removes its metadata, off the main thread.
    private func choose(_ item: PhotosPickerItem) async {
        isPreparing = true
        defer { isPreparing = false; self.item = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = try? await Task.detached(priority: .userInitiated, operation: { try PhotoPreparer.prepare(data) }).value
        else {
            failed = true
            return
        }
        photo = prepared
    }
}
