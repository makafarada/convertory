import UIKit
import Vision

/// On-device text recognition built on Apple's Vision framework.
enum OCR {
    static func observations(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    /// Recognised text grouped into reading-order rows (cells of one table row stay on one line).
    static func rows(in image: CGImage) throws -> [String] {
        rows(from: try observations(in: image))
    }

    static func rows(from observations: [VNRecognizedTextObservation]) -> [String] {
        let pieces: [(text: String, box: CGRect)] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return (text, observation.boundingBox)
        }
        // Vision's origin is bottom-left, so larger midY means higher on the page.
        let ordered = pieces.sorted { $0.box.midY > $1.box.midY }
        var grouped: [[(text: String, box: CGRect)]] = []
        for piece in ordered {
            if let reference = grouped.last?.first,
               abs(reference.box.midY - piece.box.midY) < max(reference.box.height, piece.box.height) * 0.5 {
                grouped[grouped.count - 1].append(piece)
            } else {
                grouped.append([piece])
            }
        }
        return grouped.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ")
        }
    }

    /// Draws the recognised words invisibly over a scanned page so the PDF becomes searchable and selectable.
    static func drawInvisibleText(_ observations: [VNRecognizedTextObservation], in rect: CGRect, context: CGContext) {
        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { continue }
            let b = observation.boundingBox
            let box = CGRect(x: rect.minX + b.minX * rect.width,
                             y: rect.minY + (1 - b.maxY) * rect.height,
                             width: b.width * rect.width,
                             height: b.height * rect.height)
            let font = UIFont.systemFont(ofSize: max(4, box.height * 0.85))
            let string = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: UIColor.clear
            ])
            let width = string.size().width
            guard width > 0 else { continue }
            context.saveGState()
            context.translateBy(x: box.minX, y: box.minY)
            context.scaleBy(x: box.width / width, y: 1)
            string.draw(at: .zero)
            context.restoreGState()
        }
    }
}
