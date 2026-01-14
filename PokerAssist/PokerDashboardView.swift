import SwiftUI
import MWDATCore

struct PokerDashboardView: View {
    @ObservedObject var viewModel: WearablesManager
    @ObservedObject var stream: StreamManager
    @State private var showingSettings = false
    
    var statusColor: Color {
        switch viewModel.linkStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        default: return .red
        }
    }

    var statusText: String {
        switch viewModel.linkStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        default: return "Disconnected"
        }
    }
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Connection Status & Quick Stats
                        HStack(spacing: 15) {
                            StatCard(title: "Bankroll", value: "$12,450", icon: "dollarsign.circle.fill", color: .green)
                            StatCard(title: "Win Rate", value: "64%", icon: "chart.line.uptrend.xyaxis", color: .blue)
                        }
                        .padding(.horizontal)

                        // 2. Active Session / Start Game Card
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Current Session")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 12) {
                                DashboardButton(title: "Start New Game", icon: "play.fill", color: .green) {
                                    Task {
                                        await stream.handleStartStreaming()
                                    }
                                }
                                
                                DashboardButton(title: "Resume Last Session", icon: "arrow.clockwise", color: .orange) {
                                    print("Resuming...")
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(15)
                        .padding(.horizontal)

                        // 3. Player Insights Table
                        VStack(alignment: .leading) {
                            Text("Recent Performance")
                                .font(.headline)
                                .padding(.leading)
                            
                            VStack(spacing: 0) {
                                PlayerRow(label: "Hands Played", value: "1,240")
                                Divider().padding(.horizontal)
                                PlayerRow(label: "VPIP", value: "22%")
                                Divider().padding(.horizontal)
                                PlayerRow(label: "Aggression Factor", value: "3.1")
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(15)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Poker Assist")
            .toolbar {
                // Glass Connection Badge
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption).bold()
                    }
                }
                
                // Settings & Menu
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingSettings = true }) {
                            Label("Settings", systemImage: "gear")
                        }
                        Button(action: { /* History Logic */ }) {
                            Label("Hand History", systemImage: "clock.arrow.circlepath")
                        }
                        Divider()
                        Button(role: .destructive, action: { viewModel.unregisterGlasses() }) {
                            Label("Unpair Glasses", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            Text(value)
                .font(.title2).bold()
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct DashboardButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
}

struct PlayerRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold()
        }
        .padding()
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("HUD Settings") {
                    Toggle("Show Win Probability", isOn: .constant(true))
                    Toggle("Opponent Tendencies", isOn: .constant(false))
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Preview
//#Preview {
//    PokerDashboardView(viewModel: WearablesManager(wearables: Wearables.shared, stream: StreamManager))
//}
