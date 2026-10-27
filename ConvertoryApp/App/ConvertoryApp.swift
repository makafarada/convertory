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

    init() {
        // Navy bars to match the other Convertory apps.
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0, green: 0.071, blue: 0.161, alpha: 0.98)
        tab.shadowColor = UIColor(Theme.line)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.yellow)
                .environmentObject(router)
                .environmentObject(library)
                .onOpenURL { url in router.receive([url]) }
                .task {
                    #if DEBUG
                    if DemoSeed.isRequested { DemoSeed.apply(to: router) }
                    #endif
                    library.reload()
                }
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
        return Tool.suggestions(forExtension: router.incoming.first?.pathExtension ?? "")
    }
}
