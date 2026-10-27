import SwiftUI
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Output library (the app's Documents folder, visible in the Files app)

enum ResultKind {
    case pdf, text, word, slides, sheet

    init?(ext: String) {
        switch ext.lowercased() {
        case "pdf": self = .pdf
        case "txt": self = .text
        case "docx": self = .word
        case "pptx": self = .slides
        case "xlsx": self = .sheet
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .pdf: return "doc.fill"
        case .text: return "text.alignleft"
        case .word: return "doc.richtext.fill"
        case .slides: return "rectangle.on.rectangle.angled"
        case .sheet: return "tablecells.fill"
        }
    }

    var label: String {
        switch self {
        case .pdf: return "PDF"
        case .text: return "Text"
        case .word: return "Word"
        case .slides: return "PowerPoint"
        case .sheet: return "Excel"
        }
    }
}

struct LibraryFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let date: Date
    let kind: ResultKind

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }

    static func == (a: LibraryFile, b: LibraryFile) -> Bool { a.url == b.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }

    init?(url: URL) {
        guard let kind = ResultKind(ext: url.pathExtension) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.url = url
        self.kind = kind
        self.size = Int64(values?.fileSize ?? 0)
        self.date = values?.contentModificationDate ?? Date()
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var files: [LibraryFile] = []

    nonisolated static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        files = urls.compactMap(LibraryFile.init(url:)).sorted { $0.date > $1.date }
    }

    func delete(_ file: LibraryFile) {
        try? FileManager.default.removeItem(at: file.url)
        reload()
    }

    /// A fresh, unique output path such as "Merged 20261026-143205.pdf".
    nonisolated static func newOutputURL(prefix: String, ext: String) -> URL {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        var url = folder.appendingPathComponent("\(prefix) \(stamp.string(from: Date())).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(prefix) \(stamp.string(from: Date())) \(n).\(ext)")
            n += 1
        }
        return url
    }
}

// MARK: - Staging imported files in a temp folder

enum Inbox {
    static var folder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func freshSlot(named name: String) throws -> URL {
        let dir = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// Copies a file picked by the user (possibly security scoped, possibly in iCloud) into the app sandbox.
    static func stage(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let target = try freshSlot(named: source.lastPathComponent)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: target) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return target
    }

    static func stage(data: Data, name: String) throws -> URL {
        let target = try freshSlot(named: name)
        try data.write(to: target)
        return target
    }

    static func stage(image: UIImage, name: String) throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw EngineError.message("Couldn't read the scanned page.")
        }
        return try stage(data: data, name: name)
    }
}

// MARK: - Input items shown in the tray

struct InputItem: Identifiable {
    let id = UUID()
    let url: URL
    let isPDF: Bool
    let pageCount: Int
    let thumbnail: UIImage?
    var isWord = false

    var name: String { url.lastPathComponent }

    var fileSize: Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        if isWord { return "Word document · \(size)" }
        return isPDF ? "\(pageCount) page\(pageCount == 1 ? "" : "s") · \(size)" : "Picture · \(size)"
    }

    /// Returns nil for unreadable or password-protected files.
    static func make(from url: URL) -> InputItem? {
        let isPDF = url.pathExtension.lowercased() == "pdf"
        if isPDF {
            guard let doc = PDFDocument(url: url), !doc.isLocked, doc.pageCount > 0 else { return nil }
            let thumb = doc.page(at: 0)?.thumbnail(of: CGSize(width: 96, height: 128), for: .cropBox)
            return InputItem(url: url, isPDF: true, pageCount: doc.pageCount, thumbnail: thumb)
        }
        if url.pathExtension.lowercased() == "docx" {
            guard let zip = ZipReader(url: url), zip.contains("word/document.xml") else { return nil }
            return InputItem(url: url, isPDF: false, pageCount: 1, thumbnail: nil, isWord: true)
        }
        guard let image = ImageLoader.load(url, maxPixel: 220) else { return nil }
        return InputItem(url: url, isPDF: false, pageCount: 1, thumbnail: image)
    }
}

enum ImageLoader {
    /// Decodes an image upright and downsampled so large photos do not exhaust memory.
    static func load(_ url: URL, maxPixel: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum EngineError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
