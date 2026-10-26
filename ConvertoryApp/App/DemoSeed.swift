#if DEBUG
import UIKit

/// Debug-only sample content used by the screenshot UI tests (`-seedDemo`). Not compiled into Release builds.
enum DemoSeed {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-seedDemo") }

    private static func makePDF(title: String, lines: [String], name: String) -> URL {
        let url = Inbox.folder.appendingPathComponent("\(name).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { context in
            for page in 1...3 {
                context.beginPage()
                UIColor(red: 0.86, green: 0.32, blue: 0.16, alpha: 1).setFill()
                UIRectFill(CGRect(x: 48, y: 52, width: 6, height: 34))
                (title as NSString).draw(at: CGPoint(x: 66, y: 52), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 28, weight: .bold)
                ])
                var y: CGFloat = 120
                for line in lines {
                    (line as NSString).draw(in: CGRect(x: 48, y: y, width: 499, height: 60), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 14),
                        .foregroundColor: UIColor.darkGray
                    ])
                    y += 44
                }
                ("Page \(page) of 3" as NSString).draw(at: CGPoint(x: 48, y: 780), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.gray
                ])
            }
        }
        try? data.write(to: url)
        return url
    }

    static func inputs(for tool: Tool) -> [URL] {
        switch tool {
        case .merge:
            return [
                makePDF(title: "Lease agreement", lines: sampleLines, name: "Lease agreement"),
                makePDF(title: "Signed addendum", lines: sampleLines, name: "Signed addendum")
            ]
        case .scan, .imagesToPDF:
            return []
        default:
            return [makePDF(title: "Quarterly report", lines: sampleLines, name: "Quarterly report")]
        }
    }

    private static let sampleLines = [
        "Revenue grew steadily across all regions during the quarter, led by subscriptions.",
        "Operating costs stayed flat while the team shipped three major releases.",
        "Customer satisfaction reached its highest level since the survey began.",
        "Next quarter we will focus on onboarding, reliability and support response time.",
        "Appendix tables with the full regional breakdown follow on the next pages."
    ]

    /// Called once at launch: seeds the Library and, with `-demoTool <rawValue>`, opens that tool with sample files.
    @MainActor
    static func apply(to router: Router) {
        installLibrary()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoTool"), i + 1 < args.count,
           let tool = Tool(rawValue: args[i + 1]) {
            router.incoming = inputs(for: tool)
            router.open(tool)
        }
    }

    /// Fills the Library with a few finished files.
    static func installLibrary() {
        let report = makePDF(title: "Quarterly report", lines: sampleLines, name: "Seed report")
        let notes = makePDF(title: "Meeting notes", lines: sampleLines, name: "Seed notes")
        _ = try? Engine.merge([report, notes])
        _ = try? Engine.watermark(report, text: "CONFIDENTIAL", opacity: 0.2, style: .diagonal)
        _ = try? Engine.pdfToWord(report)
        _ = try? Engine.extractText(from: notes)
        _ = try? Engine.compress(report, level: .balanced)
        Task { @MainActor in LibraryStore.shared.reload() }
    }
}
#endif
