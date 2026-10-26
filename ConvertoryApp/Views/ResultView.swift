import SwiftUI

struct ResultView: View {
    let file: LibraryFile
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            preview
            footer
        }
        .navigationTitle(file.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: file.url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
            }
        }
        .task {
            if file.kind == .text {
                text = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch file.kind {
        case .pdf:
            PDFPreview(url: file.url)
        case .word:
            QuickLookPreview(url: file.url)
        case .text:
            ScrollView {
                Text(text.isEmpty ? "No text was found." : text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Theme.paper)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Saved in Files › Convertory · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 10) {
                ShareLink(item: file.url) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if file.kind == .text {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(text.isEmpty)
                }
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.bar)
    }
}
