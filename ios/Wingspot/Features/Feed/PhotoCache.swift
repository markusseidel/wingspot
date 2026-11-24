import Account
import SwiftUI
import UIKit

/// The photos of check-ins, kept by photo id (#341). The link to a photo is signed and new every time the feed is loaded, so a cache keyed by
/// the link (what `AsyncImage` has) never hits, and the default cache skips large pictures. This one keeps the pictures in memory and in the
/// app's caches folder, so a photo that was seen shows at once when the feed comes back. It is cleared when the person signs out.
final class PhotoCache: @unchecked Sendable {
    static let shared = PhotoCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession
    private let maxDiskBytes: Int

    init(directory: URL? = nil, session: URLSession = .shared, maxDiskBytes: Int = 150_000_000) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        self.session = session
        self.maxDiskBytes = maxDiskBytes
        memory.totalCostLimit = 80_000_000
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// The picture if it is in memory already, so a view can show it without a flicker.
    func cached(_ id: UUID) -> UIImage? { memory.object(forKey: id.uuidString as NSString) }

    /// The photo: from memory, else from the disk, else downloaded (and kept). `nil` when it can't be had.
    func image(id: UUID, url: URL) async -> UIImage? {
        if let image = cached(id) { return image }
        let file = fileURL(id)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            remember(image, id: id)
            // Used again: moves it to the back of the line for pruning.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return image
        }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
        remember(image, id: id)
        try? data.write(to: file, options: .atomic)
        prune()
        return image
    }

    /// Forgets everything, on sign-out: the photos belong to the account.
    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// How many bytes the files take.
    func diskBytes() -> Int {
        files().reduce(0) { $0 + $1.size }
    }

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString) }

    private func remember(_ image: UIImage, id: UUID) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memory.setObject(image, forKey: id.uuidString as NSString, cost: cost)
    }

    private func files() -> [(url: URL, size: Int, date: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    /// Keeps the folder under its size by removing the files used longest ago.
    func prune() {
        var all = files().sorted { $0.date < $1.date }
        var total = all.reduce(0) { $0 + $1.size }
        while total > maxDiskBytes, let oldest = all.first {
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
            all.removeFirst()
        }
    }
}

/// Like `AsyncImage(url:)`, but through `PhotoCache`: the same `content` closure with the same phases.
struct CachedImage<Content: View>: View {
    let photo: FeedPhoto
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase

    init(photo: FeedPhoto, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.photo = photo
        self.content = content
        // A photo seen before is there from the first frame.
        if let image = PhotoCache.shared.cached(photo.id) { _phase = State(initialValue: .success(Image(uiImage: image))) }
        else { _phase = State(initialValue: .empty) }
    }

    var body: some View {
        content(phase)
            .task(id: photo.id) {
                if case .success = phase { return }
                if let image = await PhotoCache.shared.image(id: photo.id, url: photo.url) {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure(URLError(.cannotLoadFromNetwork))
                }
            }
    }
}
