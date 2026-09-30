import SwiftUI

@main
struct ConvertFlowApp: App {
    @StateObject private var viewModel = ConvertFlowViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
        }
    }
}
