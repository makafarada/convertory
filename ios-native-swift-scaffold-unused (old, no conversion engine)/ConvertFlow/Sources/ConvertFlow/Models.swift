import Foundation

enum ConversionType: String, CaseIterable, Identifiable {
    case pdfToExcel = "PDF to Excel"
    case pdfToWord = "PDF to Word"
    case pdfToImages = "PDF to Images"
    case imageToPdf = "Image to PDF"
    case imageToWord = "Image to Word"
    case imageToExcel = "Image to Excel"
    case mergePdf = "Merge PDF"
    case splitPdf = "Split PDF"
    case compressPdf = "Compress PDF"
    case watermarkPdf = "Watermark PDF"
    case rotatePdf = "Rotate PDF"
    case signPdf = "Sign PDF"

    var id: String { rawValue }

    var outputExtension: String {
        switch self {
        case .pdfToExcel, .imageToExcel: return "xlsx"
        case .pdfToWord, .imageToWord: return "docx"
        case .pdfToImages: return "zip"
        default: return "pdf"
        }
    }
}

enum AppRoute {
    case convert
    case batch
    case history
}

enum ProcessingStep: String {
    case reading = "Reading document"
    case detecting = "Detecting structure"
    case extracting = "Extracting content"
    case building = "Building output"
}

struct DocumentItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let sizeBytes: Int
    let pageCount: Int
    let isSample: Bool
}

struct ConversionResult: Identifiable, Equatable {
    let id = UUID()
    let outputName: String
    let type: ConversionType
    let sizeBytes: Int
    let preview: String
    let createdAt: Date
}

struct BatchItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: ConversionType
    var status: String
    var progress: Double
}
