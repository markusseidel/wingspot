import SwiftUI
import UIKit

/// The system share sheet for a file, so the person can save it to Files, send it by mail and so on.
struct ShareSheet: UIViewControllerRepresentable {
    let file: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file to share. Identifiable so a sheet can open for it.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
