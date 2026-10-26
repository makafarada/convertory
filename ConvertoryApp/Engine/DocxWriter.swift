import Foundation
import UIKit

// MARK: - Minimal ZIP container (stored entries), enough for an Office Open XML package

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

struct ZipWriter {
    private var body = Data()
    private var directory = Data()
    private var entries: UInt16 = 0

    // 2026-01-01 00:00 in MS-DOS format
    private let dosTime: UInt16 = 0
    private let dosDate: UInt16 = UInt16((2026 - 1980) << 9 | 1 << 5 | 1)

    mutating func add(name: String, data: Data) {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(data)
        let offset = UInt32(body.count)
        let size = UInt32(data.count)

        body.appendLE(UInt32(0x0403_4B50))
        body.appendLE(UInt16(20))
        body.appendLE(UInt16(0x0800))
        body.appendLE(UInt16(0))
        body.appendLE(dosTime)
        body.appendLE(dosDate)
        body.appendLE(crc)
        body.appendLE(size)
        body.appendLE(size)
        body.appendLE(UInt16(nameBytes.count))
        body.appendLE(UInt16(0))
        body.append(nameBytes)
        body.append(data)

        directory.appendLE(UInt32(0x0201_4B50))
        directory.appendLE(UInt16(20))
        directory.appendLE(UInt16(20))
        directory.appendLE(UInt16(0x0800))
        directory.appendLE(UInt16(0))
        directory.appendLE(dosTime)
        directory.appendLE(dosDate)
        directory.appendLE(crc)
        directory.appendLE(size)
        directory.appendLE(size)
        directory.appendLE(UInt16(nameBytes.count))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt32(0))
        directory.appendLE(offset)
        directory.append(nameBytes)
        entries += 1
    }

    func finish() -> Data {
        var out = body
        let directoryOffset = UInt32(body.count)
        out.append(directory)
        out.appendLE(UInt32(0x0605_4B50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(entries)
        out.appendLE(entries)
        out.appendLE(UInt32(directory.count))
        out.appendLE(directoryOffset)
        out.appendLE(UInt16(0))
        return out
    }
}

// MARK: - Word document

/// One visual line of text taken from a PDF page.
struct DocLine {
    var text: String
    var size: CGFloat
    var bold: Bool
}

enum DocxWriter {
    /// `pages` holds already merged paragraphs per source page; a page break separates them.
    static func makeDocument(pages: [[DocLine]], bodySize: CGFloat) -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        """
        for (index, page) in pages.enumerated() {
            for paragraph in page {
                xml += paragraphXML(paragraph, bodySize: bodySize)
            }
            if index < pages.count - 1 {
                xml += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            }
        }
        xml += """
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """

        var zip = ZipWriter()
        zip.add(name: "[Content_Types].xml", data: Data(contentTypes.utf8))
        zip.add(name: "_rels/.rels", data: Data(rels.utf8))
        zip.add(name: "word/document.xml", data: Data(xml.utf8))
        return zip.finish()
    }

    private static func paragraphXML(_ line: DocLine, bodySize: CGFloat) -> String {
        let isHeading = line.size >= bodySize * 1.15
        let halfPoints = Int(min(72, max(18, (line.size * 2).rounded())))
        var props = ""
        if line.bold || isHeading { props += "<w:b/>" }
        props += "<w:sz w:val=\"\(halfPoints)\"/>"
        let spacing = isHeading ? "<w:pPr><w:keepNext/><w:spacing w:before=\"240\" w:after=\"120\"/></w:pPr>"
                                : "<w:pPr><w:spacing w:after=\"120\"/></w:pPr>"
        return "<w:p>\(spacing)<w:r><w:rPr>\(props)</w:rPr><w:t xml:space=\"preserve\">\(escape(line.text))</w:t></w:r></w:p>"
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                let v = scalar.value
                // XML 1.0 forbids most control characters
                if v == 0x9 || v == 0xA || v == 0xD || v >= 0x20 && v != 0xFFFE && v != 0xFFFF {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
