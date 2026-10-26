import UIKit
import PDFKit
import Vision

/// All document processing happens here, on the device, with Apple frameworks only
/// (PDFKit, Core Graphics, ImageIO, Vision). Nothing in this app talks to a network.
enum Engine {
    typealias Progress = (Double) -> Void

    // MARK: Shared helpers

    private static func pdfFormat() -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Convertory",
            kCGPDFContextTitle as String: "Convertory document"
        ]
        return format
    }

    private static func openPDF(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else {
            throw EngineError.message("Couldn't open \(url.lastPathComponent).")
        }
        if doc.isLocked {
            throw EngineError.message("\(url.lastPathComponent) is password protected.")
        }
        guard doc.pageCount > 0 else {
            throw EngineError.message("\(url.lastPathComponent) has no pages.")
        }
        return doc
    }

    private static func save(_ doc: PDFDocument, prefix: String) throws -> URL {
        let url = LibraryStore.newOutputURL(prefix: prefix, ext: "pdf")
        guard doc.write(to: url) else { throw EngineError.message("Couldn't save the PDF.") }
        return url
    }

    private static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    /// Size in points of a page as it is displayed (page rotation applied).
    private static func displaySize(of page: CGPDFPage, box: CGPDFBox = .cropBox) -> CGSize {
        let rect = page.getBoxRect(box)
        let rotation = page.rotationAngle
        return (rotation == 90 || rotation == 270) ? CGSize(width: rect.height, height: rect.width) : rect.size
    }

    /// Draws a PDF page into a UIKit-oriented (top-left origin) context.
    private static func draw(_ page: CGPDFPage, in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }

    /// Rasterises a page; used for OCR and for compression.
    static func render(_ page: PDFPage, scale: CGFloat) -> UIImage? {
        guard let cgPage = page.pageRef else { return nil }
        let points = displaySize(of: cgPage)
        guard points.width > 0, points.height > 0 else { return nil }
        let capped = min(scale, 3200 / max(points.width, points.height))
        let size = CGSize(width: points.width * capped, height: points.height * capped)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            draw(cgPage, in: renderer.cgContext, bounds: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Photos / scans to PDF

    static func makePDFData(images urls: [URL], layout: PageLayout, searchable: Bool,
                            progress: Progress? = nil) throws -> Data {
        guard !urls.isEmpty else { throw EngineError.message("Add at least one picture.") }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: pdfFormat())
        var unreadable: String?
        let data = renderer.pdfData { context in
            for (index, url) in urls.enumerated() {
                autoreleasepool {
                    guard let image = ImageLoader.load(url, maxPixel: 2600) else {
                        unreadable = url.lastPathComponent
                        return
                    }
                    let page = layout.pageRect(for: image.size)
                    context.beginPage(withBounds: page, pageInfo: [:])
                    let target = layout.imageRect(for: image.size, in: page)
                    image.draw(in: target)
                    if searchable, let cg = image.cgImage,
                       let found = try? OCR.observations(in: cg) {
                        OCR.drawInvisibleText(found, in: target, context: context.cgContext)
                    }
                }
                progress?(Double(index + 1) / Double(urls.count))
            }
        }
        if let name = unreadable { throw EngineError.message("Couldn't read \(name).") }
        return data
    }

    static func imagesToPDF(_ urls: [URL], layout: PageLayout, searchable: Bool,
                            prefix: String, progress: Progress? = nil) throws -> URL {
        let data = try makePDFData(images: urls, layout: layout, searchable: searchable, progress: progress)
        let url = LibraryStore.newOutputURL(prefix: prefix, ext: "pdf")
        try data.write(to: url)
        return url
    }

    // MARK: Merge

    static func merge(_ urls: [URL], progress: Progress? = nil) throws -> URL {
        let output = PDFDocument()
        for (index, url) in urls.enumerated() {
            let source: PDFDocument
            if isPDF(url) {
                source = try openPDF(url)
            } else {
                let data = try makePDFData(images: [url], layout: .a4, searchable: false)
                guard let doc = PDFDocument(data: data) else {
                    throw EngineError.message("Couldn't read \(url.lastPathComponent).")
                }
                source = doc
            }
            for pageIndex in 0..<source.pageCount {
                if let page = source.page(at: pageIndex)?.copy() as? PDFPage {
                    output.insert(page, at: output.pageCount)
                }
            }
            progress?(Double(index + 1) / Double(urls.count))
        }
        return try save(output, prefix: "Merged")
    }

    // MARK: Organize pages

    struct PageEdit: Identifiable, Equatable {
        let id = UUID()
        let sourceIndex: Int
        var rotation: Int = 0
    }

    static func organize(_ url: URL, edits: [PageEdit]) throws -> URL {
        guard !edits.isEmpty else { throw EngineError.message("Keep at least one page.") }
        let source = try openPDF(url)
        let output = PDFDocument()
        for edit in edits {
            guard let page = source.page(at: edit.sourceIndex)?.copy() as? PDFPage else { continue }
            page.rotation = ((page.rotation + edit.rotation) % 360 + 360) % 360
            output.insert(page, at: output.pageCount)
        }
        return try save(output, prefix: "Pages")
    }

    // MARK: Watermark

    static func watermark(_ url: URL, text: String, opacity: Double, style: WatermarkStyle,
                          progress: Progress? = nil) throws -> URL {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw EngineError.message("Type the watermark text first.") }
        let doc = try openPDF(url)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: pdfFormat())
        var failed = false
        let data = renderer.pdfData { context in
            for index in 0..<doc.pageCount {
                autoreleasepool {
                    guard let cgPage = doc.page(at: index)?.pageRef else { failed = true; return }
                    let bounds = CGRect(origin: .zero, size: displaySize(of: cgPage))
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    draw(cgPage, in: context.cgContext, bounds: bounds)
                    drawWatermark(label, opacity: opacity, style: style, bounds: bounds, context: context.cgContext)
                }
                progress?(Double(index + 1) / Double(doc.pageCount))
            }
        }
        if failed { throw EngineError.message("Some pages could not be read.") }
        let out = LibraryStore.newOutputURL(prefix: "Watermarked", ext: "pdf")
        try data.write(to: out)
        return out
    }

    private static func drawWatermark(_ text: String, opacity: Double, style: WatermarkStyle,
                                      bounds: CGRect, context: CGContext) {
        let color = UIColor(white: 0.2, alpha: CGFloat(min(max(opacity, 0.05), 0.9)))
        func attributed(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: color
            ])
        }
        let diagonal = hypot(bounds.width, bounds.height)
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: bounds.midX, y: bounds.midY)

        switch style {
        case .diagonal:
            let probe = attributed(100).size().width
            let fontSize = min(220, max(14, 100 * (diagonal * 0.62) / max(probe, 1)))
            let string = attributed(fontSize)
            let size = string.size()
            context.rotate(by: -.pi / 4)
            string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        case .tiled:
            let fontSize = min(bounds.width, bounds.height) / 16
            let string = attributed(max(10, fontSize))
            let size = string.size()
            context.rotate(by: -.pi / 6)
            var y = -diagonal / 2
            var row = 0
            while y < diagonal / 2 {
                var x = -diagonal / 2 + (row % 2 == 0 ? 0 : size.width)
                while x < diagonal / 2 {
                    string.draw(at: CGPoint(x: x, y: y))
                    x += size.width * 2
                }
                y += size.height * 3
                row += 1
            }
        }
        context.restoreGState()
    }

    // MARK: Compress

    static func compress(_ url: URL, level: CompressLevel, progress: Progress? = nil) throws -> URL {
        let doc = try openPDF(url)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: pdfFormat())
        var failed = false
        let data = renderer.pdfData { context in
            for index in 0..<doc.pageCount {
                autoreleasepool {
                    guard let page = doc.page(at: index), let cgPage = page.pageRef,
                          let image = render(page, scale: level.renderScale),
                          let jpeg = image.jpegData(compressionQuality: level.jpegQuality),
                          let flattened = UIImage(data: jpeg) else {
                        failed = true
                        return
                    }
                    let bounds = CGRect(origin: .zero, size: displaySize(of: cgPage))
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    flattened.draw(in: bounds)
                }
                progress?(Double(index + 1) / Double(doc.pageCount))
            }
        }
        if failed { throw EngineError.message("Some pages could not be compressed.") }
        let out = LibraryStore.newOutputURL(prefix: "Compressed", ext: "pdf")
        try data.write(to: out)
        return out
    }

    // MARK: Text extraction

    /// Plain text of a page; scanned pages without a text layer go through on-device OCR.
    private static func pageText(_ page: PDFPage) -> String {
        let direct = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if direct.count >= 12 { return direct }
        guard let image = render(page, scale: 2.2)?.cgImage,
              let rows = try? OCR.rows(in: image) else { return direct }
        return rows.joined(separator: "\n")
    }

    static func extractText(from url: URL, progress: Progress? = nil) throws -> URL {
        var output = ""
        if isPDF(url) {
            let doc = try openPDF(url)
            var parts: [String] = []
            for index in 0..<doc.pageCount {
                autoreleasepool {
                    if let page = doc.page(at: index) { parts.append(pageText(page)) }
                }
                progress?(Double(index + 1) / Double(doc.pageCount))
            }
            output = parts.joined(separator: "\n\n")
        } else {
            guard let image = ImageLoader.load(url, maxPixel: 3200)?.cgImage else {
                throw EngineError.message("Couldn't read \(url.lastPathComponent).")
            }
            output = try OCR.rows(in: image).joined(separator: "\n")
            progress?(1)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError.message("No text was found in this file.") }
        let out = LibraryStore.newOutputURL(prefix: "Text", ext: "txt")
        try trimmed.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    // MARK: PDF to Word

    private static func lines(of page: PDFPage) -> [DocLine] {
        var result: [DocLine] = []
        if let attributed = page.attributedString, attributed.length > 0 {
            let text = attributed.string as NSString
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                     options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                let line = text.substring(with: range).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { return }
                let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
                result.append(DocLine(text: line,
                                      size: font?.pointSize ?? 11,
                                      bold: font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false))
            }
        }
        if result.reduce(0, { $0 + $1.text.count }) < 12 {
            // scanned page: fall back to OCR
            if let image = render(page, scale: 2.2)?.cgImage, let rows = try? OCR.rows(in: image) {
                result = rows.map { DocLine(text: $0, size: 11, bold: false) }
            }
        }
        return result
    }

    /// Joins wrapped lines back into paragraphs; headings and short lines start new ones.
    private static func paragraphs(from lines: [DocLine]) -> [DocLine] {
        let longest = lines.map { $0.text.count }.max() ?? 0
        var result: [DocLine] = []
        var current: DocLine?
        var previousLength = 0
        for line in lines {
            if var open = current {
                let sameStyle = abs(open.size - line.size) < 0.6 && open.bold == line.bold
                let previousWasShort = Double(previousLength) < 0.6 * Double(longest)
                if sameStyle && !previousWasShort {
                    if open.text.hasSuffix("-"), let first = line.text.first, first.isLowercase {
                        open.text.removeLast()
                        open.text += line.text
                    } else {
                        open.text += " " + line.text
                    }
                    current = open
                } else {
                    result.append(open)
                    current = line
                }
            } else {
                current = line
            }
            previousLength = line.text.count
        }
        if let open = current { result.append(open) }
        return result
    }

    static func pdfToWord(_ url: URL, progress: Progress? = nil) throws -> URL {
        let doc = try openPDF(url)
        var pages: [[DocLine]] = []
        var weight: [Int: Int] = [:]
        for index in 0..<doc.pageCount {
            autoreleasepool {
                guard let page = doc.page(at: index) else { return }
                let pageLines = lines(of: page)
                for line in pageLines { weight[Int(line.size.rounded()), default: 0] += line.text.count }
                pages.append(paragraphs(from: pageLines))
            }
            progress?(Double(index + 1) / Double(doc.pageCount))
        }
        guard pages.contains(where: { !$0.isEmpty }) else {
            throw EngineError.message("No text was found in this PDF.")
        }
        let bodySize = CGFloat(weight.max { $0.value < $1.value }?.key ?? 11)
        let data = DocxWriter.makeDocument(pages: pages, bodySize: bodySize)
        let out = LibraryStore.newOutputURL(prefix: "Word", ext: "docx")
        try data.write(to: out)
        return out
    }
}
