import SwiftUI

struct ConvertView: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StatusBanner()
                    SamplePicker()
                    ConversionGrid()
                    PrimaryAction()
                    ResultPanel()
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Convertory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.showPrivacySheet = true } label: {
                        Image(systemName: "lock.shield")
                    }
                    .accessibilityLabel("Privacy")
                }
            }
        }
    }
}

private struct StatusBanner: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Local-first document conversion", systemImage: "doc.badge.gearshape")
                    .font(.headline)
                Spacer()
                Button(viewModel.isPro ? "Pro" : "Free") { viewModel.showProSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            Text("PDF, Word, Excel, and image workflows with private processing, history, and batch controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: min(Double(viewModel.todayConversions) / 3.0, 1.0)) {
                Text(viewModel.isPro ? "Unlimited Pro mode active" : "\(viewModel.todayConversions) of 3 free conversions used today")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SamplePicker: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sample Documents")
                .font(.headline)
            ForEach(viewModel.sampleDocuments) { document in
                Button {
                    viewModel.selectSample(document, type: .pdfToExcel)
                } label: {
                    HStack {
                        Image(systemName: document.name.hasSuffix(".jpg") ? "photo" : "doc.richtext")
                        VStack(alignment: .leading) {
                            Text(document.name)
                            Text("\(document.pageCount) pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct ConversionGrid: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ConversionType.allCases) { type in
                    Button {
                        viewModel.selectedType = type
                    } label: {
                        HStack {
                            Image(systemName: icon(for: type))
                            Text(type.rawValue)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(10)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.selectedType == type ? .cyan : .secondary)
                }
            }
        }
    }

    private func icon(for type: ConversionType) -> String {
        switch type {
        case .pdfToExcel, .imageToExcel: return "tablecells"
        case .pdfToWord, .imageToWord: return "doc.text"
        case .pdfToImages: return "photo.on.rectangle"
        case .imageToPdf: return "doc"
        case .mergePdf: return "arrow.triangle.merge"
        case .splitPdf: return "arrow.triangle.branch"
        case .compressPdf: return "arrow.down.right.and.arrow.up.left"
        case .watermarkPdf: return "textformat"
        case .rotatePdf: return "rotate.right"
        case .signPdf: return "signature"
        }
    }
}

private struct PrimaryAction: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isProcessing {
                ProgressView(value: viewModel.progress) {
                    Text(viewModel.processingStep.rawValue)
                }
            }
            Button {
                viewModel.startConversion()
            } label: {
                Label("Start Conversion", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing)

            Button {
                viewModel.addBatchSamples()
            } label: {
                Label("Prepare Batch Queue", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ResultPanel: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        if let result = viewModel.result {
            VStack(alignment: .leading, spacing: 8) {
                Label(result.outputName, systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(result.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if viewModel.selectedDocument == nil {
            ContentUnavailableView("No document selected", systemImage: "doc.badge.plus", description: Text("Choose a sample document or import a file to start."))
        }
    }
}

struct BatchView: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        NavigationStack {
            List {
                if viewModel.batchQueue.isEmpty {
                    ContentUnavailableView("Batch queue is empty", systemImage: "square.stack.3d.up", description: Text("Add sample files from the Convert tab."))
                } else {
                    ForEach(viewModel.batchQueue) { item in
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text("\(item.type.rawValue) - \(item.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: item.progress)
                        }
                    }
                }
            }
            .navigationTitle("Batch")
            .toolbar {
                Button("Run") { viewModel.runBatch() }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        NavigationStack {
            List {
                if viewModel.history.isEmpty {
                    ContentUnavailableView("No conversions yet", systemImage: "clock", description: Text("Completed files will appear here."))
                } else {
                    ForEach(viewModel.history) { item in
                        VStack(alignment: .leading) {
                            Text(item.outputName)
                            Text(item.type.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                Button("Clear") { viewModel.clearHistory() }
            }
        }
    }
}

struct ProSheet: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label("Convertory Pro", systemImage: "crown.fill")
                    .font(.title2.bold())
                Text("Unlock batch conversion, larger files, and unlimited daily exports.")
                    .foregroundStyle(.secondary)
                Button(viewModel.isPro ? "Disable Demo Pro" : "Enable Demo Pro") {
                    viewModel.isPro.toggle()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("Pro")
        }
    }
}

struct PrivacySheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label("Private by design", systemImage: "lock.shield.fill")
                    .font(.title2.bold())
                Text("The mobile workflow is designed for local processing and temporary cache storage. Add cloud sync only after an explicit product decision.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Privacy")
        }
    }
}
