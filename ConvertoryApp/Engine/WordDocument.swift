import UIKit

struct WordRun {
    var text: String
    var bold: Bool
    var italic: Bool
}

/// One paragraph (or one table row) of a Word document.
struct WordBlock {
    var runs: [WordRun]
    var size: CGFloat = 11
    var forceBold = false
    var isList = false
    var isTableRow = false
    var breakAfter = false

    var plainText: String { runs.map { $0.text }.joined() }
}

/// Reads the visible text of a .docx (paragraphs, headings, bold/italic, lists, simple tables)
/// and lays it out as a plain PDF. Pictures, fonts and page layout are not reproduced.
enum WordDocument {
    static func blocks(from xml: Data) throws -> [WordBlock] {
        let parser = XMLParser(data: xml)
        let reader = DocxParser()
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw EngineError.message("This Word file is damaged and couldn't be read.")
        }
        return reader.blocks
    }

    // MARK: Layout

    private static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        var result = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic {
            var traits: UIFontDescriptor.SymbolicTraits = [.traitItalic]
            if bold { traits.insert(.traitBold) }
            if let descriptor = result.fontDescriptor.withSymbolicTraits(traits) {
                result = UIFont(descriptor: descriptor, size: size)
            }
        }
        return result
    }

    private static func attributed(_ block: WordBlock) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        if block.isList {
            style.firstLineHeadIndent = 0
            style.headIndent = 16
        }
        let size: CGFloat = block.isTableRow ? 10 : block.size
        let output = NSMutableAttributedString()
        let attributes: (Bool, Bool) -> [NSAttributedString.Key: Any] = { bold, italic in
            return [
                .font: font(size: size, bold: bold || block.forceBold, italic: italic),
                .foregroundColor: UIColor.black,
                .paragraphStyle: style
            ]
        }
        if block.isList {
            output.append(NSAttributedString(string: "•  ", attributes: attributes(false, false)))
        }
        for run in block.runs {
            output.append(NSAttributedString(string: run.text, attributes: attributes(run.bold, run.italic)))
        }
        return output
    }

    static func render(_ blocks: [WordBlock]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 56
        let width = page.width - margin * 2
        let bottom = page.height - margin

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Convertory",
            kCGPDFContextTitle as String: "Convertory document"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let drawOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            for block in blocks {
                let isBlank = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isBlank {
                    y += 7
                    if y > bottom { context.beginPage(); y = margin }
                    if block.breakAfter { context.beginPage(); y = margin }
                    continue
                }

                let spacing: CGFloat = block.size > 12 ? 10 : 7
                if block.size > 12, y > margin { y += 4 }
                var queue: [NSAttributedString] = [attributed(block)]
                while !queue.isEmpty {
                    let piece = queue.removeFirst()
                    let measured = piece.boundingRect(with: CGSize(width: width, height: .greatestFiniteHeight),
                                                      options: drawOptions, context: nil)
                    let height = ceil(measured.height)

                    if height > bottom - margin, piece.length > 1 {
                        // Taller than a whole page: halve it at a word boundary and lay out each half.
                        let text = piece.string as NSString
                        var middle = text.length / 2
                        let rest = NSRange(location: middle, length: text.length - middle)
                        let space = text.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: rest)
                        if space.location != NSNotFound { middle = space.location + 1 }
                        if middle >= text.length || middle <= 0 { middle = text.length / 2 }
                        let first = piece.attributedSubstring(from: NSRange(location: 0, length: middle))
                        let second = piece.attributedSubstring(from: NSRange(location: middle, length: text.length - middle))
                        queue.insert(contentsOf: [first, second], at: 0)
                        continue
                    }

                    if y + height > bottom {
                        context.beginPage()
                        y = margin
                    }
                    piece.draw(with: CGRect(x: margin, y: y, width: width, height: height + 2),
                               options: drawOptions, context: nil)
                    y += height + spacing
                }
                if block.breakAfter {
                    context.beginPage()
                    y = margin
                }
            }
        }
    }
}

