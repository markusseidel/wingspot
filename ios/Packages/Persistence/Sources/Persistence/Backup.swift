import Foundation
import SwiftData
import WingspotCore

/// What can go wrong when reading a backup, in the words the restore screen uses.
public enum BackupError: Error, Equatable, Sendable {
    /// Not a Wingspot backup at all.
    case notBackup
    /// Made by a newer Wingspot with a layout this app does not know.
    case newerVersion
    /// A Wingspot backup that cannot be read: cut off or changed.
    case damaged
}

/// The backup file (docs/BACKUP-FORMAT.md): the routes of imported flights and the check-ins only this phone has, as one
/// gzip-compressed JSON document. The same layout is written and read by the Android app.
public struct BackupDocument: Codable, Sendable, Equatable {
    public static let formatName = "wingspot-backup"
    public static let currentSchema = 1

    public var format: String
    public var schema: Int
    public var createdAt: String
    public var app: String?
    public var platform: String?
    public var counts: Counts?
    public var routes: Routes
    public var checkins: [BackupCheckIn]

    public struct Counts: Codable, Sendable, Equatable {
        public var routes: Int
        public var checkins: Int
    }

    /// A GeoJSON FeatureCollection, so it can be cut out of the file and opened in any map tool.
    public struct Routes: Codable, Sendable, Equatable {
        public var type: String
        public var features: [Feature]
    }

    public struct Feature: Codable, Sendable, Equatable {
        public var type: String
        public var properties: Properties
        public var geometry: Geometry
    }

    public struct Properties: Codable, Sendable, Equatable {
        public var checkinId: String
        public var flightNumber: String?
        public var origin: String?
        public var destination: String?
        public var day: String?
    }

    public struct Geometry: Codable, Sendable, Equatable {
        public var type: String
        /// `[longitude, latitude]` pairs.
        public var coordinates: [[Double]]
    }

    /// When the backup was made, if the date can be read.
    public var createdDate: Date? { BackupDates.parse(createdAt) }
}

/// A check-in in the backup. Ids are kept as text: both apps write them in lower case.
public struct BackupCheckIn: Codable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var occurredAt: String
    public var timeKnown: Bool?
    public var savedAt: String?
    public var registration: String?
    public var typeIcao: String?
    public var typeName: String?
    public var airportId: Int?
    public var airportCode: String?
    public var latitude: Double?
    public var longitude: Double?
    public var visitContext: String?
    public var spotId: Int?
    public var spotName: String?
    public var visitId: String?
    public var originId: Int?
    public var originCode: String?
    public var destinationId: Int?
    public var destinationCode: String?
    public var flightNumber: String?
    public var cabin: String?
    public var seat: String?
    public var flightId: String?
    public var sourceId: String?
}

enum BackupDates {
    static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) { return date }
        return try? Date(text, strategy: .iso8601)
    }

    static func format(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}

/// Writes and reads the file: JSON with snake_case keys, gzip around it. Reading also takes the plain, unzipped JSON.
public enum BackupCodec {
    /// Bigger than any real backup (100 flights take tens of megabytes); a file that unzips to more is refused.
    static let maximumSize = 200 * 1024 * 1024

    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return try Gzip.compress(encoder.encode(document))
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        let json: Data
        if data.starts(with: [0x1F, 0x8B]) {
            json = try Gzip.decompress(data, limit: maximumSize)
        } else if data.first(where: { ![0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF].contains($0) }) == UInt8(ascii: "{") {
            json = data
        } else {
            throw BackupError.notBackup
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        struct Header: Decodable { var format: String?; var schema: Int? }
        guard let header = try? decoder.decode(Header.self, from: json) else { throw BackupError.damaged }
        guard header.format == BackupDocument.formatName, let schema = header.schema else { throw BackupError.notBackup }
        guard schema <= BackupDocument.currentSchema else { throw BackupError.newerVersion }
        guard let document = try? decoder.decode(BackupDocument.self, from: json) else { throw BackupError.damaged }
        return document
    }
}

