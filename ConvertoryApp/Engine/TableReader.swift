import UIKit
import PDFKit
import Vision

/// A rough table finder: it looks at where words sit on a page, groups them into rows, then guesses
/// the columns from the gaps between them. Works on simple tables; merged cells and nested tables are not understood.
enum TableReader {
    struct Word {
        let text: String
        let box: CGRect   // page points, origin bottom-left (higher midY = higher on the page)
    }

    struct Cell {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var midX: CGFloat { (minX + maxX) / 2 }
        var width: CGFloat { maxX - minX }
    }

    struct Grid {
        var rows: [[String]]
        var tableRows: Int
    }

    // MARK: Words from a page

    static func words(on page: PDFPage) -> [Word] {
        guard let text = page.string, !text.isEmpty else { return [] }
        let ns = text as NSString
        var result: [Word] = []
        var current = ""
        var box = CGRect.null
        var last = CGRect.null

        func flush() {
            if !current.isEmpty, !box.isNull { result.append(Word(text: current, box: box)) }
            current = ""
            box = .null
            last = .null
        }

        var index = 0
        while index < ns.length {
            let range = ns.rangeOfComposedCharacterSequence(at: index)
            index = range.location + max(range.length, 1)
            let piece = ns.substring(with: range)
            if piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flush()
                continue
            }
            let rect = page.characterBounds(at: range.location)
            if rect.height <= 0 || rect.width < 0 || rect.isNull || rect.isInfinite {
                continue
            }
            if !current.isEmpty {
                let sameLine = abs(rect.midY - last.midY) <= max(rect.height, last.height) * 0.5
                let gap = rect.minX - last.maxX
                if !sameLine || gap > rect.height * 0.7 || gap < -rect.height * 2 {
                    flush()
                }
            }
            current += piece
            box = box.isNull ? rect : box.union(rect)
            last = rect
        }
        flush()
        return result
    }

    /// Words for a scanned page, read with on-device text recognition.
    static func words(fromScan page: PDFPage) -> [Word] {
        guard let image = Engine.render(page, scale: 2.2)?.cgImage,
              let found = try? OCR.observations(in: image) else { return [] }
        let size = page.bounds(for: .cropBox).size
        return found.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            let b = observation.boundingBox
            let rect = CGRect(x: b.minX * size.width, y: b.minY * size.height,
                              width: b.width * size.width, height: b.height * size.height)
            return Word(text: text, box: rect)
        }
    }

    // MARK: Words to a grid

    static func grid(for page: PDFPage) -> Grid {
        var words = TableReader.words(on: page)
        if words.count < 3 { words = TableReader.words(fromScan: page) }
        return grid(from: words, pageWidth: max(page.bounds(for: .cropBox).width, 1))
    }

    static func grid(from words: [Word], pageWidth: CGFloat) -> Grid {
        guard !words.isEmpty else { return Grid(rows: [], tableRows: 0) }

        // 1. Words into lines, top to bottom.
        let ordered = words.sorted { $0.box.midY > $1.box.midY }
        var lines: [[Word]] = []
        for word in ordered {
            if let reference = lines.last?.first,
               abs(reference.box.midY - word.box.midY) < max(reference.box.height, word.box.height) * 0.5 {
                lines[lines.count - 1].append(word)
            } else {
                lines.append([word])
            }
        }

        // 2. Each line into cells: a gap wider than about one em starts a new cell.
        let cellLines: [[Cell]] = lines.map { line in
            var cells: [Cell] = []
            for word in line.sorted(by: { $0.box.minX < $1.box.minX }) {
                if var open = cells.last {
                    let gap = word.box.minX - open.maxX
                    if gap > max(word.box.height, 6) * 0.9 {
                        cells.append(Cell(text: word.text, minX: word.box.minX, maxX: word.box.maxX))
                    } else {
                        open.text += " " + word.text
                        open.maxX = max(open.maxX, word.box.maxX)
                        cells[cells.count - 1] = open
                    }
                } else {
                    cells.append(Cell(text: word.text, minX: word.box.minX, maxX: word.box.maxX))
                }
            }
            return cells
        }

        // 3. Column bands from the lines that have two or more cells.
        let tableIndexes = cellLines.indices.filter { cellLines[$0].count >= 2 }
        guard let firstTable = tableIndexes.first, let lastTable = tableIndexes.last else {
            return Grid(rows: cellLines.map { [$0.map(\.text).joined(separator: " ")] }, tableRows: 0)
        }

        let wide = pageWidth * 0.45
        var spans: [(lo: CGFloat, hi: CGFloat)] = []
        for index in tableIndexes {
            for cell in cellLines[index] where cell.width <= wide {
                spans.append((cell.minX, cell.maxX))
            }
        }
        if spans.isEmpty {
            for index in tableIndexes {
                for cell in cellLines[index] { spans.append((cell.minX, cell.maxX)) }
            }
        }
        spans.sort { $0.lo < $1.lo }
        var bands: [(lo: CGFloat, hi: CGFloat)] = []
        for span in spans {
            if let last = bands.last, span.lo <= last.hi {
                bands[bands.count - 1] = (last.lo, max(last.hi, span.hi))
            } else {
                bands.append(span)
            }
        }

        func band(for cell: Cell) -> Int {
            let probe = cell.width > wide ? cell.minX : cell.midX
            if let hit = bands.firstIndex(where: { probe >= $0.lo && probe <= $0.hi }) { return hit }
            var best = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (offset, candidate) in bands.enumerated() {
                let distance = abs(probe - (candidate.lo + candidate.hi) / 2)
                if distance < bestDistance {
                    bestDistance = distance
                    best = offset
                }
            }
            return best
        }

        // 4. Place the cells. Single-cell lines inside the table are kept in their column;
        //    titles and footers outside it stay in the first column.
        var rows: [[String]] = []
        for (index, cells) in cellLines.enumerated() {
            var row = [String](repeating: "", count: max(bands.count, 1))
            let insideTable = index >= firstTable && index <= lastTable
            if cells.count >= 2 || insideTable {
                for cell in cells {
                    let column = band(for: cell)
                    row[column] = row[column].isEmpty ? cell.text : row[column] + " " + cell.text
                }
            } else {
                row[0] = cells.map(\.text).joined(separator: " ")
            }
            while let tail = row.last, tail.isEmpty, row.count > 1 { row.removeLast() }
            rows.append(row)
        }
        return Grid(rows: rows, tableRows: tableIndexes.count)
    }
}
