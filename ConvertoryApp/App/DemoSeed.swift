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
                UIColor(red: 0, green: 0.533, blue: 1, alpha: 1).setFill()
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

    /// A large picture-only PDF, like a phone scan, so Compress has something to shrink.
    private static func makePhotoPDF(name: String) -> URL {
        let size = CGSize(width: 2000, height: 2800)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            // Desk with a soft gradient, like a phone photo of a paper on a table.
            let colors = [UIColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1).cgColor,
                          UIColor(red: 0.36, green: 0.27, blue: 0.21, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            // Paper with a shadow.
            let paper = CGRect(x: 180, y: 220, width: 1640, height: 2360)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 30), blur: 60, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor(white: 0.97, alpha: 1).setFill()
            cg.fill(paper)
            cg.restoreGState()
            ("Signed contract" as NSString).draw(at: CGPoint(x: 300, y: 340), withAttributes: [
                .font: UIFont.systemFont(ofSize: 130, weight: .bold), .foregroundColor: UIColor(white: 0.1, alpha: 1)])
            for row in 0..<22 {
                UIColor(white: 0.35, alpha: 0.55).setFill()
                let width = CGFloat(1180 + (row * 97) % 220)
                cg.fill(CGRect(x: 300, y: CGFloat(620 + row * 78), width: width, height: 26))
            }
            // Signature scribble.
            UIColor(red: 0.1, green: 0.15, blue: 0.5, alpha: 1).setStroke()
            let sign = UIBezierPath()
            sign.lineWidth = 9
            sign.move(to: CGPoint(x: 320, y: 2330))
            sign.addCurve(to: CGPoint(x: 900, y: 2300), controlPoint1: CGPoint(x: 450, y: 2180), controlPoint2: CGPoint(x: 600, y: 2420))
            sign.addCurve(to: CGPoint(x: 1300, y: 2320), controlPoint1: CGPoint(x: 1000, y: 2200), controlPoint2: CGPoint(x: 1150, y: 2400))
            sign.stroke()
            // Fine grain so the file is realistically large.
            for i in 0..<9000 {
                UIColor(white: CGFloat((i * 13) % 100) / 100, alpha: 0.08).setFill()
                cg.fill(CGRect(x: (i * 211) % 2000, y: (i * 389) % 2800, width: 8, height: 8))
            }
        }
        let png = Inbox.folder.appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: png)
        let pdf = try? Engine.imagesToPDF([png, png, png], layout: .a4, searchable: false, prefix: "DemoPhoto")
        let target = Inbox.folder.appendingPathComponent("\(name).pdf")
        if let pdf { try? FileManager.default.removeItem(at: target); try? FileManager.default.moveItem(at: pdf, to: target) }
        return target
    }

    static func inputs(for tool: Tool) -> [URL] {
        switch tool {
        case .merge:
            return [
                makePDF(title: "Lease agreement", lines: sampleLines, name: "Lease agreement"),
                makePDF(title: "Signed addendum", lines: sampleLines, name: "Signed addendum")
            ]
        case .compress:
            return [makePhotoPDF(name: "Signed contract (scan)")]
        case .scan, .imagesToPDF, .wordToPDF:
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
        let docs = LibraryStore.folder
        for url in (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
        if !ProcessInfo.processInfo.arguments.contains("-demoTool") { installLibrary() }
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
