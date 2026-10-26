import SwiftUI
import PhotosUI

struct ToolScreen: View {
    @EnvironmentObject private var router: Router
    @StateObject private var model: ToolModel
    @State private var showFiles = false
    @State private var showScanner = false
    @State private var photoSelection: [PhotosPickerItem] = []

    init(tool: Tool) {
        _model = StateObject(wrappedValue: ToolModel(tool: tool))
    }

    private var tool: Tool { model.tool }

    var body: some View {
        ZStack {
            ScreenBackground()
            content
            if model.busy {
                BusyOverlay(progress: model.progress, title: model.items.isEmpty && model.pageEdits.isEmpty ? "Opening…" : "Working…")
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    if tool.allowsMultiple { EditButton() } else { Button("Clear") { model.clear() } }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .fileImporter(isPresented: $showFiles,
                      allowedContentTypes: tool.input.contentTypes,
                      allowsMultipleSelection: tool.allowsMultiple) { result in
            if case .success(let urls) = result { model.add(urls: urls) }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner(
                onFinish: { images in
                    showScanner = false
                    model.add(scannedPages: images)
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoSelection) { _, selection in
            guard !selection.isEmpty else { return }
            model.add(photos: selection)
            photoSelection = []
        }
        .navigationDestination(item: $model.result) { ResultView(file: $0) }
        .alert("Convertory", isPresented: Binding(get: { model.message != nil },
                                                   set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
        .onAppear {
            let waiting = router.takePending()
            if !waiting.isEmpty { model.add(urls: waiting) }
            if tool == .scan && model.items.isEmpty && DocumentScanner.isAvailable { showScanner = true }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if tool == .organize && !model.pageEdits.isEmpty {
            OrganizerView(model: model)
        } else if model.items.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(model.items) { ItemRow(item: $0) }
                        .onDelete { offsets in if tool.allowsMultiple { model.remove(at: offsets) } }
                        .onMove { source, destination in
                            if tool.allowsMultiple { model.move(from: source, to: destination) }
                        }
                } header: {
                    if tool.allowsMultiple { Text("\(model.items.count) in order") }
                } footer: {
                    if tool.minimumItems > model.items.count {
                        Text("Add at least \(tool.minimumItems) files.")
                    }
                }
                .listRowBackground(Theme.card)

                if tool.allowsMultiple { addMoreSection }
                optionsSection
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            SymbolTile(symbol: tool.symbol, tint: tool.tint, size: 72)
            Text(tool.tagline)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(tool.emptyHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                addButtons
            }
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private var addButtons: some View {
        if tool.input == .images {
            if DocumentScanner.isAvailable {
                Button { showScanner = true } label: {
                    Label("Scan with camera", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 40, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        if tool.input == .images {
            Button { showFiles = true } label: {
                Label("Choose from Files", systemImage: "folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        } else {
            Button { showFiles = true } label: {
                Label("Choose from Files", systemImage: "folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var addMoreSection: some View {
        Section {
            if tool.input == .images {
                if DocumentScanner.isAvailable {
                    Button { showScanner = true } label: { Label("Scan more pages", systemImage: "camera.viewfinder") }
                }
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 40, matching: .images) {
                    Label("Add from Photos", systemImage: "photo.on.rectangle")
                }
            }
            Button { showFiles = true } label: { Label("Add from Files", systemImage: "folder.badge.plus") }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: Options

    @ViewBuilder
    private var optionsSection: some View {
        switch tool {
        case .scan, .imagesToPDF:
            Section("Page") {
                Picker("Page size", selection: $model.layout) {
                    ForEach(PageLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Make text searchable", isOn: $model.searchable)
            }
            .listRowBackground(Theme.card)
        case .watermark:
            Section("Watermark") {
                TextField("Text on every page", text: $model.watermarkText)
                    .textInputAutocapitalization(.characters)
                Picker("Style", selection: $model.watermarkStyle) {
                    ForEach(WatermarkStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Strength")
                    Slider(value: $model.watermarkOpacity, in: 0.08...0.6)
                }
            }
            .listRowBackground(Theme.card)
        case .compress:
            Section {
                Picker("Quality", selection: $model.compressLevel) {
                    ForEach(CompressLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Quality")
            } footer: {
                Text("\(model.compressLevel.detail). Pages are re-rendered as images, so text is no longer selectable in the compressed copy.")
            }
            .listRowBackground(Theme.card)
        case .pdfToWord:
            Section {} footer: {
                Text("Headings, bold text and paragraphs are rebuilt as editable Word text. Pictures and complex layouts are not carried over. Scanned pages are read with text recognition.")
            }
        case .extractText:
            Section {} footer: {
                Text("Pages without a text layer and pictures are read with on-device text recognition.")
            }
        case .merge, .organize:
            EmptyView()
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if !model.items.isEmpty {
            VStack(spacing: 0) {
                Button { model.run() } label: {
                    Text(tool.actionTitle).font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canRun)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Theme.paper.opacity(0.96))
        }
    }
}

private struct ItemRow: View {
    let item: InputItem

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: item.isPDF ? "doc" : "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 42, height: 54)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
