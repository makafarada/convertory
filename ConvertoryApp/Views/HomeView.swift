import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: Router
    @State private var showAbout = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NavigationLink(value: Tool.scan) { HeroCard() }
                        .buttonStyle(.plain)

                    section("Make a PDF", tools: [.imagesToPDF, .merge])
                    section("Edit a PDF", tools: [.organize, .watermark, .compress])
                    section("Get the content out", tools: [.extractText, .pdfToWord])

                    Label("Everything runs on this device. No account, no ads, no uploads.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .navigationTitle("Convertory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About Convertory")
                }
            }
            .navigationDestination(for: Tool.self) { ToolScreen(tool: $0) }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }

    private func section(_ title: String, tools: [Tool]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tools) { tool in
                    NavigationLink(value: tool) { ToolCard(tool: tool) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HeroCard: View {
    var body: some View {
        HStack(spacing: 16) {
            SymbolTile(symbol: Tool.scan.symbol, tint: Tool.scan.tint, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Scan a document")
                    .font(.title3.weight(.semibold))
                Text("Point the camera at a page. Convertory crops it, reads the words and saves a searchable PDF.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Tool.scan.tint.opacity(0.8), lineWidth: 1.5))
    }
}

private struct ToolCard: View {
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SymbolTile(symbol: tool.symbol, tint: tool.tint)
            Text(tool.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(tool.tagline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