/// gzip (RFC 1952) around the raw DEFLATE that Foundation writes and reads.
enum Gzip {
    static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
        out.append(deflated)
        appendLittleEndian(crc32(data), to: &out)
        appendLittleEndian(UInt32(truncatingIfNeeded: data.count), to: &out)
        return out
    }

    static func decompress(_ data: Data, limit: Int) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else { throw BackupError.damaged }
        let flags = bytes[3]
        var position = 10
        if flags & 0x04 != 0 {
            guard position + 2 <= bytes.count else { throw BackupError.damaged }
            position += 2 + Int(bytes[position]) + Int(bytes[position + 1]) << 8
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
            while position < bytes.count, bytes[position] != 0 { position += 1 }
            position += 1
        }
        if flags & 0x02 != 0 { position += 2 }
        guard position <= bytes.count - 8 else { throw BackupError.damaged }
        let size = Int(readLittleEndian(bytes, at: bytes.count - 4))
        guard size <= limit else { throw BackupError.damaged }
        let body = Data(bytes[position..<(bytes.count - 8)])
        guard let inflated = try? (body as NSData).decompressed(using: .zlib) as Data,
              inflated.count <= limit,
              UInt32(truncatingIfNeeded: inflated.count) == UInt32(size),
              crc32(inflated) == readLittleEndian(bytes, at: bytes.count - 8) else { throw BackupError.damaged }
        return inflated
    }

    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readLittleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
}

/// What a backup would bring, for the review before restoring.
public struct BackupPreview: Equatable, Sendable {
    public let created: Date?
    public let platform: String?
    public let routes: Int
    public let checkIns: Int
    /// Routes whose flight is on this phone already. None while signed in means the flights may belong to another account,
    /// or have not come back from the server yet.
    public let routesWithFlightHere: Int
}

/// What restoring did.
public struct BackupResult: Equatable, Sendable {
    public var routes = 0
    public var checkIns = 0
    public var skipped = 0
}

/// Makes a backup of this phone and restores one into it. Restore only adds (docs/BACKUP-PLAN.md, decision 6).
@MainActor
public struct BackupService {
    private let context: ModelContext
    private let tracks: FlightTrackFiles

    public init(context: ModelContext, tracks: FlightTrackFiles = .standard) {
        self.context = context
        self.tracks = tracks
    }

