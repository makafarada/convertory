import SwiftUI
import PDFKit
import PhotosUI

@MainActor
final class ToolModel: ObservableObject {
    let tool: Tool

    @Published var items: [InputItem] = []
    @Published var pageEdits: [Engine.PageEdit] = []
    @Published var busy = false
    @Published var progress = 0.0
    @Published var message: String?
    @Published var result: LibraryFile?

    // Options
    @Published var watermarkText = "CONFIDENTIAL"
    @Published var watermarkOpacity = 0.22
    @Published var watermarkStyle = WatermarkStyle.diagonal
    @Published var layout = PageLayout.a4
    @Published var searchable = true
    @Published var compressLevel = CompressLevel.balanced

    private(set) var organizerDocument: PDFDocument?

    init(tool: Tool) {
        self.tool = tool
    }

    var canRun: Bool {
        guard !busy else { return false }
        if tool == .organize { return !pageEdits.isEmpty }
        return items.count >= tool.minimumItems
    }

    // MARK: Adding input

    func add(urls: [URL]) {
        guard !urls.isEmpty else { return }
        busy = true
        message = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ([InputItem], Int) in
                var loaded: [InputItem] = []
                var failed = 0
                for url in urls {
                    if let staged = try? Inbox.stage(url), let item = InputItem.make(from: staged) {
                        loaded.append(item)
                    } else {
                        failed += 1
                    }
                }
                return (loaded, failed)
            }.value
            finishAdding(outcome.0, failed: outcome.1)
        }
    }

    func add(photos: [PhotosPickerItem]) {
        guard !photos.isEmpty else { return }
        busy = true
        message = nil
        Task {
            var staged: [URL] = []
            var failed = 0
            for (index, photo) in photos.enumerated() {
                let ext = photo.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                if let data = try? await photo.loadTransferable(type: Data.self),
                   let url = try? Inbox.stage(data: data, name: "Photo \(index + 1).\(ext)") {
                    staged.append(url)
                } else {
                    failed += 1
                }
            }
            let outcome = await Task.detached(priority: .userInitiated) { () -> [InputItem] in
                staged.compactMap(InputItem.make(from:))
            }.value
            finishAdding(outcome, failed: failed + (staged.count - outcome.count))
        }
    }

    func add(scannedPages images: [UIImage]) {
        guard !images.isEmpty else { return }
        busy = true
        message = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> [InputItem] in
                var out: [InputItem] = []
                for (index, image) in images.enumerated() {
                    if let url = try? Inbox.stage(image: image, name: "Scan \(index + 1).jpg"),
                       let item = InputItem.make(from: url) {
                        out.append(item)
                    }
                }
                return out
            }.value
            finishAdding(outcome, failed: images.count - outcome.count)
        }
    }

    private func finishAdding(_ loaded: [InputItem], failed: Int) {
        busy = false
        if tool.allowsMultiple {
            items.append(contentsOf: loaded)
        } else if let first = loaded.first {
            items = [first]
        }
        if tool == .organize, let first = items.first { loadOrganizer(for: first) }
        if failed > 0 {
            message = failed == 1
                ? "One file couldn't be opened. It may be damaged or password protected."
                : "\(failed) files couldn't be opened. They may be damaged or password protected."
        }
    }

    func remove(at offsets: IndexSet) { items.remove(atOffsets: offsets) }
    func move(from source: IndexSet, to destination: Int) { items.move(fromOffsets: source, toOffset: destination) }

    func clear() {
        items = []
        pageEdits = []
        organizerDocument = nil
        message = nil
    }

    // MARK: Organizer

    private func loadOrganizer(for item: InputItem) {
        organizerDocument = PDFDocument(url: item.url)
        pageEdits = (0..<item.pageCount).map { Engine.PageEdit(sourceIndex: $0) }
    }

    func thumbnail(for edit: Engine.PageEdit) -> UIImage? {
        guard let page = organizerDocument?.page(at: edit.sourceIndex) else { return nil }
        return page.thumbnail(of: CGSize(width: 110, height: 150), for: .cropBox)
    }

    func rotate(_ edit: Engine.PageEdit) {
        guard let index = pageEdits.firstIndex(where: { $0.id == edit.id }) else { return }
        pageEdits[index].rotation = (pageEdits[index].rotation + 90) % 360
    }

    // MARK: Running

    func run() {
        guard canRun else { return }
        busy = true
        progress = 0
        message = nil

        let tool = self.tool
        let urls = items.map(\.url)
        let edits = pageEdits
        let text = watermarkText
        let opacity = watermarkOpacity
        let style = watermarkStyle
        let layout = self.layout
        let searchable = self.searchable
        let level = compressLevel
        let originalSize = items.first?.fileSize ?? 0

        let report: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in self?.progress = value }
        }

        Task {
            do {
                let output: URL = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    switch tool {
                    case .scan:
                        return try Engine.imagesToPDF(urls, layout: layout, searchable: searchable,
                                                      prefix: "Scan", progress: report)
                    case .imagesToPDF:
                        return try Engine.imagesToPDF(urls, layout: layout, searchable: searchable,
                                                      prefix: "Photos", progress: report)
                    case .merge:
                        return try Engine.merge(urls, progress: report)
                    case .organize:
                        return try Engine.organize(urls[0], edits: edits)
                    case .watermark:
                        return try Engine.watermark(urls[0], text: text, opacity: opacity,
                                                    style: style, progress: report)
                    case .compress:
                        let out = try Engine.compress(urls[0], level: level, progress: report)
                        let newSize = Int64((try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        if newSize >= originalSize {
                            try? FileManager.default.removeItem(at: out)
                            throw EngineError.message("This PDF is already compact, so compressing it wouldn't make it smaller. Try the Smallest setting.")
                        }
                        return out
                    case .extractText:
                        return try Engine.extractText(from: urls[0], progress: report)
                    case .pdfToWord:
                        return try Engine.pdfToWord(urls[0], progress: report)
                    }
                }.value
                busy = false
                LibraryStore.shared.reload()
                result = LibraryFile(url: output)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                busy = false
                message = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
