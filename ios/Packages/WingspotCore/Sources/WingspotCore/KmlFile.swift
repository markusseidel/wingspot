import Foundation

/// Which files shared or opened into the app are read as a flight track (#236).
public enum KmlFile {
    /// A `.kml` file on disk. A KMZ (zipped), a GPX, a link and anything else is not.
    public static func isKml(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == "kml"
    }
}
