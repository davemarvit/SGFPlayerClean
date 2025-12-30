// MARK: - File: StoneView2D.swift (v8.100)
import SwiftUI

struct StoneView2D: View {
    let color: Stone; let position: BoardPosition; var seedOverride: Int? = nil
    init(color: Stone, position: BoardPosition = BoardPosition(0,0), seedOverride: Int? = nil) {
        self.color = color; self.position = position; self.seedOverride = seedOverride
    }
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35)).offset(x: 1.2, y: 1.2)
            if color == .black { SafeImage(name: "stone_black.png", resizingMode: .stretch) }
            else {
                let idx = ((seedOverride ?? (position.row * 31 + position.col)) % 5) + 1
                SafeImage(name: String(format: "clam_%02d.png", idx), resizingMode: .stretch)
            }
        }
    }
}
