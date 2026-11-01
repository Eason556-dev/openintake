import SwiftUI
import VisionKit
import Vision

struct LabelScanner: UIViewControllerRepresentable {
    var completion: (Result<OCRDocument, Error>) -> Void
    var cancellation: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion, cancellation) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        var completion: (Result<OCRDocument, Error>) -> Void
        var cancellation: () -> Void
        init(_ completion: @escaping (Result<OCRDocument, Error>) -> Void, _ cancellation: @escaping () -> Void) { self.completion = completion; self.cancellation = cancellation }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { cancellation() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completion(.failure(error)) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage }
            Task {
                do {
                    let document = try await Task.detached(priority: .userInitiated) { try await DocumentOCR.recognize(images) }.value
                    completion(.success(document))
                } catch { completion(.failure(error)) }
            }
        }
    }
}
