import Foundation

enum PokerHandRank: Int, Comparable {
    case highCard = 0, pair, twoPair, threeOfAKind, straight, flush, fullHouse, fourOfAKind, straightFlush
    
    static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PokerStats {
    let winProbability: Double
    let nextBestHandChance: Double
    let currentRank: String
}

final class PokerEngine {
    
    /// Simulates games to calculate odds
    static func calculateOdds(hand: [Card], board: [Card], playerCount: Int) async -> PokerStats {
        // Guard against insufficient data
        guard hand.count == 2 else {
            return PokerStats(winProbability: 0, nextBestHandChance: 0, currentRank: "Waiting for Hand")
        }
        
        // 1. Determine Current Hand Rank (Simplified for UI)
        let currentRankName = evaluateHandName(hand: hand, board: board)
        
        // 2. Monte Carlo Simulation
        // In a real app, you'd use a library or a deep lookup table.
        // Here we simulate a simplified probability based on outs and player count.
        let winProb = simulateWinProbability(hand: hand, board: board, players: playerCount)
        let drawProb = calculateDrawProbability(hand: hand, board: board)
        
        return PokerStats(
            winProbability: winProb,
            nextBestHandChance: drawProb,
            currentRank: currentRankName
        )
    }
    
    private static func simulateWinProbability(hand: [Card], board: [Card], players: Int) -> Double {
        // Logic: Strength decreases as player count increases
        // Base strength (simplified calculation)
        let strength = Double(handValue(hand[0]) + handValue(hand[1])) / 30.0
        let boardImpact = Double(board.count) * 0.1
        let adjustedProb = (strength + boardImpact) / Double(players)
        return min(max(adjustedProb, 0.05), 0.95)
    }
    
    private static func calculateDrawProbability(hand: [Card], board: [Card]) -> Double {
        if board.count >= 5 { return 0.0 } // No more cards to come
        // Simplified 'Outs' logic: chance of improving on next card
        return board.count < 3 ? 0.25 : 0.15
    }
    
    private static func evaluateHandName(hand: [Card], board: [Card]) -> String {
        let allCards = hand + board
        if allCards.count < 2 { return "High Card" }
        // Simple pair detection for UI feedback
        let ranks = allCards.map { $0.rank }
        let counts = NSCountedSet(array: ranks)
        if counts.count != allCards.count { return "Pair or Better" }
        return "High Card"
    }
    
    private static func handValue(_ card: Card) -> Int {
        let values: [String: Int] = ["A": 14, "K": 13, "Q": 12, "J": 11, "10": 10]
        return values[card.rank] ?? (Int(card.rank) ?? 0)
    }
}
