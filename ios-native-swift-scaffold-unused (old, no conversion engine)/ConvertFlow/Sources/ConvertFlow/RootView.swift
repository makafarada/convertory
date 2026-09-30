import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: ConvertFlowViewModel

    var body: some View {
        AdBannerContainer(isPro: viewModel.isPro) {
            TabView(selection: $viewModel.route) {
                ConvertView()
                    .tabItem { Label("Convert", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(AppRoute.convert)
                BatchView()
                    .tabItem { Label("Batch", systemImage: "square.stack.3d.up") }
                    .tag(AppRoute.batch)
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    .tag(AppRoute.history)
            }
            .tint(.cyan)
            .sheet(isPresented: $viewModel.showProSheet) { ProSheet() }
            .sheet(isPresented: $viewModel.showPrivacySheet) { PrivacySheet() }
            .alert("Convertory", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
