// MARK: - File: StoneView2D.swift (v8.100)
import SwiftUI

/// Place the visible body, rather than the padded source canvas, in the frame.
/// Bounds exclude baked shadows and stray edge pixels; the view supplies shadows.
struct EquipmentSprite2D: View {
    let name: String
    let canvas: CGSize
    let bodyBounds: CGRect

    var body: some View {
        GeometryReader { geometry in
            SafeImage(name: name, resizingMode: .stretch)
                .frame(width: geometry.size.width * canvas.width / bodyBounds.width,
                       height: geometry.size.height * canvas.height / bodyBounds.height)
                .offset(x: -geometry.size.width * bodyBounds.minX / bodyBounds.width,
                        y: -geometry.size.height * bodyBounds.minY / bodyBounds.height)
        }
        .clipped()
    }
}

struct StoneView2D: View {
    let color: Stone; let position: BoardPosition; var seedOverride: Int? = nil
    var showsShadow: Bool = true
    init(color: Stone, position: BoardPosition = BoardPosition(0,0), seedOverride: Int? = nil, showsShadow: Bool = true) {
        self.color = color; self.position = position; self.seedOverride = seedOverride
        self.showsShadow = showsShadow
    }
    var body: some View {
        ZStack {

            // Shadow: Larger and Softer
            if showsShadow {
                Circle().fill(Color.black.opacity(0.4)).offset(x: 2.7, y: 2.7).blur(radius: 3.0)
            }
            if color == .black {
                EquipmentSprite2D(name: "stone_black.png", canvas: CGSize(width: 1542, height: 1547),
                                  bodyBounds: CGRect(x: 24, y: 27, width: 1480, height: 1479))
                    .clipShape(Circle())
            }
            else {
                let idx = ((seedOverride ?? (position.row * 31 + position.col)) % 5) + 1
                let bounds = Self.whiteArtwork[idx - 1]
                EquipmentSprite2D(name: String(format: "clam_%02d.png", idx), canvas: bounds.0, bodyBounds: bounds.1)
                    .clipShape(Circle())
            }
        }
    }

    private static let whiteArtwork: [(CGSize, CGRect)] = [
        (CGSize(width: 1466, height: 1469), CGRect(x: 35, y: 28, width: 1408, height: 1405)),
        (CGSize(width: 1367, height: 1360), CGRect(x: 31, y: 25, width: 1301, height: 1303)),
        (CGSize(width: 1362, height: 1345), CGRect(x: 14, y: 17, width: 1311, height: 1318)),
        (CGSize(width: 1387, height: 1385), CGRect(x: 8, y: 4, width: 1369, height: 1373)),
        (CGSize(width: 500, height: 501), CGRect(x: 13, y: 10, width: 479, height: 478))
    ]
}
