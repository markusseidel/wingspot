import BCBP
import PhotosUI
import SwiftUI
import Vision
import VisionKit

/// Reads boarding pass barcodes. Everything happens on the device. The barcode text is only passed to the parser,
/// which drops the passenger name and booking code, and is never saved or sent anywhere.
enum BoardingPassScanning {
    static let symbologies: [VNBarcodeSymbology] = [.pdf417, .aztec, .qr]

    /// Finds the first boarding pass in an image, such as a screenshot or a photo of a paper pass.
    static func boardingPass(inImageData data: Data) async -> BoardingPass? {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = symbologies
            #if targetEnvironment(simulator)
            // The Simulator has no neural engine, and Vision fails there unless it is told to use the CPU.
            request.usesCPUOnly = true
            #endif
            let handler = VNImageRequestHandler(data: data)
            guard (try? handler.perform([request])) != nil else { return nil }
            return request.results?
                .compactMap { $0.payloadStringValue }
                .lazy
                .compactMap { try? BoardingPass(barcode: $0) }
                .first
        }.value
    }

    @MainActor static var cameraIsAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}

/// A live camera view that reports the first boarding pass it sees.
struct BoardingPassCameraView: View {
    let onFound: (BoardingPass) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CameraScanner(onFound: { pass in
                onFound(pass)
                dismiss()
            })
            .ignoresSafeArea()
            .navigationTitle("Scan boarding pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Hold the barcode inside the frame. Your name and booking code are never saved.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    let onFound: (BoardingPass) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: BoardingPassScanning.symbologies)],
            qualityLevel: .accurate, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (BoardingPass) -> Void
        private var done = false

        init(onFound: @escaping (BoardingPass) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let barcode) in items {
                guard let text = barcode.payloadStringValue, let pass = try? BoardingPass(barcode: text) else { continue }
                done = true
                scanner.stopScanning()
                onFound(pass)
                return
            }
        }
    }
}
