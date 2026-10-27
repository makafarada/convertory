import Foundation
import UIKit

enum OOXML {
    /// Escapes text for XML and drops characters XML 1.0 cannot hold.
    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D { continue }
            if v == 0xFFFE || v == 0xFFFF { continue }
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    static let relationshipsNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let officeRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
}

/// Writes a .pptx in which every slide is one page picture. Built on the stored-entry ZipWriter.
enum PptxWriter {
    struct Slide {
        let jpeg: Data
        let size: CGSize
    }

    private static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    private static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"

    private static let emptyTree =
        "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>" +
        "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/>" +
        "<a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    static func makePresentation(slides: [Slide]) -> Data {
        let reference = slides.first?.size ?? CGSize(width: 4, height: 3)
        let ratio = max(reference.width, 1) / max(reference.height, 1)
        let slideW: Int
        let slideH: Int
        if ratio >= 1 {
            slideW = 12_192_000
            slideH = Int(Double(slideW) / Double(ratio))
        } else {
            slideH = 9_144_000
            slideW = Int(Double(slideH) * Double(ratio))
        }

        var zip = ZipWriter()
        zip.add(name: "[Content_Types].xml", data: utf8(contentTypes(slideCount: slides.count)))
        zip.add(name: "_rels/.rels", data: utf8(
            OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">" +
            "<Relationship Id=\"rId1\" Type=\"\(OOXML.officeRel)/officeDocument\" Target=\"ppt/presentation.xml\"/>" +
            "</Relationships>"))
        zip.add(name: "ppt/presentation.xml", data: utf8(presentation(slideCount: slides.count, width: slideW, height: slideH)))
        zip.add(name: "ppt/_rels/presentation.xml.rels", data: utf8(presentationRels(slideCount: slides.count)))
        zip.add(name: "ppt/slideMasters/slideMaster1.xml", data: utf8(slideMaster))
        zip.add(name: "ppt/slideMasters/_rels/slideMaster1.xml.rels", data: utf8(
            OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">" +
            "<Relationship Id=\"rId1\" Type=\"\(OOXML.officeRel)/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>" +
            "<Relationship Id=\"rId2\" Type=\"\(OOXML.officeRel)/theme\" Target=\"../theme/theme1.xml\"/>" +
            "</Relationships>"))
        zip.add(name: "ppt/slideLayouts/slideLayout1.xml", data: utf8(slideLayout))
        zip.add(name: "ppt/slideLayouts/_rels/slideLayout1.xml.rels", data: utf8(
            OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">" +
            "<Relationship Id=\"rId1\" Type=\"\(OOXML.officeRel)/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/>" +
            "</Relationships>"))
        zip.add(name: "ppt/theme/theme1.xml", data: utf8(theme))

