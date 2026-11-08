import SwiftUI

/// Uses the desktop tree's branch columns and node identities; taps select a
/// position without creating or discarding variations.
struct TabletVariationTree: View {
    @ObservedObject var game: TabletGame
    var body: some View {
        DisclosureGroup("Variations") {
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            for node in game.tree.nodes {
                                if let parent = node.parent {
                                    path.move(to: point(parent))
                                    path.addLine(to: point(node.id))
                                }
                            }
                        }.stroke(.secondary.opacity(0.5), lineWidth: 1)
                        ForEach(game.tree.nodes) { node in
                            Button { game.select(node.id) } label: {
                                Text(node.isPass ? "P" : node.label)
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 36, height: 36)
                                    .background(node.color == .black ? Color.black : Color.white, in: Circle())
                                    .foregroundStyle(node.color == .black ? .white : .black)
                                    .overlay(Circle().stroke(game.tree.selectedID == node.id ? Color.cyan : .gray, lineWidth: game.tree.selectedID == node.id ? 3 : 1))
                                    .frame(width: 44, height: 44)
                            }.position(point(node.id)).id(node.id)
                                .accessibilityLabel("Move \(node.moveNumber)\(node.isPass ? ", pass" : "")")
                        }
                    }.frame(width: CGFloat(max(1, game.tree.columnCount)) * 48 + 44,
                            height: CGFloat((game.tree.nodes.map(\.depth).max() ?? 0) + 1) * 48 + 44)
                }.frame(height: 220)
                    .onChange(of: game.tree.selectedID) { _, id in proxy.scrollTo(id, anchor: .center) }
                    .onAppear { proxy.scrollTo(game.tree.selectedID, anchor: .center) }
            }
        }.accessibilityIdentifier("variationTree")
    }
    private func point(_ id: Int) -> CGPoint {
        CGPoint(x: CGFloat(game.tree.columns[id]) * 48 + 24,
                y: CGFloat(game.tree.nodes[id].depth) * 48 + 24)
    }
}
