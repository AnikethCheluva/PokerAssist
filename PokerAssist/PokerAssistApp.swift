import SwiftUI
import MWDATCamera
import MWDATCore

@main
struct PokerAssistApp: App {
    // We declare the property but don't initialize it yet
    @StateObject private var viewModel: WearablesManager
    @StateObject private var stream: StreamManager
    
    
    init() {
        // 1. Configure the SDK inside a proper do-catch block
        do {
            // Ensure you pass your bundle ID here if the SDK requires it
            try Wearables.configure()
            print("DAT SDK Configured Successfully")
        } catch {
            print("DAT SDK Configuration Failed: \(error.localizedDescription)")
        }
        
        // 2. Initialize the StateObject AFTER configuration
        // Note: Using a dummy identifier or shared instance as per your SDK requirements
        _viewModel = StateObject(wrappedValue: WearablesManager(wearables: Wearables.shared))
        _stream = StateObject(wrappedValue: StreamManager(wearables: Wearables.shared))
    } // Added missing closing brace for init
    
    var body: some Scene {
        WindowGroup {
            // Use the initialized viewModel and the shared wearables instance
            PokerMainView(wearables: Wearables.shared, viewModel: viewModel, stream: stream)
        }
    }
}
