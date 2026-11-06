import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
import WingspotCore
@testable import Persistence

/// A JPEG like a phone makes it: big, turned on its side by an orientation flag, and full of metadata including
/// the place it was taken.
private func phoneJPEG(width: Int = 4000, height: Int = 3000, orientation: Int = 6) throws -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())

    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: orientation,
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 50.03, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 8.57, kCGImagePropertyGPSLongitudeRef: "E",
        ],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:06 10:00:00"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "EOS R5"],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

private func properties(of jpeg: Data) throws -> [String: Any] {
    let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
    return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
}

/// The same rule the server applies: EXIF and XMP live in an APP1 segment (0xFFE1), and other application
/// segments except JFIF (E0), the colour profile (E2) and Adobe's colour flag (EE) are refused.
private func refusedSegments(in jpeg: Data) -> [UInt8] {
    let bytes = [UInt8](jpeg)
    var found: [UInt8] = []
    var i = 2
    while i + 4 <= bytes.count, bytes[i] == 0xFF {
        let marker = bytes[i + 1]
        if marker == 0xFF { i += 1; continue }
        if (0xE1...0xEF).contains(marker), marker != 0xE2, marker != 0xEE { found.append(marker) }
        if marker == 0xFE { found.append(marker) }
        if marker == 0xDA { break }
        i += 2 + (Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]))
    }
    return found
}

struct PhotoPreparerTests {
    @Test func theTestPictureReallyCarriesALocation() throws {
        let original = try phoneJPEG()
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary as String] != nil)
    }

    @Test func removesTheLocationAndEveryOtherPieceOfMetadata() throws {
        let prepared = try PhotoPreparer.prepare(try phoneJPEG())
        let result = try properties(of: prepared.jpeg)
        #expect(result[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(result[kCGImagePropertyTIFFDictionary as String] == nil)
        let exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] == nil)
        #expect(refusedSegments(in: prepared.jpeg).isEmpty, "the server refuses these segments")
        #expect(!String(decoding: prepared.jpeg, as: UTF8.self).contains("Canon"))
    }

    @Test func shrinksToTheLimitAndTurnsThePictureUpright() throws {
        // 4000 x 3000 with orientation 6 is a portrait picture: 3000 wide and 4000 tall once turned.
        let prepared = try PhotoPreparer.prepare(try phoneJPEG())
        #expect(max(prepared.width, prepared.height) == PhotoPreparer.maxPixels)
        #expect(prepared.height > prepared.width)
        #expect(prepared.jpeg.count <= PhotoPreparer.maxBytes)
        let result = try properties(of: prepared.jpeg)
        #expect(result[kCGImagePropertyPixelWidth as String] as? Int == prepared.width)
        #expect(result[kCGImagePropertyOrientation as String] == nil || result[kCGImagePropertyOrientation as String] as? Int == 1)
    }

    @Test func leavesSmallPicturesTheirSize() throws {
        let prepared = try PhotoPreparer.prepare(try phoneJPEG(width: 800, height: 600, orientation: 1))
        #expect(prepared.width == 800)
        #expect(prepared.height == 600)
    }

    @Test func refusesWhatIsNotAPicture() {
        #expect(throws: PhotoError.unreadable) { try PhotoPreparer.prepare(Data("hello".utf8)) }
    }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: LocalCheckIn.self, LocalPhoto.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let photo = PreparedPhoto(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 800, height: 600)
private let alice = UUID()
private let bob = UUID()

private actor FakePhotoServer: PhotoUploader {
    enum Answer { case stored, rejected(String), notThereYet, networkDown }
    var answer = Answer.stored
    private(set) var uploaded: [(photo: UUID, checkIn: UUID)] = []

    func set(_ answer: Answer) { self.answer = answer }

    func upload(photoID: UUID, checkInID: UUID, jpeg: Data) async throws -> PhotoUploadOutcome {
        uploaded.append((photoID, checkInID))
        switch answer {
        case .stored: return .stored
        case .rejected(let code): return .rejected(code: code)
        case .notThereYet: return .checkInNotThereYet
        case .networkDown: throw URLError(.notConnectedToInternet)
        }
    }
}

