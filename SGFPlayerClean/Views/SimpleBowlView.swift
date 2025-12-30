// MARK: - File: SimpleBowlView.swift (v6.400)
import SwiftUI

struct SimpleLidView: View {
    let stoneColor: Stone; let stoneCount: Int; let stoneSize: CGFloat; let lidNumber: Int; let lidSize: CGFloat
    var body: some View {
        ZStack {
            SafeImage(name: lidNumber == 1 ? "go_lid_1.png" : "go_lid_2.png", resizingMode: .stretch)
                .frame(width: lidSize, height: lidSize).shadow(color: .black.opacity(0.4), radius: 5, x: 2, y: 3)
            if stoneCount > 0 { LidStonesPile(color: stoneColor, count: min(stoneCount, 35), stoneSize: stoneSize, lidSize: lidSize) }
        }.frame(width: lidSize, height: lidSize)
    }
}
struct LidStonesPile: View {
    let color: Stone; let count: Int; let stoneSize: CGFloat; let lidSize: CGFloat
    var body: some View {
        let adjS = color == .black ? stoneSize * 1.015 : stoneSize * 0.995
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let off = getOff(i: i, r: lidSize * 0.3)
                StoneView2D(color: color, position: BoardPosition(0, 0), seedOverride: i * 7)
                    .frame(width: adjS, height: adjS).position(x: (lidSize / 2) + off.x, y: (lidSize / 2) + off.y)
            }
        }
    }
    private func getOff(i: Int, r: CGFloat) -> CGPoint {
        let a = Double(i) * 2.39996, d = r * sqrt(Double(i) / Double(count))
        return CGPoint(x: CGFloat(cos(a) * d), y: CGFloat(sin(a) * d))
    }
}
