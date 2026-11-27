import Foundation
import SwiftData
import Testing
import WingspotCore
@testable import Persistence

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, BadgeAck.self, BadgeAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func temporaryFiles() -> FlightTrackFiles {
    FlightTrackFiles(directory: FileManager.default.temporaryDirectory.appending(path: "tracks-\(UUID().uuidString)", directoryHint: .isDirectory))
}

/// The made-up backup both apps read, from `contracts/test-vectors/backup/`.
private func vector(_ name: String) throws -> Data {
    var url = URL(filePath: #filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    return try Data(contentsOf: url.appending(path: "contracts/test-vectors/backup/\(name)"))
}

private let flightID = UUID(uuidString: "019a0000-0000-7000-8000-000000000001")!
private let spottedID = UUID(uuidString: "019a0000-0000-7000-8000-000000000002")!
private let orphanRouteID = UUID(uuidString: "019a0000-0000-7000-8000-00000000000a")!

@Test func theSharedVectorReadsTheSameZippedAndPlain() throws {
    let zipped = try BackupCodec.decode(vector("example.wingspotbackup"))
    let plain = try BackupCodec.decode(vector("example.json"))
    #expect(zipped == plain)
    #expect(plain.schema == 1 && plain.platform == "android")
    #expect(plain.routes.features.count == 2 && plain.checkins.count == 2)
    #expect(plain.routes.features[0].geometry.coordinates[2] == [-73.77814, 40.64131])
    #expect(plain.checkins[0].typeIcao == "A359" && plain.checkins[0].timeKnown == false)
}

@Test func theSchema2VectorReadsWithWhatTheServerHas() throws {
    let zipped = try BackupCodec.decode(vector("example-schema2.wingspotbackup"))
    let plain = try BackupCodec.decode(vector("example-schema2.json"))
    #expect(zipped == plain && plain.schema == 2 && plain.checkins.count == 3)
    let visit = try #require(plain.checkins.last)
    #expect(visit.onServer == true && visit.ownerId == "019a0000-0000-7000-8000-0000000000ff" && visit.visitContext == "departing")
    #expect(plain.checkins[0].onServer == nil)
}

@Test func whatIsNotABackupIsTold() throws {
    #expect(throws: BackupError.notBackup) { try BackupCodec.decode(Data("hello".utf8)) }
    #expect(throws: BackupError.notBackup) { try BackupCodec.decode(Data(#"{"format":"other","schema":1}"#.utf8)) }
    #expect(throws: BackupError.newerVersion) { try BackupCodec.decode(Data(#"{"format":"wingspot-backup","schema":99}"#.utf8)) }
    #expect(throws: BackupError.damaged) { try BackupCodec.decode(vector("truncated.wingspotbackup")) }
    var cut = try vector("example.wingspotbackup")
    cut.removeLast(20)
    #expect(throws: BackupError.damaged) { try BackupCodec.decode(cut) }
}

@Test func gzipIsTheStandardOne() throws {
    let text = Data(String(repeating: "Wingspot ", count: 500).utf8)
    let zipped = try Gzip.compress(text)
    #expect(Array(zipped.prefix(3)) == [0x1F, 0x8B, 0x08])
    #expect(try Gzip.decompress(zipped, limit: 1_000_000) == text)
    #expect(Gzip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
}

@MainActor @Test func aBackupRestoresOnAnEmptyPhone() throws {
    let context = try makeContext(), tracks = temporaryFiles()
    let result = try BackupService(context: context, tracks: tracks).restore(BackupCodec.decode(vector("example.json")), replaceRoutes: false)
    #expect(result == BackupResult(routes: 2, checkIns: 2, skipped: 0))
    let all = try context.fetch(FetchDescriptor<LocalCheckIn>())
    #expect(Set(all.map(\.id)) == [flightID, spottedID])
    let flight = try #require(all.first { $0.id == flightID })
    #expect(flight.syncState == SyncState.pending.rawValue && flight.ownerID == nil)
    #expect(flight.timeKnown == false && flight.seat == "34K" && flight.originCode == "FRA")
    // A route whose flight is not here yet is kept for when it arrives.
    #expect(tracks.load(id: orphanRouteID)?.count == 2)
    #expect(tracks.load(id: flightID)?.last == GeoCoordinate(latitude: 40.64131, longitude: -73.77814))
}

@MainActor @Test func restoringTwiceAddsNothingAndReplacingIsAChoice() throws {
    let context = try makeContext(), tracks = temporaryFiles()
    let service = BackupService(context: context, tracks: tracks)
    let document = try BackupCodec.decode(vector("example.json"))
    _ = try service.restore(document, replaceRoutes: false)
    try tracks.save([GeoCoordinate(latitude: 1, longitude: 1), GeoCoordinate(latitude: 2, longitude: 2)], for: flightID)
    #expect(try service.restore(document, replaceRoutes: false) == BackupResult(routes: 0, checkIns: 0, skipped: 4))
    #expect(tracks.load(id: flightID)?.count == 2)
    #expect(try service.restore(document, replaceRoutes: true) == BackupResult(routes: 2, checkIns: 0, skipped: 2))
    #expect(tracks.load(id: flightID)?.count == 3)
    #expect(try context.fetch(FetchDescriptor<LocalCheckIn>()).count == 2)
}

@MainActor @Test func aBackupHoldsRoutesAndEveryCheckIn() throws {
    let context = try makeContext(), tracks = temporaryFiles()
    let store = CheckInStore(context: context, tracks: tracks)
    let fra = SpottedDraft.Place(airportID: 2212, code: "FRA"), jfk = SpottedDraft.Place(airportID: 3797, code: "JFK")
    let flown = try store.saveFlown(FlownDraft(origin: fra, destination: jfk, flightNumber: "LH400"))
    let sent = try store.saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
    try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first { $0.id == sent.id }).syncState = SyncState.synced.rawValue
    try tracks.save([GeoCoordinate(latitude: 50.033333333, longitude: 8.570634567), GeoCoordinate(latitude: 40.64, longitude: -73.78)], for: flown.id)

    let document = try BackupService(context: context, tracks: tracks).make(app: "Wingspot test", now: Date(timeIntervalSince1970: 0))
    // The flight, the two airport visits it made, and the sighting the server has, marked as such.
    #expect(document.checkins.contains { $0.id == flown.id.uuidString.lowercased() } && document.checkins.count == 4)
    #expect(document.checkins.filter { $0.onServer == true }.map(\.id) == [sent.id.uuidString.lowercased()])
    #expect(document.routes.features.first?.properties.flightNumber == "LH400")
    #expect(document.createdAt == "1970-01-01T00:00:00Z")

    let data = try BackupCodec.encode(document)
    let json = try #require(String(data: Gzip.decompress(data, limit: 1_000_000), encoding: .utf8))
    #expect(json.contains("[8.57063,50.03333]"))
    #expect(json.contains(#""checkin_id":""#) && json.contains(#""type":"FeatureCollection""#))
    #expect(!json.contains("ownerID") && json.contains(#""on_server":true"#))

    // Round trip onto another phone.
    let other = try makeContext(), otherTracks = temporaryFiles()
    let result = try BackupService(context: other, tracks: otherTracks).restore(BackupCodec.decode(data), replaceRoutes: false)
    #expect(result == BackupResult(routes: 1, checkIns: 4, skipped: 0))
    #expect(try other.fetch(FetchDescriptor<LocalCheckIn>()).filter { $0.syncState == SyncState.pending.rawValue }.count == 3)
    #expect(otherTracks.load(id: flown.id)?.first == GeoCoordinate(latitude: 50.03333, longitude: 8.57063))
}

@MainActor @Test func thePreviewCountsRoutesWhoseFlightIsHere() throws {
    let context = try makeContext(), tracks = temporaryFiles()
    let service = BackupService(context: context, tracks: tracks)
    let document = try BackupCodec.decode(vector("example.json"))
    #expect(try service.preview(document).routesWithFlightHere == 0)
    _ = try service.restore(document, replaceRoutes: false)
    let preview = try service.preview(document)
    #expect(preview.routes == 2 && preview.checkIns == 2 && preview.routesWithFlightHere == 1)
}
