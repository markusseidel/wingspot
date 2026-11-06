import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo ready to save and upload: a JPEG with no metadata.
public struct PreparedPhoto: Equatable, Sendable {
    public let jpeg: Data
    public let width: Int
    public let height: Int

    public init(jpeg: Data, width: Int, height: Int) {
        self.jpeg = jpeg
        self.width = width
        self.height = height
    }
}

public enum PhotoError: Error, Equatable {
    case unreadable
    case tooLarge
}

/// Turns any picture the user picks into what Wingspot stores (concept §4.1): a JPEG of at most 2048 pixels on
/// the long side, turned the right way up, with **no metadata at all**. The picture is drawn again from its pixels,
/// so the location, the camera and the date in the original are not carried over. The original is not kept.
public enum PhotoPreparer {
    public static let maxPixels = 2048
    /// The server refuses anything above 3 MB.
    public static let maxBytes = 2_900_000

    public static func prepare(_ original: Data) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { throw PhotoError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // applies the orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoError.unreadable
        }

        for quality in [0.8, 0.65, 0.5] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
            else { throw PhotoError.unreadable }
            // Only the compression quality is set. Nothing is copied over from the original's properties.
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PhotoError.unreadable }
            let clean = removingMetadata(from: output as Data)
            if clean.count <= maxBytes {
                return PreparedPhoto(jpeg: clean, width: image.width, height: image.height)
            }
        }
        throw PhotoError.tooLarge
    }

    /// ImageIO still writes a small EXIF segment with the picture's size and colour space. Nothing in it is
    /// personal, but the server refuses every segment that could carry a location, so these are cut out too.
    /// Kept: the JFIF header (E0), the colour profile (E2, so colours stay right) and Adobe's colour flag (EE).
    static func removingMetadata(from jpeg: Data) -> Data {
        let bytes = [UInt8](jpeg)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return jpeg }
        var result: [UInt8] = [0xFF, 0xD8]
        var i = 2
        while i + 4 <= bytes.count, bytes[i] == 0xFF {
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }
            if marker == 0xDA { break }  // the picture data starts here, with no more metadata after it
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return jpeg }
            let isMetadata = (0xE1...0xEF).contains(marker) && marker != 0xE2 && marker != 0xEE || marker == 0xFE
            if !isMetadata { result.append(contentsOf: bytes[i..<(i + 2 + length)]) }
            i += 2 + length
        }
        result.append(contentsOf: bytes[i...])
        return Data(result)
    }
}
