import Foundation
import SwiftData
import Testing
import WingspotCore
@testable import Persistence

private func temporaryFiles() -> FlightTrackFiles {
    FlightTrackFiles(directory: FileManager.default.temporaryDirectory.appending(path: "tracks-\(UUID().uuidString)", directoryHint: .isDirectory))
}

private let sample = [
    GeoCoordinate(latitude: 50.03, longitude: 8.57), GeoCoordinate(latitude: 40.64, longitude: -73.78),
    GeoCoordinate(latitude: -33.5, longitude: 179.999999),
]

@Test func aTrackIsSavedAndLoadedExactly() throws {
    let files = temporaryFiles(), id = UUID()
    #expect(files.load(id: id) == nil && !files.has(id: id))
    try files.save(sample, for: id)
    #expect(files.has(id: id))
    #expect(files.load(id: id) == sample)
}

@Test func theFileHasTheLayoutBothAppsShare() throws {
    let files = temporaryFiles(), id = UUID()
    try files.save([GeoCoordinate(latitude: 2, longitude: 1)], for: id)
    let data = try Data(contentsOf: files.directory.appending(path: "\(id.uuidString.lowercased()).trk"))
    #expect(data.count == 4 + 16)
    #expect(Array(data.prefix(4)) == Array("WTR1".utf8))
    // 1.0 as little-endian IEEE 754 is 00 00 00 00 00 00 F0 3F
    #expect(Array(data[4..<12]) == [0, 0, 0, 0, 0, 0, 0xF0, 0x3F])
}

@Test func aDamagedFileIsNotATrack() throws {
    let files = temporaryFiles(), id = UUID()
    try files.save(sample, for: id)
    let path = files.directory.appending(path: "\(id.uuidString.lowercased()).trk")
    try Data("junk".utf8).write(to: path)
    #expect(files.load(id: id) == nil)
    try Data("WTR1abc".utf8).write(to: path)
    #expect(files.load(id: id) == nil)
}

@Test func deletingRemovesTheFile() throws {
    let files = temporaryFiles(), a = UUID(), b = UUID()
    try files.save(sample, for: a)
    try files.save(sample, for: b)
    files.delete(id: a)
    #expect(files.load(id: a) == nil && files.load(id: b) == sample)
    files.delete(ids: [b, a])
    #expect(!files.has(id: b))
}

@MainActor @Test func deletingAFlightAndErasingAnAccountRemoveTheirTracks() throws {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, BadgeAck.self, BadgeAccount.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let files = temporaryFiles()
    let store = CheckInStore(context: context, tracks: files)
    let me = UUID(), other = UUID()
    let draft = { FlownDraft(origin: .init(airportID: 1, code: "AAA"), destination: .init(airportID: 2, code: "BBB"), distanceKm: 100) }
    let first = try store.saveFlown(draft(), ownerID: me)
    let second = try store.saveFlown(draft(), ownerID: me)
    let third = try store.saveFlown(draft(), ownerID: other)
    for result in [first, second, third] { try files.save(sample, for: result.id) }

    try store.deleteLocal(id: first.id)
    #expect(files.load(id: first.id) == nil && files.load(id: second.id) == sample)

    try AccountEraser(context: context, tracks: files).erase(userID: me)
    #expect(files.load(id: second.id) == nil, "the erased account's track is gone")
    #expect(files.load(id: third.id) == sample, "another account's track stays")
}
