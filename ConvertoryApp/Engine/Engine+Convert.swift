import UIKit
import PDFKit

/// Conversions between PDF and Office formats. All of it runs on the device.
extension Engine {
    // MARK: Word to PDF

    static func wordToPDF(_ url: URL, progress: Progress? = nil) throws -> URL {
        guard url.pathExtension.lowercased() == "docx" else {
            throw EngineError.message("Only Word files saved as .docx can be converted. Older .doc files aren't supported.")
        }
        guard let zip = ZipReader(url: url), let xml = zip.read("word/document.xml") else {
            throw EngineError.message("\(url.lastPathComponent) couldn't be read as a Word document.")
        }
        progress?(0.25)
        let blocks = try WordDocument.blocks(from: xml)
        let hasText = blocks.contains { !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasText else { throw EngineError.message("No text was found in this Word file.") }
        progress?(0.5)
        let data = WordDocument.render(blocks)
        let out = LibraryStore.newOutputURL(prefix: "Document", ext: "pdf")
        try data.write(to: out)
        progress?(1)
        return out
    }

    // MARK: PDF to PowerPoint

    static func pdfToPowerPoint(_ url: URL, progress: Progress? = nil) throws -> URL {
        let doc = try openPDF(url)
        var slides: [PptxWriter.Slide] = []
        for index in 0..<doc.pageCount {
            var failed = false
            autoreleasepool {
                guard let page = doc.page(at: index) else { failed = true; return }
                let points = page.bounds(for: .cropBox).size
                let longest = max(points.width, points.height, 1)
                let scale = min(2.0, 1800 / longest)
                guard let image = render(page, scale: scale),
                      let jpeg = image.jpegData(compressionQuality: 0.82) else {
                    failed = true
                    return
                }
                slides.append(PptxWriter.Slide(jpeg: jpeg, size: image.size))
            }
            if failed { throw EngineError.message("Page \(index + 1) couldn't be read.") }
            progress?(Double(index + 1) / Double(doc.pageCount))
        }
        let data = PptxWriter.makePresentation(slides: slides)
        let out = LibraryStore.newOutputURL(prefix: "Slides", ext: "pptx")
        try data.write(to: out)
        return out
    }

    // MARK: PDF to Excel

    static func pdfToExcel(_ url: URL, progress: Progress? = nil) throws -> URL {
        let doc = try openPDF(url)
        var sheets: [XlsxWriter.Sheet] = []
        var tableRows = 0
        for index in 0..<doc.pageCount {
            autoreleasepool {
                if let page = doc.page(at: index) {
                    let grid = TableReader.grid(for: page)
                    tableRows += grid.tableRows
                    if !grid.rows.isEmpty {
                        sheets.append(XlsxWriter.Sheet(name: "Page \(index + 1)", rows: grid.rows))
                    }
                }
            }
            progress?(Double(index + 1) / Double(doc.pageCount))
        }
        guard !sheets.isEmpty else { throw EngineError.message("No text was found in this PDF.") }
        guard tableRows >= 2 else {
            throw EngineError.message("No table was found in this PDF. Try Extract text or PDF to Word instead.")
        }
        let data = XlsxWriter.makeWorkbook(sheets: sheets)
        let out = LibraryStore.newOutputURL(prefix: "Spreadsheet", ext: "xlsx")
        try data.write(to: out)
        return out
    }
}