    /// The routes on this phone and the check-ins the server does not have.
    public func make(app: String, now: Date = .now) throws -> BackupDocument {
        let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var features: [BackupDocument.Feature] = []
        for id in tracks.ids().sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let points = tracks.load(id: id), points.count >= 2 else { continue }
            let flight = byID[id]
            features.append(BackupDocument.Feature(
                type: "Feature",
                properties: BackupDocument.Properties(
                    checkinId: id.uuidString.lowercased(), flightNumber: flight?.flightNumber, origin: flight?.originCode,
                    destination: flight?.destinationCode, day: flight.map { BackupDates.day($0.occurredAt) }
                ),
                geometry: BackupDocument.Geometry(type: "LineString", coordinates: points.map { [round5($0.longitude), round5($0.latitude)] })
            ))
        }
        let local = all.filter { $0.syncState != SyncState.synced.rawValue }.sorted { $0.occurredAt < $1.occurredAt }
        let checkIns = local.map(Self.backupCheckIn)
        return BackupDocument(
            format: BackupDocument.formatName, schema: BackupDocument.currentSchema, createdAt: BackupDates.format(now),
            app: app, platform: "ios", counts: .init(routes: features.count, checkins: checkIns.count),
            routes: .init(type: "FeatureCollection", features: features), checkins: checkIns
        )
    }

    public func preview(_ document: BackupDocument) throws -> BackupPreview {
        let ids = Set(try context.fetch(FetchDescriptor<LocalCheckIn>()).map(\.id))
        let routeIDs = document.routes.features.compactMap { UUID(uuidString: $0.properties.checkinId) }
        return BackupPreview(
            created: document.createdDate, platform: document.platform, routes: routeIDs.count, checkIns: document.checkins.count,
            routesWithFlightHere: routeIDs.filter { ids.contains($0) }.count
        )
    }

    public func restore(_ document: BackupDocument, replaceRoutes: Bool) throws -> BackupResult {
        var result = BackupResult()
        let here = Set(try context.fetch(FetchDescriptor<LocalCheckIn>()).map(\.id))
        for item in document.checkins {
            guard let checkIn = Self.localCheckIn(item) else { result.skipped += 1; continue }
            if here.contains(checkIn.id) { result.skipped += 1; continue }
            context.insert(checkIn)
            result.checkIns += 1
        }
        try context.save()
        for feature in document.routes.features {
            guard let id = UUID(uuidString: feature.properties.checkinId), let points = Self.points(feature.geometry) else {
                result.skipped += 1
                continue
            }
            if tracks.has(id: id), !replaceRoutes { result.skipped += 1; continue }
            try tracks.save(points, for: id)
            result.routes += 1
        }
        return result
    }

    private func round5(_ value: Double) -> Double { (value * 100_000).rounded() / 100_000 }

    private static func points(_ geometry: BackupDocument.Geometry) -> [GeoCoordinate]? {
        guard geometry.type == "LineString", geometry.coordinates.count >= 2 else { return nil }
        var points: [GeoCoordinate] = []
        points.reserveCapacity(geometry.coordinates.count)
        for pair in geometry.coordinates {
            guard pair.count >= 2, (-180...180).contains(pair[0]), (-90...90).contains(pair[1]) else { return nil }
            points.append(GeoCoordinate(latitude: pair[1], longitude: pair[0]))
        }
        return points
    }

    static func backupCheckIn(_ c: LocalCheckIn) -> BackupCheckIn {
        BackupCheckIn(
            id: c.id.uuidString.lowercased(), kind: c.kind, occurredAt: BackupDates.format(c.occurredAt),
            timeKnown: c.timeKnown == false ? false : nil, savedAt: c.savedAt.map(BackupDates.format),
            registration: c.registration, typeIcao: c.typeICAO, typeName: c.typeName, airportId: c.airportID,
            airportCode: c.airportCode, latitude: c.latitude, longitude: c.longitude, visitContext: c.visitContext,
            spotId: c.spotID, spotName: c.spotName, visitId: c.visitID?.uuidString.lowercased(),
            originId: c.originID, originCode: c.originCode, destinationId: c.destinationID, destinationCode: c.destinationCode,
            flightNumber: c.flightNumber, cabin: c.cabin, seat: c.seat, flightId: c.flightID?.uuidString.lowercased(),
            sourceId: c.sourceID?.uuidString.lowercased()
        )
    }

    /// A pending check-in with no owner, so it goes to the account that is signed in or signs in next. Nil when it cannot be used.
    static func localCheckIn(_ b: BackupCheckIn) -> LocalCheckIn? {
        guard let id = UUID(uuidString: b.id), ["spotted", "airport", "flown"].contains(b.kind),
              let occurredAt = BackupDates.parse(b.occurredAt) else { return nil }
        if let latitude = b.latitude, !(-90...90).contains(latitude) { return nil }
        if let longitude = b.longitude, !(-180...180).contains(longitude) { return nil }
        return LocalCheckIn(
            id: id, kind: b.kind, registration: b.registration, typeICAO: b.typeIcao, typeName: b.typeName, airportID: b.airportId,
            airportCode: b.airportCode, latitude: b.latitude, longitude: b.longitude, occurredAt: occurredAt, syncState: .pending,
            ownerID: nil, visitContext: b.visitContext, originID: b.originId, destinationID: b.destinationId, originCode: b.originCode,
            destinationCode: b.destinationCode, flightNumber: b.flightNumber, cabin: b.cabin, seat: b.seat,
            flightID: b.flightId.flatMap(UUID.init(uuidString:)), sourceID: b.sourceId.flatMap(UUID.init(uuidString:)),
            spotID: b.spotId, spotName: b.spotName, visitID: b.visitId.flatMap(UUID.init(uuidString:)),
            savedAt: b.savedAt.flatMap(BackupDates.parse), timeKnown: b.timeKnown == false ? false : nil
        )
    }
}
