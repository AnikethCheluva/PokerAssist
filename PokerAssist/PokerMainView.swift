import SwiftUI
import MWDATCore

struct PokerMainView: View {
    let wearables: WearablesInterface
    @ObservedObject private var viewModel: WearablesManager
    @ObservedObject var stream: StreamManager

    init(wearables: WearablesInterface, viewModel: WearablesManager, stream: StreamManager) {
        self.wearables = wearables
        self.viewModel = viewModel
        self.stream = stream
    }
    
    var body: some View {
        // FIX: Use ZStack to give the compiler a clearer container for inference
        ZStack {
            if viewModel.registrationState != .registered {
                RegistrationView(viewModel: viewModel)
            } else if !stream.isStreaming {
                PokerDashboardView(viewModel: viewModel, stream: stream)
            } else {
                StreamView(viewModel: viewModel, stream: stream)
            }
        }
        .onOpenURL { url in
            handleMetaCallback(url)
        }
    }

    private func handleMetaCallback(_ url: URL) {
        guard url.query?.contains("metaWearablesAction") == true else { return }
        Task {
            do {
                _ = try await wearables.handleUrl(url)
            } catch {
                viewModel.showError("Registration URL error: \(error.localizedDescription)")
            }
        }
    }
}
