import Account
import SwiftUI
import UIKit

/// Profile images, for every list that shows people. An image is asked for by the person's ID and cached; a person
/// without one is remembered for this run, so a long feed asks once per person.
@MainActor
@Observable
final class AvatarStore {
    private let projectURL: URL?
    private let backend: (any AvatarBackend)?
    @ObservationIgnored private let cache = NSCache<NSUUID, UIImage>()
    @ObservationIgnored private var misses: Set<UUID> = []
    @ObservationIgnored private var requests: [UUID: Task<UIImage?, Never>] = [:]
    /// Counts the changes made on this phone, so views showing your own image refresh at once.
    private(set) var changes = 0

    init(projectURL: URL?, backend: (any AvatarBackend)?) {
        self.projectURL = projectURL
        self.backend = backend
    }

    /// The person's image, or `nil` if they have none or it can't be loaded now.
    func image(for id: UUID) async -> UIImage? {
        if let cached = cache.object(forKey: id as NSUUID) { return cached }
        guard let projectURL, !misses.contains(id) else { return nil }
        if let running = requests[id] { return await running.value }
        let task = Task { [weak self] () -> UIImage? in
            let url = AvatarImage.url(projectURL: projectURL, userID: id)
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
            let image = status == 200 ? UIImage(data: data) : nil
            // 400 and 404 mean the person has no image. Other answers may pass, so they aren't remembered.
            if image == nil, status == 400 || status == 404 { self?.misses.insert(id) }
            if let image { self?.cache.setObject(image, forKey: id as NSUUID) }
            return image
        }
        requests[id] = task
        let image = await task.value
        requests[id] = nil
        return image
    }

    /// Sets or removes your own image. Throws if the upload fails, and then nothing changes.
    func setMine(_ id: UUID, jpeg: Data?, preview: UIImage?) async throws {
        guard let backend else { throw AccountError.notConfigured }
        if let jpeg { try await backend.uploadAvatar(jpeg) } else { try await backend.removeAvatar() }
        misses.remove(id)
        if let preview { cache.setObject(preview, forKey: id as NSUUID) } else { cache.removeObject(forKey: id as NSUUID); misses.insert(id) }
        changes += 1
    }

    /// Cuts the picture to a centred square, scales it to the profile image size and encodes it as JPEG.
    /// Encoding again also drops location and camera data.
    nonisolated static func prepare(_ data: Data) -> (jpeg: Data, preview: UIImage)? {
        guard let source = UIImage(data: data) else { return nil }
        let size = source.size
        let crop = AvatarImage.squareCrop(width: size.width, height: size.height)
        let side = CGFloat(AvatarImage.side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = side / crop.width
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            source.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale, width: size.width * scale, height: size.height * scale))
        }
        var quality: CGFloat = 0.85
        while quality > 0.3 {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= AvatarImage.maxBytes { return (jpeg, image) }
            quality -= 0.15
        }
        return nil
    }
}

/// A person's picture in a circle, or their first letter when they have none.
struct AvatarView: View {
    let id: UUID?
    let name: String
    var size: CGFloat = 40

    @Environment(AvatarStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.accentColor.opacity(0.15)
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: Reload(id: id, changes: store.changes)) {
            guard let id else { image = nil; return }
            image = await store.image(for: id)
        }
    }

    private struct Reload: Equatable {
        let id: UUID?
        let changes: Int
    }
}
