// MARK: - File: SimpleBowlView.swift (v6.400)
import SwiftUI

/// The 2D presentation swaps small offline renders, never running a SceneKit view.
struct PlayerSupplyBowlView: View {
    @ObservedObject var player: SGFPlayer
    let stoneColor: Stone
    let size: CGFloat

    var body: some View {
        let counts = GoEquipment3D.supplyCounts(for: player)
        let remaining = stoneColor == .black ? counts.black : counts.white
        let colorName = stoneColor == .black ? "Black" : "White"
        Group {
            if let image = BowlImages2D.image(color: stoneColor, remaining: remaining) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 8, x: 10, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(colorName) supply bowl")
        .accessibilityValue("\(remaining) stones remaining")
        .accessibilityIdentifier(stoneColor == .black ? "black-supply-bowl" : "white-supply-bowl")
        .help("\(colorName) supply bowl")
    }
}

/// Limit decoded images to eight frames, even when scrubbing a long game.
enum BowlImages2D {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 512 * 512 * 4
        return cache
    }()

    static func image(color: Stone, remaining: Int) -> NSImage? {
        let count = min(color == .black ? 181 : 180, max(0, remaining))
        let name = "\(color == .black ? "black" : "white")-\(count)"
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Environments/Bowls2D"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: name as NSString, cost: 512 * 512 * 4)
        return image
    }
}

/// Observe the player directly: the parent AppModel does not forward nested board changes.
struct PlayerCaptureLidView: View {
    @ObservedObject var player: SGFPlayer
    let stoneColor: Stone
    let stoneSize: CGFloat
    let lidNumber: Int
    let lidSize: CGFloat

    var body: some View {
        SimpleLidView(stoneColor: stoneColor,
                      stoneCount: stoneColor == .black ? player.capturesByWhite : player.capturesByBlack,
                      stoneSize: stoneSize, lidNumber: lidNumber, lidSize: lidSize, seed: player.captureSeed)
    }
}

struct SimpleLidView: View {
    let stoneColor: Stone; let stoneCount: Int; let stoneSize: CGFloat; let lidNumber: Int; let lidSize: CGFloat
    var seed: UInt64 = 0
    var body: some View {
        ZStack {
            EquipmentSprite2D(name: lidNumber == 1 ? "go_lid_1.png" : "go_lid_2.png",
                              canvas: CGSize(width: 1024, height: 1024),
                              bodyBounds: lidNumber == 1
                                ? CGRect(x: 104, y: 80, width: 808, height: 829)
                                : CGRect(x: 85, y: 75, width: 851, height: 856))
                .frame(width: lidSize, height: lidSize).shadow(color: .black.opacity(0.4), radius: 8, x: 10, y: 10)
            if stoneCount > 0 { LidStonesPile(color: stoneColor, count: stoneCount, stoneSize: stoneSize, lidSize: lidSize, seed: seed) }
        }.frame(width: lidSize, height: lidSize)
            .overlay(alignment: .bottomTrailing) {
                Text("\(max(0, stoneCount))").font(.caption.bold()).monospacedDigit()
                    .padding(5).background(.regularMaterial, in: Capsule())
            }
            .accessibilityLabel("\(stoneColor == .black ? "Black" : "White") stones captured: \(max(0, stoneCount))")
    }
}
struct LidStonesPile: View {
    let color: Stone; let count: Int; let stoneSize: CGFloat; let lidSize: CGFloat
    var seed: UInt64 = 0
    var body: some View {
        let adjS = stoneSize * GoEquipmentDimensions2D.stoneDiameter(color) / GoEquipmentDimensions2D.blackStoneDiameter
        // The seeded layout was settled with stones 0.15 units across. Scale its
        // centres with the physical stone diameter, keeping existing pile spacing.
        let pileScale = stoneSize / max(lidSize, 1) / 0.15
        let pile = CapturePileLayout.stones(count: count,
            seed: CapturePileLayout.lidSeed(game: seed, whiteStones: color == .white))
        ZStack {
            ForEach(pile.indices, id: \.self) { i in
                let stone = pile[i]
                LidPileStoneView(color: color, stone: stone, size: adjS)
                    .position(x: lidSize * (0.5 + stone.x * pileScale), y: lidSize * (0.5 + stone.y * pileScale))
                    .zIndex(stone.height)
            }
        }
    }
}

private struct LidPileStoneView: View {
    let color: Stone
    let stone: CapturePileStone
    let size: CGFloat

    private var rotation: Angle { .degrees(stone.angle * 0.08 - 14.4) }

    private func shadow(diameter: CGFloat, opacity: Double, core: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: .black.opacity(opacity), location: 0),
                .init(color: .black.opacity(opacity), location: core),
                .init(color: .black.opacity(opacity * 0.4), location: core + (1 - core) * 0.5),
                .init(color: .clear, location: 1)
            ], center: .center, startRadius: 0, endRadius: size * diameter / 2))
            .frame(width: size * diameter, height: size * diameter)
            .scaleEffect(x: 1, y: stone.tilt)
            .rotationEffect(rotation)
    }

    var body: some View {
        ZStack {
            // Offset after rotation so every stone shares the lid's upper-left light.
            // Drawing each shadow with its stone lets it shade the lower stones too.
            // Gradients keep the soft edges at small sizes without offscreen blur passes.
            shadow(diameter: 1.35, opacity: 0.38, core: 0.55)
                .offset(x: size * 0.085, y: size * 0.11)
            shadow(diameter: 1.12, opacity: 0.58, core: 0.76)
                .offset(x: size * 0.025, y: size * 0.04)
            StoneView2D(color: color, seedOverride: Int(stone.angle) % 5, showsShadow: false)
                .frame(width: size, height: size)
                .scaleEffect(x: 1, y: stone.tilt)
                .rotationEffect(rotation)
        }
        .frame(width: size, height: size)
    }
}