// MARK: - document.xml parser

private final class DocxParser: NSObject, XMLParserDelegate {
    private(set) var blocks: [WordBlock] = []

    private var runs: [WordRun] = []
    private var styleName = ""
    private var isList = false
    private var breakAfter = false
    private var inParagraph = false
    private var inRun = false
    private var inText = false
    private var runBold = false
    private var runItalic = false
    private var runText = ""
    private var tableDepth = 0
    private var cellText = ""
    private var rowCells: [String] = []
    private var fallbackDepth = 0

    private static func isOn(_ value: String?) -> Bool {
        guard let value = value else { return true }
        return value != "0" && value != "false" && value != "off"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "mc:Fallback" {
            fallbackDepth += 1
            return
        }
        if fallbackDepth > 0 { return }
        switch elementName {
        case "w:tbl":
            tableDepth += 1
        case "w:tr":
            if tableDepth == 1 { rowCells = [] }
        case "w:tc":
            if tableDepth == 1 { cellText = "" }
        case "w:p":
            inParagraph = true
            runs = []
            styleName = ""
            isList = false
            breakAfter = false
        case "w:pStyle":
            if inParagraph { styleName = attributeDict["w:val"] ?? "" }
        case "w:numPr":
            if inParagraph { isList = true }
        case "w:r":
            inRun = true
            runBold = false
            runItalic = false
            runText = ""
        case "w:b":
            if inRun { runBold = DocxParser.isOn(attributeDict["w:val"]) }
        case "w:i":
            if inRun { runItalic = DocxParser.isOn(attributeDict["w:val"]) }
        case "w:t":
            if inRun { inText = true }
        case "w:tab":
            if inRun { runText += "\t" }
        case "w:br", "w:cr":
            if inRun {
                if attributeDict["w:type"] == "page" {
                    breakAfter = true
                } else {
                    runText += "\n"
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText && fallbackDepth == 0 { runText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "mc:Fallback" {
            fallbackDepth = max(0, fallbackDepth - 1)
            return
        }
        if fallbackDepth > 0 { return }
        switch elementName {
        case "w:t":
            inText = false
        case "w:r":
            if inRun {
                if !runText.isEmpty { runs.append(WordRun(text: runText, bold: runBold, italic: runItalic)) }
                inRun = false
            }
        case "w:p":
            finishParagraph()
        case "w:tc":
            if tableDepth == 1 {
                rowCells.append(cellText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        case "w:tr":
            if tableDepth == 1 { finishRow() }
        case "w:tbl":
            tableDepth = max(0, tableDepth - 1)
        default:
            break
        }
    }

    private func finishParagraph() {
        inParagraph = false
        inRun = false
        inText = false
        let text = runs.map { $0.text }.joined()

        if tableDepth > 0 {
            // Text inside a table cell is collected into one line per cell.
            let flat = text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !flat.isEmpty { cellText += (cellText.isEmpty ? "" : " ") + flat }
            return
        }

        var block = WordBlock(runs: runs)
        let lower = styleName.lowercased()
        if lower == "title" {
            block.size = 26
            block.forceBold = true
        } else if lower == "subtitle" {
            block.size = 15
        } else if lower.hasPrefix("heading"), let level = Int(lower.dropFirst(7)) {
            block.size = level == 1 ? 20 : (level == 2 ? 16 : (level == 3 ? 14 : 12))
            block.forceBold = true
        } else {
            block.isList = isList
        }
        block.breakAfter = breakAfter
        blocks.append(block)
    }

    private func finishRow() {
        let hasText = rowCells.contains { !$0.isEmpty }
        if hasText {
            let line = rowCells.joined(separator: "   |   ")
            var block = WordBlock(runs: [WordRun(text: line, bold: false, italic: false)])
            block.isTableRow = true
            blocks.append(block)
        }
        rowCells = []
    }
}
