import Foundation
import SwiftUI
import Vision
import MWDATCore

// MARK: - Models

struct ServerDetection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect // Normalized 0.0 - 1.0
}

// MARK: - StreamView

struct StreamView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: WearablesManager
    @ObservedObject var stream: StreamManager

    @State private var handCards: [Card] = []
    @State private var boardCards: [Card] = []
    @State private var playerCount: Int = 2
    @State private var isStreamVisible: Bool = true
    @State private var pokerStats = PokerStats(winProbability: 0, nextBestHandChance: 0, currentRank: "Waiting...")
    
    @State private var debugObservations: [ServerDetection] = []

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    if isStreamVisible {
                        streamHeader
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            analyticsSection
                            cardSection(title: "Your Private Hand", cards: handCards, accentColor: .blue, max: 2, subtitle: "Click 'Snap Hand' to capture")
                            cardSection(title: "Community Board", cards: boardCards, accentColor: .orange, max: 5, subtitle: "Scanning automatically...")
                            Color.clear.frame(height: 140)
                        }
                        .padding()
                    }
                }

                navigationControlBar
            }
            .navigationTitle("Poker Assist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { withAnimation(.spring()) { isStreamVisible.toggle() } }) {
                        Image(systemName: isStreamVisible ? "video.fill" : "video.slash.fill")
                            .foregroundColor(isStreamVisible ? .blue : .secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    statusIndicator
                }
            }
        }
        .onAppear { setupDetectionCallback() }
    }

    private var streamHeader: some View {
        ZStack(alignment: .center) {
            Color.black
            
            if let frame = stream.currentVideoFrame {
                Image(uiImage: frame)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 240, height: 240)
                    .overlay(boundingBoxOverlay)
                    .overlay(alignment: .topLeading) {
                        telemetryBadge(for: frame.size)
                    }
            } else {
                placeholderView
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    streamingStatusBadge
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 350)
        .background(Color.black)
    }

    private func telemetryBadge(for size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(size.width))px × \(Int(size.height))px")
            Text("Ping: \(String(format: "%.0f", stream.lastInferenceTime))ms")
                .foregroundColor(stream.lastInferenceTime > 150 ? .orange : .green)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
        .padding(6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
        .padding(8)
    }

    private var boundingBoxOverlay: some View {
        GeometryReader { geo in
            ForEach(debugObservations) { detection in
                let width = detection.boundingBox.width * geo.size.width
                let height = detection.boundingBox.height * geo.size.height
                let x = detection.boundingBox.minX * geo.size.width
                let y = detection.boundingBox.minY * geo.size.height
                
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: width, height: height)
                    
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.system(size: 8, weight: .black))
                        .padding(2)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .offset(y: -12)
                }
                .offset(x: x, y: y)
            }
        }
    }

    // MARK: - FIXED Logic Pipeline
    private func setupDetectionCallback() {
        stream.onCardsFound = { serverDetections in
            let uiDetections = serverDetections.map { det in
                ServerDetection(
                    label: det.label,
                    confidence: Float(det.confidence),
                    boundingBox: CGRect(x: det.bbox.x1, y: det.bbox.y1,
                                      width: det.bbox.x2 - det.bbox.x1,
                                      height: det.bbox.y2 - det.bbox.y1)
                )
            }
            
            Task { @MainActor in
                self.debugObservations = uiDetections
                
                for det in serverDetections {
                    // FIX: Pass all required arguments to Card.from
                    if let card = Card.from(label: det.label, confidence: det.confidence, yCoord: det.bbox.y1) {
                        let isDuplicate = handCards.contains(where: { $0.id == card.id }) ||
                                          boardCards.contains(where: { $0.id == card.id })
                        
                        // Continuous board scanning
                        if !isDuplicate && boardCards.count < 5 {
                            withAnimation(.spring()) { boardCards.append(card) }
                        }
                    }
                }
                updateOdds()
            }
        }

        stream.onHandCaptureReady = { handDetections in
            Task { @MainActor in
                var newHand: [Card] = []
                for det in handDetections {
                    // FIX: Pass all required arguments to Card.from
                    if let card = Card.from(label: det.label, confidence: det.confidence, yCoord: det.bbox.y1) {
                        newHand.append(card)
                    }
                }
                self.handCards = Array(newHand.prefix(2))
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                updateOdds()
            }
        }
    }

    private func updateOdds() {
        Task {
            let stats = await PokerEngine.calculateOdds(hand: handCards, board: boardCards, playerCount: playerCount)
            await MainActor.run { self.pokerStats = stats }
        }
    }

    // MARK: - Navigation Control Bar
    private var navigationControlBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    Button(action: { stream.captureHand() }) {
                        Label("Snap Hand", systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!stream.isStreaming)
                    
                    Button(action: {
                        withAnimation {
                            handCards.removeAll()
                            boardCards.removeAll()
                            debugObservations.removeAll()
                        }
                    }) {
                        Image(systemName: "trash").padding(12).padding(.horizontal, 10)
                    }.buttonStyle(.bordered)
                }

                HStack(spacing: 15) {
                    Button(action: {
                        if stream.isStreaming { Task { await stream.stopSession() } }
                        else { Task { await stream.handleStartStreaming() } }
                    }) {
                        Label(stream.isStreaming ? "Stop" : "Start", systemImage: stream.isStreaming ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.bordered).tint(stream.isStreaming ? .red : .green)

                    Stepper("Players: \(playerCount)", value: $playerCount, in: 2...9).font(.caption.bold())
                }
            }
            .padding().background(.ultraThinMaterial).cornerRadius(24).padding()
        }
    }

    // MARK: - Dashboard Components
    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("PROBABILITY INSIGHTS").font(.caption2.bold()).foregroundColor(.secondary)
            HStack(spacing: 12) {
                statBox(title: "WIN CHANCE", value: String(format: "%.0f%%", pokerStats.winProbability * 100), color: .green, icon: "chart.line.uptrend.xyaxis")
                statBox(title: "OUTS %", value: String(format: "%.0f%%", pokerStats.nextBestHandChance * 100), color: .purple, icon: "rectangle.stack")
            }
            HStack {
                Text("Current Rank:").font(.subheadline).foregroundColor(.secondary)
                Text(pokerStats.currentRank).font(.headline).foregroundColor(.primary)
                Spacer()
            }
            .padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(12)
        }
    }

    private func cardSection(title: String, cards: [Card], accentColor: Color, max: Int, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text("\(cards.count)/\(max)").font(.caption).foregroundColor(.secondary)
                }
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if cards.isEmpty { emptyCardPlaceholder }
                    else { ForEach(cards) { card in cardPill(card) } }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var statusIndicator: some View {
        HStack {
            Circle().fill(viewModel.linkStatus == .connected ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(viewModel.linkStatus == .connected ? "Active" : "Offline").font(.caption2).bold()
        }
    }

    private var placeholderView: some View {
        VStack {
            Image(systemName: "camera.metering.unknown").font(.largeTitle)
            Text("Waiting for feed...").font(.caption)
        }.foregroundColor(.white.opacity(0.4))
    }

    private var streamingStatusBadge: some View {
        Text(stream.streamingStatus == .streaming ? "LIVE" : "PAUSED")
            .font(.system(size: 10, weight: .black))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(stream.streamingStatus == .streaming ? Color.red : Color.gray)
            .foregroundColor(.white).cornerRadius(4).padding(12)
    }

    private func cardPill(_ card: Card) -> some View {
        VStack(spacing: 4) {
            Text(card.rank).font(.title3).bold()
            Text(symbol(for: card.suit)).font(.title)
        }
        .foregroundColor(suitColor(for: card.suit))
        .frame(width: 65, height: 95)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12).shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var emptyCardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
            .frame(width: 60, height: 85).overlay(Image(systemName: "plus").foregroundColor(.gray))
    }

    private func statBox(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).font(.caption); Text(title).font(.caption2.bold()) }.foregroundColor(color)
            Text(value).font(.system(.title, design: .rounded)).fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding().background(color.opacity(0.1)).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private func suitColor(for suit: Suit) -> Color {
        suit == .hearts || suit == .diamonds ? .red : (colorScheme == .dark ? .white : .black)
    }
    
    private func symbol(for suit: Suit) -> String {
        switch suit { case .hearts: return "♥"; case .diamonds: return "♦"; case .clubs: return "♣"; case .spades: return "♠" }
    }
}
