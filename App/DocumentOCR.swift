import Foundation
import CoreGraphics
import Vision

enum DocumentOCR {
    static func recognize(_ images: [CGImage]) async throws -> OCRDocument {
        var result = OCRDocument(blocks: [])
        for (page, image) in images.enumerated() {
            if #available(iOS 26.0, macOS 26.0, *) {
                do {
                    var request = RecognizeDocumentsRequest()
                    request.textRecognitionOptions.automaticallyDetectLanguage = true
                    request.textRecognitionOptions.useLanguageCorrection = false
                    result.supportedOCRLanguages = request.supportedRecognitionLanguages.map(\.minimalIdentifier).sorted()
                    let observations = try await request.perform(on: image)
                    guard !observations.isEmpty else { throw IntakeError.missing }
                    for (d, observation) in observations.enumerated() {
                        let document = observation.document
                        // Full paragraphs/table ranges survive, even where flattened rows are uncertain.
                        if let json = try? JSONEncoder().encode(document), let string = String(data: json, encoding: .utf8) {
                            result.structureJSON = (result.structureJSON ?? "") + "\n" + string
                        }
                        func append(_ lines: [RecognizedTextObservation], table: String? = nil, row: Int? = nil, column: Int? = nil) {
                            for line in lines {
                                guard let candidate = line.topCandidates(1).first else { continue }
                                let b = line.boundingBox.cgRect
                                result.appendEvidence(OCRBlock(id: "p\(page)-d\(d)-b\(result.blocks.count)", page: page, text: candidate.string, confidence: Double(candidate.confidence), box: OCRBox(x: b.minX, y: b.minY, width: b.width, height: b.height), table: table, row: row, column: column))
                            }
                        }
                        append(document.text.lines)
                        for (t, table) in document.tables.enumerated() {
                            for cells in table.rows {
                                for cell in cells {
                                    // Spanning cells cannot establish a unique nutrient row association.
                                    if cell.rowRange.lowerBound == cell.rowRange.upperBound {
                                        append(cell.content.text.lines, table: "p\(page)-d\(d)-t\(t)", row: cell.rowRange.lowerBound, column: cell.columnRange.lowerBound)
                                    }
                                }
                            }
                        }
                    }
                    result.engine = "Vision.RecognizeDocumentsRequest"
                    continue
                } catch { result.warnings.append("结构化 OCR 不可用，已回退行识别；没有推测表格关联。") }
            }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true; request.usesLanguageCorrection = false
            result.supportedOCRLanguages = try request.supportedRecognitionLanguages()
            try VNImageRequestHandler(cgImage: image).perform([request])
            for observation in request.results ?? [] {
                guard let text = observation.topCandidates(1).first else { continue }
                let b = observation.boundingBox
                result.appendEvidence(OCRBlock(id: "p\(page)-b\(result.blocks.count)", page: page, text: text.string, confidence: Double(text.confidence), box: OCRBox(x: b.minX, y: b.minY, width: b.width, height: b.height)))
            }
            result.engine = "Vision.VNRecognizeTextRequest"
        }
        return result
    }
}
