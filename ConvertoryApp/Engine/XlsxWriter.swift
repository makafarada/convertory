import Foundation

/// Writes a minimal .xlsx (one worksheet per entry) on the stored-entry ZipWriter.
enum XlsxWriter {
    struct Sheet {
        let name: String
        let rows: [[String]]
    }

    private static let nsMain = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

    static func makeWorkbook(sheets input: [Sheet]) -> Data {
        let sheets = input.isEmpty ? [Sheet(name: "Sheet1", rows: [])] : input
        var zip = ZipWriter()
        zip.add(name: "[Content_Types].xml", data: utf8(contentTypes(count: sheets.count)))
        zip.add(name: "_rels/.rels", data: utf8(
            OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">" +
            "<Relationship Id=\"rId1\" Type=\"\(OOXML.officeRel)/officeDocument\" Target=\"xl/workbook.xml\"/>" +
            "</Relationships>"))
        zip.add(name: "xl/workbook.xml", data: utf8(workbook(sheets)))
        zip.add(name: "xl/_rels/workbook.xml.rels", data: utf8(workbookRels(count: sheets.count)))
        zip.add(name: "xl/styles.xml", data: utf8(styles))
        for (offset, sheet) in sheets.enumerated() {
            zip.add(name: "xl/worksheets/sheet\(offset + 1).xml", data: utf8(worksheet(sheet.rows)))
        }
        return zip.finish()
    }

    private static func utf8(_ text: String) -> Data { Data(text.utf8) }

    private static func contentTypes(count: Int) -> String {
        var xml = OOXML.header +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>" +
            "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for number in 1...count {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(number).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        return xml + "</Types>"
    }

    private static func workbook(_ sheets: [Sheet]) -> String {
        var list = ""
        for (offset, sheet) in sheets.enumerated() {
            let name = OOXML.escape(safeName(sheet.name, fallback: "Sheet\(offset + 1)"))
            list += "<sheet name=\"\(name)\" sheetId=\"\(offset + 1)\" r:id=\"rId\(offset + 1)\"/>"
        }
        return OOXML.header +
            "<workbook xmlns=\"\(nsMain)\" xmlns:r=\"\(OOXML.officeRel)\"><sheets>\(list)</sheets></workbook>"
    }

    private static func workbookRels(count: Int) -> String {
        var xml = OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">"
        for number in 1...count {
            xml += "<Relationship Id=\"rId\(number)\" Type=\"\(OOXML.officeRel)/worksheet\" Target=\"worksheets/sheet\(number).xml\"/>"
        }
        xml += "<Relationship Id=\"rId\(count + 1)\" Type=\"\(OOXML.officeRel)/styles\" Target=\"styles.xml\"/>"
        return xml + "</Relationships>"
    }

    private static var styles: String {
        OOXML.header +
        "<styleSheet xmlns=\"\(nsMain)\">" +
        "<fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>" +
        "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>" +
        "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>" +
        "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>" +
        "<cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs>" +
        "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>" +
        "</styleSheet>"
    }

    /// Sheet names: at most 31 characters and none of  \ / ? * [ ] :
    private static func safeName(_ name: String, fallback: String) -> String {
        let blocked = CharacterSet(charactersIn: "\\/?*[]:")
        let cleaned = String(name.unicodeScalars.filter { !blocked.contains($0) }.prefix(31).map { Character($0) })
        return cleaned.isEmpty ? fallback : cleaned
    }

    // MARK: Worksheet

    static func columnName(_ index: Int) -> String {
        var number = index + 1
        var name = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            name = String(Character(UnicodeScalar(UInt8(65 + remainder)))) + name
            number = (number - 1) / 26
        }
        return name
    }

    /// A plain number such as 42, -3.5 or 1,234.50 (no leading zeros, no currency); nil for anything else.
    static func number(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 15 else { return nil }
        var digits = trimmed
        if digits.contains(",") {
            guard digits.range(of: "^-?[0-9]{1,3}(,[0-9]{3})+(\\.[0-9]+)?$", options: .regularExpression) != nil else {
                return nil
            }
            digits = digits.replacingOccurrences(of: ",", with: "")
        }
        guard digits.range(of: "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return digits
    }

    private static func worksheet(_ rows: [[String]]) -> String {
        let width = min(rows.map { $0.count }.max() ?? 0, 200)
        var xml = OOXML.header + "<worksheet xmlns=\"\(nsMain)\">"
        if width > 0 {
            xml += "<cols>"
            for column in 0..<width {
                var longest = 6
                for row in rows where column < row.count {
                    longest = max(longest, min(row[column].count, 60))
                }
                xml += "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(longest + 2)\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for (rowIndex, row) in rows.enumerated() {
            let cells = row.prefix(width).enumerated().filter { !$0.element.isEmpty }
            guard !cells.isEmpty else { continue }
            xml += "<row r=\"\(rowIndex + 1)\">"
            for (column, value) in cells {
                let ref = "\(columnName(column))\(rowIndex + 1)"
                if let numeric = number(from: value) {
                    xml += "<c r=\"\(ref)\"><v>\(numeric)</v></c>"
                } else {
                    xml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(OOXML.escape(value))</t></is></c>"
                }
            }
            xml += "</row>"
        }
        return xml + "</sheetData></worksheet>"
    }
}
