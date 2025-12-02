import Foundation

/// Represents a position on the Go board
struct BoardPosition: Hashable, Codable {
    let row: Int
    let col: Int

    init(_ row: Int, _ col: Int) {
        self.row = row
        self.col = col
    }

    /// Create from SGF coordinates (e.g., "dd" for D4)
    init?(sgf: String, boardSize: Int) {
        guard sgf.count == 2 else { return nil }

        let chars = Array(sgf)
        guard let first = chars[0].asciiValue,
              let second = chars[1].asciiValue else {
            return nil
        }

        // SGF uses 'a' = 0, 'b' = 1, etc.
        let col = Int(first - Character("a").asciiValue!)
        let row = Int(second - Character("a").asciiValue!)

        guard col >= 0, col < boardSize,
              row >= 0, row < boardSize else {
            return nil
        }

        self.row = row
        self.col = col
    }

    /// Convert to human-readable coordinates (e.g., "D4")
    func toHumanReadable(boardSize: Int) -> String {
        let colChar = Character(UnicodeScalar(65 + col)!) // A, B, C...
        let rowNum = boardSize - row // 1-based from bottom

        // Skip 'I' in Go notation
        let adjustedCol = col >= 8 ? Character(UnicodeScalar(66 + col)!) : colChar

        return "\(adjustedCol)\(rowNum)"
    }
}
