import Foundation

/// Loads shared test vectors from `contracts/test-vectors/` at the repository root.
enum TestVectors {
    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T {
        // This file lives at ios/Packages/BCBP/Tests/BCBPTests/.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        url.append(path: "contracts/test-vectors/\(name).json")
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Could not load test vectors \(url.path): \(error)")
        }
    }
}
