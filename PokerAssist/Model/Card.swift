import Foundation

// MARK: - Models

enum Suit: String, CaseIterable {
    case hearts = "Hearts"
    case diamonds = "Diamonds"
    case clubs = "Clubs"
    case spades = "Spades"
}

enum CardLocation: String {
    case hand = "Hand"
    case board = "Board"
}

struct Card: Equatable, Identifiable {
    var id: String { "\(rank)\(suit.rawValue)" }
    let rank: String
    let suit: Suit
    var location: CardLocation
    let y: Double

    static func == (lhs: Card, rhs: Card) -> Bool {
        return lhs.rank == rhs.rank && lhs.suit == rhs.suit
    }
    
    /// Fixed Helper: Now correctly accepts the BBox struct and confidence
    static func from(label: String, confidence: Double, yCoord: Double) -> Card? {
        guard label.count >= 2 else { return nil }
        
        let suitChar = String(label.last ?? " ").uppercased()
        let suit: Suit
        switch suitChar {
            case "H": suit = .hearts
            case "D": suit = .diamonds
            case "C": suit = .clubs
            case "S": suit = .spades
            default: return nil
        }
        
        let rank = String(label.dropLast()).uppercased()
        
        // Logical Split: If the card is in the bottom 35% of the 720x720 crop, it's likely the player's hand
        let location: CardLocation = (yCoord > 0.65) ? .hand : .board
        
        return Card(
            rank: rank,
            suit: suit,
            location: location,
            y: yCoord
        )
    }
}
