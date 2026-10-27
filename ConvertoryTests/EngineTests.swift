import XCTest
import PDFKit
import UIKit
@testable import Convertory

final class EngineTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: Fixtures

    private func makePDF(pages: [String]) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24),
                    .foregroundColor: UIColor.black
                ])
            }
        }
        let url = scratch.appendingPathComponent("\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }

    private func makeTextImage(_ text: String) throws -> URL {
        let size = CGSize(width: 1200, height: 500)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            (text as NSString).draw(at: CGPoint(x: 60, y: 150), withAttributes: [
                .font: UIFont.systemFont(ofSize: 90, weight: .semibold),
                .foregroundColor: UIColor.black
            ])
        }
        let url = scratch.appendingPathComponent("\(UUID().uuidString).jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.95)).write(to: url)
        return url
    }

    private func fileSize(_ url: URL) throws -> Int {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    // MARK: Tests

    func testMergeKeepsAllPagesInOrder() throws {
        let a = try makePDF(pages: ["Alpha one", "Alpha two"])
        let b = try makePDF(pages: ["Bravo one"])
        let out = try Engine.merge([a, b])
        defer { try? FileManager.default.removeItem(at: out) }
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 3)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("Alpha one") ?? false)
        XCTAssertTrue(doc.page(at: 2)?.string?.contains("Bravo one") ?? false)
    }

    func testMergeAcceptsPictures() throws {
        let pdf = try makePDF(pages: ["Doc"])
        let picture = try makeTextImage("Picture")
        let out = try Engine.merge([pdf, picture])
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(PDFDocument(url: out)?.pageCount, 2)
    }

    func testOrganizeReordersRotatesAndDrops() throws {
        let src = try makePDF(pages: ["First", "Second", "Third"])
        var edits = [Engine.PageEdit(sourceIndex: 2), Engine.PageEdit(sourceIndex: 0)]
        edits[0].rotation = 90
        let out = try Engine.organize(src, edits: edits)
        defer { try? FileManager.default.removeItem(at: out) }
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("Third") ?? false)
        XCTAssertEqual(doc.page(at: 0)?.rotation, 90)
        XCTAssertTrue(doc.page(at: 1)?.string?.contains("First") ?? false)
    }

    func testOrganizeRefusesEmptySelection() throws {
        let src = try makePDF(pages: ["Only"])
        XCTAssertThrowsError(try Engine.organize(src, edits: []))
    }

    func testWatermarkAddsTextAndKeepsPages() throws {
        let src = try makePDF(pages: ["Body one", "Body two"])
        let out = try Engine.watermark(src, text: "DRAFT", opacity: 0.3, style: .diagonal)
        defer { try? FileManager.default.removeItem(at: out) }
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("DRAFT") ?? false)
        XCTAssertTrue(doc.page(at: 1)?.string?.contains("Body two") ?? false)
    }

    func testWatermarkRequiresText() throws {
        let src = try makePDF(pages: ["x"])
        XCTAssertThrowsError(try Engine.watermark(src, text: "   ", opacity: 0.3, style: .tiled))
    }

    func testCompressShrinksPhotoPDF() throws {
        // A PDF made of one big, noisy picture: re-rendering at a lower scale must make it smaller.
        let size = CGSize(width: 2400, height: 3200)
        let noisy = UIGraphicsImageRenderer(size: size).image { ctx in
            for i in 0..<3000 {
                UIColor(hue: CGFloat((i * 7) % 100) / 100, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: (i * 37) % 2300, y: (i * 53) % 3100, width: 90, height: 70))
            }
        }
        let imageURL = scratch.appendingPathComponent("noisy.png")
        try XCTUnwrap(noisy.pngData()).write(to: imageURL)
        let pdf = try Engine.imagesToPDF([imageURL], layout: .a4, searchable: false, prefix: "Fixture")
        defer { try? FileManager.default.removeItem(at: pdf) }
        let out = try Engine.compress(pdf, level: .smallest)
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(PDFDocument(url: out)?.pageCount, 1)
        XCTAssertLessThan(try fileSize(out), try fileSize(pdf))
    }

    func testImagesToPDFMakesSearchableText() throws {
        let image = try makeTextImage("Invoice 2026")
        let out = try Engine.imagesToPDF([image], layout: .a4, searchable: true, prefix: "Test")
        defer { try? FileManager.default.removeItem(at: out) }
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 1)
        let text = (doc.string ?? "").lowercased()
        XCTAssertTrue(text.contains("invoice"), "OCR layer missing, got: \(text)")
    }

    func testImagesToPDFWithoutOCRHasNoTextLayer() throws {
        let image = try makeTextImage("Invoice 2026")
        let out = try Engine.imagesToPDF([image], layout: .letter, searchable: false, prefix: "Test")
        defer { try? FileManager.default.removeItem(at: out) }
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 1)
        XCTAssertTrue((doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testExtractTextFromTextPDF() throws {
        let src = try makePDF(pages: ["Hello Convertory world"])
        let out = try Engine.extractText(from: src)
        defer { try? FileManager.default.removeItem(at: out) }
        let text = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(text.contains("Hello Convertory"))
    }

    func testExtractTextFromPictureUsesOCR() throws {
        let image = try makeTextImage("Meeting notes")
        let out = try Engine.extractText(from: image)
        defer { try? FileManager.default.removeItem(at: out) }
        let text = try String(contentsOf: out, encoding: .utf8).lowercased()
        XCTAssertTrue(text.contains("meeting"), "got: \(text)")
    }

    func testPDFToWordProducesValidDocx() throws {
        let src = try makePDF(pages: ["Quarterly report body text that is long enough to count as real text."])
        let out = try Engine.pdfToWord(src)
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(out.pathExtension, "docx")
        let data = try Data(contentsOf: out)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "not a zip")
        let blob = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(blob.contains("word/document.xml"))
        XCTAssertTrue(blob.contains("[Content_Types].xml"))
        XCTAssertTrue(blob.contains("Quarterly report"))
    }

    // MARK: Office conversions

    private func makeTablePDF() throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let rows: [[String]] = [
            ["Item", "Qty", "Price"],
            ["Apples", "12", "3.50"],
            ["Pears", "7", "1,200.00"],
            ["Plums", "30", "0.75"]
        ]
        let columns: [CGFloat] = [60, 260, 400]
        let data = renderer.pdfData { context in
            context.beginPage()
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, cell) in row.enumerated() {
                    (cell as NSString).draw(
                        at: CGPoint(x: columns[columnIndex], y: 100 + CGFloat(rowIndex) * 30),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.black])
                }
            }
        }
        let url = scratch.appendingPathComponent("\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }

    func testWordToPDFReadsDeflatedDocx() throws {
        let data = try XCTUnwrap(Data(base64Encoded: Self.sampleDocxBase64))
        let src = scratch.appendingPathComponent("sample.docx")
        try data.write(to: src)
        let out = try Engine.wordToPDF(src)
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(out.pathExtension, "pdf")
        let doc = try XCTUnwrap(PDFDocument(url: out))
        let text = doc.string ?? ""
        XCTAssertTrue(text.contains("Budget Overview"), "got: \(text)")
        XCTAssertTrue(text.contains("compressed with deflate"), "got: \(text)")
        XCTAssertTrue(text.contains("Laptop"), "got: \(text)")
    }

    func testWordToPDFRoundTripFromPDFToWord() throws {
        let src = try makePDF(pages: ["Round trip sentence for the converter."])
        let docx = try Engine.pdfToWord(src)
        defer { try? FileManager.default.removeItem(at: docx) }
        let out = try Engine.wordToPDF(docx)
        defer { try? FileManager.default.removeItem(at: out) }
        let text = PDFDocument(url: out)?.string ?? ""
        XCTAssertTrue(text.contains("Round trip"), "got: \(text)")
    }

    func testWordToPDFRejectsOtherFiles() throws {
        let src = try makePDF(pages: ["Not a Word file"])
        XCTAssertThrowsError(try Engine.wordToPDF(src))
    }

    func testPDFToPowerPointMakesOneSlidePerPage() throws {
        let src = try makePDF(pages: ["First page", "Second page"])
        let out = try Engine.pdfToPowerPoint(src)
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(out.pathExtension, "pptx")
        let zip = try XCTUnwrap(ZipReader(url: out))
        XCTAssertTrue(zip.contains("ppt/slides/slide1.xml"))
        XCTAssertTrue(zip.contains("ppt/slides/slide2.xml"))
        XCTAssertFalse(zip.contains("ppt/slides/slide3.xml"))
        let image = try XCTUnwrap(zip.read("ppt/media/image1.jpeg"))
        XCTAssertEqual(Array(image.prefix(2)), [0xFF, 0xD8], "not a JPEG")
    }

    func testPDFToExcelFindsColumns() throws {
        let src = try makeTablePDF()
        let out = try Engine.pdfToExcel(src)
        defer { try? FileManager.default.removeItem(at: out) }
        XCTAssertEqual(out.pathExtension, "xlsx")
        let zip = try XCTUnwrap(ZipReader(url: out))
        let sheet = String(decoding: try XCTUnwrap(zip.read("xl/worksheets/sheet1.xml")), as: UTF8.self)
        XCTAssertTrue(sheet.contains("r=\"A1\""), "got: \(sheet)")
        XCTAssertTrue(sheet.contains("r=\"C1\""), "got: \(sheet)")
        XCTAssertTrue(sheet.contains("<v>12</v>"), "got: \(sheet)")
        XCTAssertTrue(sheet.contains("<v>1200.00</v>"), "got: \(sheet)")
        XCTAssertTrue(sheet.contains("Apples"), "got: \(sheet)")
    }

    func testPDFToExcelRefusesPlainProse() throws {
        let src = try makePDF(pages: ["Just one line of ordinary prose."])
        XCTAssertThrowsError(try Engine.pdfToExcel(src))
    }

    func testXlsxHelpers() {
        XCTAssertEqual(XlsxWriter.columnName(0), "A")
        XCTAssertEqual(XlsxWriter.columnName(25), "Z")
        XCTAssertEqual(XlsxWriter.columnName(26), "AA")
        XCTAssertEqual(XlsxWriter.number(from: "42"), "42")
        XCTAssertEqual(XlsxWriter.number(from: "-3.5"), "-3.5")
        XCTAssertEqual(XlsxWriter.number(from: "1,234.50"), "1234.50")
        XCTAssertNil(XlsxWriter.number(from: "007"))
        XCTAssertNil(XlsxWriter.number(from: "$5"))
        XCTAssertNil(XlsxWriter.number(from: "12,34"))
    }

    private static let sampleDocxBase64 = [
        "UEsDBBQAAAAIAGZEW11AE3eN3gAAAJwBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbH1QS07DMBC9iuUtiid0gRBK0gWUJbAoB7Ds",
        "SWLhnzxuKbdn0pYuUNXlzPvqdetD8GKPhVyKvbxXrRQYTbIuTr383L42j3I9dNufjCSYGqmXc635CYDMjEGTShkjI2MqQVc+ywRZ",
        "my89Iaza9gFMihVjberiIYfuBUe981VsDvw+xbJciucTb4nqpc7ZO6Mrw7CgcFVX0NMN4T7af+2aczPFyiOHZpfp7pzwzjsUZ1F8",
        "6FLfdGA7+E7Fgk1mFzhC3S56JS+NozN40S9uuSSDRDxw8OqCBO3iXw84zj38AlBLAwQUAAAACABmRFtdNlfe3KIAAAAYAQAACwAA",
        "AF9yZWxzLy5yZWxzjc87DsIwDAbgq0TeqQsDQqhpF4TUFZUDRImbRjQPJeF1ezIwUMTAaPv3Z7npHnZmN4rJeMdhXdXAyEmvjNMc",
        "zsNxtYOubU40i1wSaTIhsbLiEocp57BHTHIiK1LlA7kyGX20IpcyagxCXoQm3NT1FuOnAUuT9YpD7NUa2PAM9I/tx9FIOnh5teTy",
        "jxNfiSKLqClzuPuoUL3bVWEB2wYXL7YvUEsDBBQAAAAIAGZEW12dX5BWGQEAAFYCAAARAAAAd29yZC9kb2N1bWVudC54bWyVUl1L",
        "AzEQ/CtL3m1aH0SO3hUUREFQsOLz9rK9C+SLZNvYf2/u+iFoi/iyQ9jZmR0288WnNbClmLR3tZhNpgLItV5p19XifflwdSsgMTqF",
        "xjuqxY6SWDTzXCnfbiw5hiLgUpVr0TOHSsrU9mQxTXwgV3prHy1yecZOZh9ViL6llIq+NfJ6Or2RFrUTg+TKq92AYSyvcYQ33hmC",
        "XG3R1OKRcNhsJmQzlyfOWLi526iOGF5Kmq2mPBB4pMU9+SR94C97nSBgxC5i6CFjghw1MznQDj7KrlByQ+ttiGVjUpA196BobZBp",
        "clafV2aEvUX70/KJyZ6Zk0fu74l7n/jyhDxZXTB8xsA+/M9yVq7yp6U8ZJXHs8nvL9F8AVBLAQIUABQAAAAIAGZEW11AE3eN3gAA",
        "AJwBAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQAFAAAAAgAZkRbXTZX3tyiAAAAGAEAAAsAAAAA",
        "AAAAAAAAAIABDwEAAF9yZWxzLy5yZWxzUEsBAhQAFAAAAAgAZkRbXZ1fkFYZAQAAVgIAABEAAAAAAAAAAAAAAIAB2gEAAHdvcmQv",
        "ZG9jdW1lbnQueG1sUEsFBgAAAAADAAMAuQAAACIDAAAAAA=="
    ].joined()

    func testCRC32KnownValue() {
        // CRC-32 of "123456789" is 0xCBF43926
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testPageLayoutRects() {
        let a4 = PageLayout.a4.pageRect(for: CGSize(width: 100, height: 100))
        XCTAssertEqual(a4.size, CGSize(width: 595, height: 842))
        let fit = PageLayout.fit.pageRect(for: CGSize(width: 300, height: 200))
        XCTAssertEqual(fit.width / fit.height, 1.5, accuracy: 0.01)
    }
}
