import SwiftUI
import UniformTypeIdentifiers

/// What kind of files a tool takes as input.
enum InputKind {
    case pdf, images, pdfOrImage, word

    var contentTypes: [UTType] {
        switch self {
        case .word: return [UTType("org.openxmlformats.wordprocessingml.document") ?? .data]
        case .pdf: return [.pdf]
        case .images: return [.image]
        case .pdfOrImage: return [.pdf, .image]
        }
    }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case scan, imagesToPDF, merge, organize, watermark, compress, extractText, pdfToWord, wordToPDF, pdfToPowerPoint, pdfToExcel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: return "Scan to PDF"
        case .imagesToPDF: return "Photos to PDF"
        case .merge: return "Merge"
        case .organize: return "Organize pages"
        case .watermark: return "Watermark"
        case .compress: return "Compress"
        case .extractText: return "Extract text"
        case .pdfToWord: return "PDF to Word"
        case .wordToPDF: return "Word to PDF"
        case .pdfToPowerPoint: return "PDF to PowerPoint"
        case .pdfToExcel: return "PDF to Excel"
        }
    }

    var tagline: String {
        switch self {
        case .scan: return "Use the camera. Pages become a searchable PDF."
        case .imagesToPDF: return "Turn pictures into one tidy PDF."
        case .merge: return "Join PDFs and pictures in the order you choose."
        case .organize: return "Reorder, rotate or remove pages."
        case .watermark: return "Stamp your own text on every page."
        case .compress: return "Make a large PDF small enough to send."
        case .extractText: return "Pull the text out of a PDF or a photo."
        case .pdfToWord: return "An editable .docx with headings and paragraphs."
        case .wordToPDF: return "Turn a .docx into a PDF: text, headings and tables."
        case .pdfToPowerPoint: return "Every page becomes a slide in a .pptx."
        case .pdfToExcel: return "Find simple tables and save them as a .xlsx."
        }
    }

    var symbol: String {
        switch self {
        case .scan: return "doc.viewfinder"
        case .imagesToPDF: return "photo.on.rectangle.angled"
        case .merge: return "rectangle.stack"
        case .organize: return "square.grid.2x2"
        case .watermark: return "drop.halffull"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .extractText: return "text.viewfinder"
        case .pdfToWord: return "doc.richtext"
        case .wordToPDF: return "doc.plaintext"
        case .pdfToPowerPoint: return "rectangle.on.rectangle.angled"
        case .pdfToExcel: return "tablecells"
        }
    }

    var tint: Color {
        switch self {
        case .scan: return Color(red: 1, green: 0.831, blue: 0)
        case .imagesToPDF: return Color(red: 0, green: 0.718, blue: 1)
        case .merge: return Color(red: 0.62, green: 0.45, blue: 1)
        case .organize: return Color(red: 0.07, green: 0.77, blue: 0.79)
        case .watermark: return Color(red: 0.95, green: 0.31, blue: 0.53)
        case .compress: return Color(red: 0.12, green: 0.75, blue: 0.37)
        case .extractText: return Color(red: 1, green: 0.36, blue: 0.40)
        case .pdfToWord: return Color(red: 0.2, green: 0.6, blue: 1)
        case .wordToPDF: return Color(red: 0.98, green: 0.45, blue: 0.27)
        case .pdfToPowerPoint: return Color(red: 1, green: 0.62, blue: 0.15)
        case .pdfToExcel: return Color(red: 0.15, green: 0.68, blue: 0.45)
        }
    }

    var input: InputKind {
        switch self {
        case .scan, .imagesToPDF: return .images
        case .merge, .extractText: return .pdfOrImage
        case .organize, .watermark, .compress, .pdfToWord, .pdfToPowerPoint, .pdfToExcel: return .pdf
        case .wordToPDF: return .word
        }
    }

    var allowsMultiple: Bool {
        switch self {
        case .scan, .imagesToPDF, .merge: return true
        default: return false
        }
    }

    var minimumItems: Int { self == .merge ? 2 : 1 }

    var actionTitle: String {
        switch self {
        case .scan, .imagesToPDF: return "Create PDF"
        case .merge: return "Merge files"
        case .organize: return "Save pages"
        case .watermark: return "Add watermark"
        case .compress: return "Compress"
        case .extractText: return "Extract text"
        case .pdfToWord: return "Convert to Word"
        case .wordToPDF: return "Convert to PDF"
        case .pdfToPowerPoint: return "Convert to PowerPoint"
        case .pdfToExcel: return "Convert to Excel"
        }
    }

    var emptyHint: String {
        switch input {
        case .pdf: return "Choose a PDF to begin."
        case .images: return "Add photos or pages to begin."
        case .pdfOrImage: return "Choose PDFs or pictures to begin."
        case .word: return "Choose a Word document (.docx) to begin."
        }
    }

    /// Tools that make sense for a file opened from another app.
    static func suggestions(forExtension fileExtension: String) -> [Tool] {
        let lower = fileExtension.lowercased()
        let isPDF = lower == "pdf"
        let isWord = lower == "docx"
        return allCases.filter { tool in
            switch tool.input {
            case .pdf: return isPDF
            case .word: return isWord
            case .images: return !isPDF && !isWord && tool != .scan
            case .pdfOrImage: return !isWord
            }
        }
    }
}

enum PageLayout: String, CaseIterable, Identifiable {
    case a4 = "A4"
    case letter = "US Letter"
    case fit = "Match picture"

    var id: String { rawValue }

    func pageRect(for image: CGSize) -> CGRect {
        switch self {
        case .fit:
            let longSide: CGFloat = 842
            let scale = longSide / max(image.width, image.height, 1)
            return CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale)
        case .a4, .letter:
            let base = self == .a4 ? CGSize(width: 595, height: 842) : CGSize(width: 612, height: 792)
            let landscape = image.width > image.height
            return CGRect(x: 0, y: 0,
                          width: landscape ? base.height : base.width,
                          height: landscape ? base.width : base.height)
        }
    }

    func imageRect(for image: CGSize, in page: CGRect) -> CGRect {
        if self == .fit { return page }
        let area = page.insetBy(dx: 24, dy: 24)
        let scale = min(area.width / max(image.width, 1), area.height / max(image.height, 1))
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

enum WatermarkStyle: String, CaseIterable, Identifiable {
    case diagonal = "Diagonal"
    case tiled = "Tiled"
    var id: String { rawValue }
}

enum CompressLevel: String, CaseIterable, Identifiable {
    case smallest = "Smallest"
    case balanced = "Balanced"
    case sharp = "Sharp"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .smallest: return "Lowest quality, smallest file"
        case .balanced: return "Good for e-mail"
        case .sharp: return "Keeps small print readable"
        }
    }

    /// Render scale relative to 72 dpi, and JPEG quality.
    var renderScale: CGFloat {
        switch self {
        case .smallest: return 1.0
        case .balanced: return 1.5
        case .sharp: return 2.1
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .smallest: return 0.45
        case .balanced: return 0.6
        case .sharp: return 0.75
        }
    }
}