@MainActor private func savedPhoto(_ context: ModelContext, owner: UUID? = nil) throws -> (checkIn: LocalCheckIn, photo: LocalPhoto) {
    _ = try CheckInStore(context: context).saveSpotted(
        SpottedDraft(registration: Registration("DAIMA"), photo: photo), ownerID: owner
    )
    return (try #require(try context.fetch(FetchDescriptor<LocalCheckIn>()).first),
            try #require(try context.fetch(FetchDescriptor<LocalPhoto>()).first))
}

@MainActor struct PhotoOutboxTests {
    @Test func aPhotoIsSavedTogetherWithItsCheckIn() throws {
        let context = try makeContext()
        let saved = try savedPhoto(context)
        #expect(saved.photo.checkInID == saved.checkIn.id)
        #expect(saved.photo.syncState == "pending")
        #expect(saved.photo.jpeg == photo.jpeg)
        #expect(saved.photo.width == 800)
    }

    @Test func aCheckInWithoutAPhotoSavesNone() throws {
        let context = try makeContext()
        _ = try CheckInStore(context: context).saveSpotted(SpottedDraft(registration: Registration("DAIMA")))
        #expect(try context.fetchCount(FetchDescriptor<LocalPhoto>()) == 0)
    }

    @Test func aPhotoWaitsUntilItsCheckInIsOnTheServer() async throws {
        let context = try makeContext()
        let saved = try savedPhoto(context, owner: alice)
        let server = FakePhotoServer()
        let outbox = PhotoOutbox(context: context, uploader: server)

        #expect(await outbox.sync(userID: alice) == .idle)
        #expect(await server.uploaded.isEmpty)

        saved.checkIn.syncState = SyncState.synced.rawValue
        #expect(await outbox.sync(userID: alice) == .finished(stored: 1, rejected: 0))
        #expect(saved.photo.syncState == "synced")
        #expect(await server.uploaded.count == 1)
        #expect(await outbox.sync(userID: alice) == .idle, "a stored photo is not sent again")
    }

    @Test func aFailedRequestOrAMissingCheckInKeepsThePhotoWaiting() async throws {
        let context = try makeContext()
        let saved = try savedPhoto(context, owner: alice)
        saved.checkIn.syncState = SyncState.synced.rawValue
        let server = FakePhotoServer()
        let outbox = PhotoOutbox(context: context, uploader: server)

        await server.set(.networkDown)
        #expect(await outbox.sync(userID: alice) == .retryLater(stored: 0, rejected: 0))
        await server.set(.notThereYet)
        #expect(await outbox.sync(userID: alice) == .retryLater(stored: 0, rejected: 0))
        #expect(saved.photo.syncState == "pending")

        await server.set(.stored)
        #expect(await outbox.sync(userID: alice) == .finished(stored: 1, rejected: 0))
    }

    @Test func aRefusedPhotoStaysOnTheDeviceAndIsNotSentAgain() async throws {
        let context = try makeContext()
        let saved = try savedPhoto(context, owner: alice)
        saved.checkIn.syncState = SyncState.synced.rawValue
        let server = FakePhotoServer()
        await server.set(.rejected("too_many_photos"))
        let outbox = PhotoOutbox(context: context, uploader: server)

        #expect(await outbox.sync(userID: alice) == .finished(stored: 0, rejected: 1))
        #expect(saved.photo.syncState == "rejected")
        #expect(saved.photo.syncError == "too_many_photos")
        #expect(await outbox.sync(userID: alice) == .idle)
        #expect(await server.uploaded.count == 1)
    }

    @Test func aPhotoWhoseCheckInWasRejectedIsRejectedToo() async throws {
        let context = try makeContext()
        let saved = try savedPhoto(context, owner: alice)
        saved.checkIn.syncState = SyncState.rejected.rawValue
        let server = FakePhotoServer()

        #expect(await PhotoOutbox(context: context, uploader: server).sync(userID: alice) == .finished(stored: 0, rejected: 1))
        #expect(saved.photo.syncError == "checkin_rejected")
        #expect(await server.uploaded.isEmpty)
    }

    @Test func anotherAccountsPhotosStayOnTheDevice() async throws {
        let context = try makeContext()
        let saved = try savedPhoto(context, owner: alice)
        saved.checkIn.syncState = SyncState.synced.rawValue
        let server = FakePhotoServer()

        #expect(await PhotoOutbox(context: context, uploader: server).sync(userID: bob) == .idle)
        #expect(await server.uploaded.isEmpty)
        #expect(saved.photo.syncState == "pending")
    }
}