        for (offset, slide) in slides.enumerated() {
            let number = offset + 1
            zip.add(name: "ppt/slides/slide\(number).xml",
                    data: utf8(slideXML(number: number, picture: slide.size, slideWidth: slideW, slideHeight: slideH)))
            zip.add(name: "ppt/slides/_rels/slide\(number).xml.rels", data: utf8(
                OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">" +
                "<Relationship Id=\"rId1\" Type=\"\(OOXML.officeRel)/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>" +
                "<Relationship Id=\"rId2\" Type=\"\(OOXML.officeRel)/image\" Target=\"../media/image\(number).jpeg\"/>" +
                "</Relationships>"))
            zip.add(name: "ppt/media/image\(number).jpeg", data: slide.jpeg)
        }
        return zip.finish()
    }

    private static func utf8(_ text: String) -> Data { Data(text.utf8) }

    private static func contentTypes(slideCount: Int) -> String {
        var xml = OOXML.header +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>" +
            "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>" +
            "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/>" +
            "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>" +
            "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        for number in 1...max(slideCount, 1) where number <= slideCount {
            xml += "<Override PartName=\"/ppt/slides/slide\(number).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
        }
        return xml + "</Types>"
    }

    private static func presentation(slideCount: Int, width: Int, height: Int) -> String {
        var ids = ""
        for number in 1...max(slideCount, 1) where number <= slideCount {
            ids += "<p:sldId id=\"\(255 + number)\" r:id=\"rId\(number + 1)\"/>"
        }
        return OOXML.header +
            "<p:presentation xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\">" +
            "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>" +
            "<p:sldIdLst>\(ids)</p:sldIdLst>" +
            "<p:sldSz cx=\"\(width)\" cy=\"\(height)\"/>" +
            "<p:notesSz cx=\"6858000\" cy=\"9144000\"/>" +
            "</p:presentation>"
    }

    private static func presentationRels(slideCount: Int) -> String {
        var xml = OOXML.header + "<Relationships xmlns=\"\(OOXML.relationshipsNS)\">" +
            "<Relationship Id=\"rId1\" Type=\"\(OOXML.officeRel)/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        for number in 1...max(slideCount, 1) where number <= slideCount {
            xml += "<Relationship Id=\"rId\(number + 1)\" Type=\"\(OOXML.officeRel)/slide\" Target=\"slides/slide\(number).xml\"/>"
        }
        xml += "<Relationship Id=\"rId\(slideCount + 2)\" Type=\"\(OOXML.officeRel)/theme\" Target=\"theme/theme1.xml\"/>"
        return xml + "</Relationships>"
    }

    private static func slideXML(number: Int, picture: CGSize, slideWidth: Int, slideHeight: Int) -> String {
        // Fit the page picture inside the slide, centred.
        let scale = min(Double(slideWidth) / Double(max(picture.width, 1)),
                        Double(slideHeight) / Double(max(picture.height, 1)))
        let w = Int(Double(picture.width) * scale)
        let h = Int(Double(picture.height) * scale)
        let x = (slideWidth - w) / 2
        let y = (slideHeight - h) / 2
        var xml = OOXML.header
        xml += "<p:sld xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\"><p:cSld><p:spTree>"
        xml += emptyTree
        xml += "<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page \(number)\" descr=\"Page \(number)\"/>"
        xml += "<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
        xml += "<p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
        xml += "<p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm>"
        xml += "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
        xml += "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
        return xml
    }

    private static var slideMaster: String {
        OOXML.header +
        "<p:sldMaster xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\"><p:cSld>" +
        "<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>" +
        "<p:spTree>" + emptyTree + "</p:spTree></p:cSld>" +
        "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" " +
        "accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>" +
        "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst>" +
        "</p:sldMaster>"
    }

    private static var slideLayout: String {
        OOXML.header +
        "<p:sldLayout xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\" type=\"blank\" preserve=\"1\">" +
        "<p:cSld name=\"Blank\"><p:spTree>" + emptyTree + "</p:spTree></p:cSld>" +
        "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
    }

    private static var theme: String {
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"9525\">" + fill + "</a:ln>"
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        func color(_ name: String, _ value: String) -> String {
            "<a:\(name)><a:srgbClr val=\"\(value)\"/></a:\(name)>"
        }
        let colors = color("dk1", "000000") + color("lt1", "FFFFFF") + color("dk2", "1F2A44") + color("lt2", "EEF2F8") +
            color("accent1", "0088FF") + color("accent2", "FFD400") + color("accent3", "00B7FF") +
            color("accent4", "9D73FF") + color("accent5", "12C4C9") + color("accent6", "F24F87") +
            color("hlink", "0563C1") + color("folHlink", "954F72")
        let fonts = "<a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        return OOXML.header +
            "<a:theme xmlns:a=\"\(nsA)\" name=\"Convertory\"><a:themeElements>" +
            "<a:clrScheme name=\"Convertory\">\(colors)</a:clrScheme>" +
            "<a:fontScheme name=\"Convertory\"><a:majorFont>\(fonts)</a:majorFont><a:minorFont>\(fonts)</a:minorFont></a:fontScheme>" +
            "<a:fmtScheme name=\"Convertory\">" +
            "<a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst>" +
            "<a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst>" +
            "<a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst>" +
            "<a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst>" +
            "</a:fmtScheme></a:themeElements></a:theme>"
    }
}
