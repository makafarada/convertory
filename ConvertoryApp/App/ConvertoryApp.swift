import SwiftUI

/// Files handed to Convertory from other apps ("Open in…" / share sheet), waiting for a tool choice.
@MainActor
final class Router: ObservableObject {
    @Published var path: [Tool] = []
    @Published var incoming: [URL] = []
    @Published var showChooser = false
    private(set) var pending: [URL] = []

    func receive(_ urls: [URL]) {
        let staged = urls.compactMap { try? Inbox.stage($0) }
        guard !staged.isEmpty else { return }
        incoming = staged
        showChooser = true
    }

    func open(_ tool: Tool) {
        pending = incoming
        incoming = []
        path = [tool]
    }

    func takePending() -> [URL] {
        defer { pending = [] }
        return pending
    }
}

@main
struct ConvertoryApp: App {
    @StateObject private var router = Router()
    @StateObject private var library = LibraryStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(library)
                .onOpenURL { url in router.receive([url]) }
                .task { library.reload() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var router: Router
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Tools", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            LibraryView()
                .tabItem { Label("Library", systemImage: "tray.full.fill") }
                .tag(1)
        }
        .onChange(of: router.path) { _, path in
            if !path.isEmpty { tab = 0 }
        }
        .confirmationDialog(chooserTitle, isPresented: $router.showChooser, titleVisibility: .visible) {
            ForEach(chooserTools) { tool in
                Button(tool.title) { router.open(tool) }
            }
            Button("Cancel", role: .cancel) { router.incoming = [] }
        }
    }

    private var chooserTitle: String {
        guard let first = router.incoming.first else { return "What would you like to do?" }
        return "What would you like to do with “\(first.lastPathComponent)”?"
    }

    private var chooserTools: [Tool] {
        let isPDF = router.incoming.first?.pathExtension.lowercased() == "pdf"
        return Tool.suggestions(forPDF: isPDF)
    }
}
