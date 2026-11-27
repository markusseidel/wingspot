import Foundation
import WingspotCore

/// The tracks of imported flights, kept **on this iPhone only**: one small file per check-in, named by its id. Nothing here
/// is uploaded. A file is 4 bytes of header ("WTR1") and then 16 bytes per position, longitude and latitude as little-endian
/// 64-bit floats, so 50 000 positions take about 800 kB. The Android app uses the same layout.
public struct FlightTrackFiles: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The folder the app uses: `FlightTracks` in Application Support.
    public static var standard: FlightTrackFiles {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return FlightTrackFiles(directory: base.appending(path: "FlightTracks", directoryHint: .isDirectory))
    }

    private static let header = Data("WTR1".utf8)

    private func url(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString.lowercased()).trk", directoryHint: .notDirectory) }

    public func save(_ points: [GeoCoordinate], for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = Self.header
        data.reserveCapacity(Self.header.count + points.count * 16)
        for point in points {
            for value in [point.longitude, point.latitude] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        try data.write(to: url(id), options: .atomic)
    }

    /// The positions saved for a check-in, or nil if there are none or the file is damaged.
    public func load(id: UUID) -> [GeoCoordinate]? {
        guard let data = try? Data(contentsOf: url(id)), data.count >= Self.header.count,
              data.prefix(Self.header.count) == Self.header, (data.count - Self.header.count) % 16 == 0 else { return nil }
        let body = data.dropFirst(Self.header.count)
        var points: [GeoCoordinate] = []
        points.reserveCapacity(body.count / 16)
        var offset = body.startIndex
        func double(at start: Data.Index) -> Double {
            var bits: UInt64 = 0
            for byte in 0..<8 { bits |= UInt64(body[start + byte]) << (8 * UInt64(byte)) }
            return Double(bitPattern: bits)
        }
        while offset < body.endIndex {
            points.append(GeoCoordinate(latitude: double(at: offset + 8), longitude: double(at: offset)))
            offset += 16
        }
        return points
    }

    /// The check-ins that have a saved route, for the backup.
    public func ids() -> [UUID] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".trk") else { return nil }
            return UUID(uuidString: String(name.dropLast(4)))
        }
    }

    public func has(id: UUID) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }

    /// Removes every saved route. Flights themselves are not touched.
    public func deleteAll() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".trk") || name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: directory.appending(path: name, directoryHint: .notDirectory))
        }
    }

    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
    }

    public func delete(ids: some Sequence<UUID>) {
        for id in ids { delete(id: id) }
    }
}
