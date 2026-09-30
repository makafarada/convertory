import Foundation

@MainActor
final class ConvertFlowViewModel: ObservableObject {
    @Published var route: AppRoute = .convert
    @Published var isPro = false
    @Published var todayConversions = 1
    @Published var selectedDocument: DocumentItem?
    @Published var selectedType: ConversionType = .pdfToExcel
    @Published var isProcessing = false
    @Published var processingStep: ProcessingStep = .reading
    @Published var progress = 0.0
    @Published var result: ConversionResult?
    @Published var history: [ConversionResult] = []
    @Published var batchQueue: [BatchItem] = []
    @Published var errorMessage: String?
    @Published var isOffline = false
    @Published var showProSheet = false
    @Published var showPrivacySheet = false

    let sampleDocuments: [DocumentItem] = [
        DocumentItem(name: "Invoice sample.pdf", sizeBytes: 248_000, pageCount: 1, isSample: true),
        DocumentItem(name: "Contract sample.pdf", sizeBytes: 512_000, pageCount: 2, isSample: true),
        DocumentItem(name: "Receipt scan.jpg", sizeBytes: 138_000, pageCount: 1, isSample: true),
        DocumentItem(name: "Monthly report.pdf", sizeBytes: 1_420_000, pageCount: 6, isSample: true)
    ]

    var freeLimitReached: Bool {
        !isPro && todayConversions >= 3
    }

    func selectSample(_ document: DocumentItem, type: ConversionType) {
        selectedDocument = document
        selectedType = type
        result = nil
    }

    func startConversion() {
        guard let document = selectedDocument else {
            errorMessage = "Choose a document first."
            return
        }
        guard !freeLimitReached else {
            showProSheet = true
            return
        }

        isProcessing = true
        progress = 0.08
        processingStep = .reading

        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            processingStep = .detecting
            progress = 0.38
            try? await Task.sleep(nanoseconds: 350_000_000)
            processingStep = .extracting
            progress = 0.68
            try? await Task.sleep(nanoseconds: 350_000_000)
            processingStep = .building
            progress = 0.92
            try? await Task.sleep(nanoseconds: 250_000_000)

            let baseName = document.name.split(separator: ".").first.map(String.init) ?? "converted"
            let conversion = ConversionResult(
                outputName: "\(baseName).\(selectedType.outputExtension)",
                type: selectedType,
                sizeBytes: max(42_000, document.sizeBytes / 3),
                preview: "Local sample conversion completed with preserved layout, table structure, and export metadata.",
                createdAt: Date()
            )
            result = conversion
            history.insert(conversion, at: 0)
            todayConversions += 1
            isProcessing = false
            progress = 1
        }
    }

    func addBatchSamples() {
        batchQueue = sampleDocuments.prefix(3).map {
            BatchItem(name: $0.name, type: .pdfToExcel, status: "Queued", progress: 0)
        }
        route = .batch
    }

    func runBatch() {
        guard isPro else {
            showProSheet = true
            return
        }
        for index in batchQueue.indices {
            batchQueue[index].status = "Completed"
            batchQueue[index].progress = 1
        }
    }

    func clearHistory() {
        history.removeAll()
    }
}
