import SwiftUI

/// Fit the raised seating lip, not the transparent image canvas, to the bowl.
/// Approximate lip diameters measured from the ridge in each 1024px lid image.
/// The bowl's 2.88-unit mouth radius is rendered across an 8-unit camera span.
enum TabletLidFit {
    static let bowlOpeningFraction: CGFloat = (2 * 2.88) / 8
    static let seatingClearance: CGFloat = 0.98

    static func lipFraction(for color: Stone) -> CGFloat {
        (color == .black ? 760 : 800) / 1024
    }

    static func canvasRatio(for color: Stone) -> CGFloat {
        bowlOpeningFraction * seatingClearance / lipFraction(for: color)
    }

    static func frame(in slot: CGRect, color: Stone) -> CGRect {
        let diameter = slot.width * canvasRatio(for: color)
        return CGRect(x: slot.midX - diameter / 2, y: slot.midY - diameter / 2,
                      width: diameter, height: diameter)
    }
}

/// Fit the board and four pieces of equipment without covering any intersections.
/// Use the window's orientation, so this also works in a resized iPad window.
struct TabletTableLayout {
    static let boardAspect: CGFloat = 1.0773
    let board: CGRect
    let whiteBowl: CGRect
    let blackBowl: CGRect
    let whiteCaptures: CGRect
    let blackCaptures: CGRect

    init(size: CGSize, portrait: Bool) {
        let inset: CGFloat = 12, gap: CGFloat = 10, ratio: CGFloat = 0.20
        let width = max(0, size.width - inset * 2)
        let height = max(0, size.height - inset * 2)
        let boardWidth = max(0, portrait ? min(width, (height - gap * 2) / (Self.boardAspect + ratio * 2))
                                        : min(height / Self.boardAspect, (width - gap * 2) / (1 + ratio * 2)))
        let boardHeight = boardWidth * Self.boardAspect
        let diameter = boardWidth * ratio
        board = CGRect(x: (size.width - boardWidth) / 2, y: (size.height - boardHeight) / 2, width: boardWidth, height: boardHeight)
        let left = portrait ? board.minX : board.minX - gap - diameter
        let right = portrait ? board.maxX - diameter : board.maxX + gap
        let top = portrait ? board.minY - gap - diameter : board.minY
        let bottom = portrait ? board.maxY + gap : board.maxY - diameter
        whiteBowl = CGRect(x: left, y: top, width: diameter, height: diameter)
        blackCaptures = TabletLidFit.frame(in: CGRect(x: right, y: top, width: diameter, height: diameter), color: .black)
        whiteCaptures = TabletLidFit.frame(in: CGRect(x: left, y: bottom, width: diameter, height: diameter), color: .white)
        blackBowl = CGRect(x: right, y: bottom, width: diameter, height: diameter)
    }

    func intersection(at point: CGPoint, boardSize: Int) -> BoardPosition? {
        guard board.width > 0, boardSize > 1, board.contains(point) else { return nil }
        let col = Int(((point.x - board.minX - board.width * 0.065) / (board.width * 0.87) * CGFloat(boardSize - 1)).rounded())
        let row = Int(((point.y - board.minY - board.height * 0.065) / (board.height * 0.87) * CGFloat(boardSize - 1)).rounded())
        guard (0..<boardSize).contains(row), (0..<boardSize).contains(col) else { return nil }
        return BoardPosition(row, col)
    }
}

@MainActor enum TabletBowlImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 512 * 512 * 4
        return cache
    }()
    static func image(color: Stone, remaining: Int) -> UIImage? {
        let count = max(0, min(color == .black ? 181 : 180, remaining))
        let name = "\(color == .black ? "black" : "white")-\(count)"
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Environments/Bowls2D"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString, cost: 512 * 512 * 4)
        return image
    }
}

struct TabletEquipment: View {
    @ObservedObject var player: SGFPlayer
    let layout: TabletTableLayout

    var body: some View {
        let counts = GoEquipment3D.supplyCounts(for: player)
        ZStack(alignment: .topLeading) {
            bowl(.white, count: counts.white, rect: layout.whiteBowl)
            bowl(.black, count: counts.black, rect: layout.blackBowl)
            lid(.white, count: player.capturesByBlack, rect: layout.whiteCaptures)
            lid(.black, count: player.capturesByWhite, rect: layout.blackCaptures)
        }
    }

    private func bowl(_ color: Stone, count: Int, rect: CGRect) -> some View {
        Group {
            if let image = TabletBowlImages.image(color: color, remaining: count) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .frame(width: rect.width, height: rect.height)
        .shadow(color: .black.opacity(0.4), radius: 4, x: 4, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(color == .black ? "Black" : "White") supply bowl")
        .accessibilityIdentifier(color == .black ? "black-supply-bowl" : "white-supply-bowl")
        .position(x: rect.midX, y: rect.midY)
    }

    private func lid(_ color: Stone, count: Int, rect: CGRect) -> some View {
        let pile = CapturePileLayout.stones(count: count, seed: CapturePileLayout.lidSeed(game: player.captureSeed, whiteStones: color == .white))
        return ZStack {
            if let image = UIImage(named: color == .black ? "go_lid_1.png" : "go_lid_2.png") {
                Image(uiImage: image).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 4, y: 5)
            }
            ForEach(pile.indices, id: \.self) { index in
                let stone = pile[index]
                let texture = color == .black ? "stone_black.png" : String(format: "clam_%02d.png", Int(stone.angle) % 5 + 1)
                if let image = UIImage(named: texture) {
                    Image(uiImage: image).resizable().scaledToFit()
                    // Resizing the wooden lid must not shrink its captured stones.
                    .frame(width: layout.blackBowl.width * 0.17, height: layout.blackBowl.width * 0.17)
                    .scaleEffect(x: 1, y: stone.tilt)
                    .rotationEffect(.degrees(stone.angle * 0.08 - 14.4))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 2)
                    .position(x: rect.width * (0.5 + stone.x), y: rect.height * (0.5 + stone.y))
                    .zIndex(stone.height)
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .bottomTrailing) { badge("\(count)") }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(color == .black ? "Black" : "White") stones captured")
        .accessibilityValue("\(count)")
        .accessibilityIdentifier(color == .black ? "black-capture-lid" : "white-capture-lid")
        .position(x: rect.midX, y: rect.midY)
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
    }
}
