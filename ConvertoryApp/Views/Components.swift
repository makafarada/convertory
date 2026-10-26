import SwiftUI
import PDFKit
import QuickLook
import VisionKit

// MARK: - Look

enum Theme {
    // Same palette as the Convertory web, Windows and Android apps (ms-store/styles.css).
    static let yellow = Color(red: 1, green: 0.831, blue: 0)                 // #FFD400
    static let blue = Color(red: 0, green: 0.533, blue: 1)                   // #0088FF
    static let cyan = Color(red: 0, green: 0.718, blue: 1)                   // #00B7FF
    static let ink = Color(red: 0.035, green: 0.082, blue: 0.149)            // #091526, text on yellow
    static let text = Color(red: 0.969, green: 0.984, blue: 1)               // #F7FBFF
    static let muted = Color(red: 0.616, green: 0.725, blue: 0.875)          // #9DB9DF
    static let paper = Color(red: 0.0, green: 0.071, blue: 0.161)            // #001229
    static let card = Color(red: 0.012, green: 0.118, blue: 0.243)           // #031E3E
    static let line = Color(red: 0, green: 0.533, blue: 1).opacity(0.45)     // rgba(0,136,255,.45)
}

/// The dark navy screen with soft yellow and blue glows used across every Convertory app.
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.024, green: 0.102, blue: 0.22),
                                    Color(red: 0, green: 0.071, blue: 0.161),
                                    Color(red: 0.024, green: 0.102, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0, green: 0.549, blue: 1).opacity(0.28), .clear],
                           center: UnitPoint(x: 0.18, y: 0.12), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Theme.yellow.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.82, y: 0.18), startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
    }
}

/// Yellow call-to-action, like the primary button in the other Convertory apps.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.yellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Blue-outlined secondary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.text)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cyan.opacity(0.8), lineWidth: 1.2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: shape)
            .overlay(shape.strokeBorder(tint.opacity(0.75), lineWidth: 1.2))
    }
}

// MARK: - PDFKit

struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = false
        view.backgroundColor = UIColor(red: 0, green: 0.071, blue: 0.161, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

// MARK: - Quick Look (Word files)

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Camera document scanner (VisionKit)

struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

// MARK: - Progress overlay

struct BusyOverlay: View {
    let progress: Double
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                if progress > 0 && progress < 1 {
                    ProgressView(value: progress).frame(width: 180)
                } else {
                    ProgressView()
                }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .transition(.opacity)
    }
}
