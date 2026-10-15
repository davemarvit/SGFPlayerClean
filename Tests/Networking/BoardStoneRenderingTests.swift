import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class BoardStoneRenderingTests: XCTestCase {
    private func render(_ stones: [BoardPosition: Stone], in scene: SceneManager3D) {
        scene.updateStones(from: stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) },
                           lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
    }

    private func assertColors(_ expected: [BoardPosition: Stone], in scene: SceneManager3D,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        var actual: [BoardPosition: SCNNode] = [:]
        scene.scene.rootNode.enumerateChildNodes { node, _ in
            // Actual board-stone meshes, excluding the ghost and the board geometry.
            guard node.categoryBitMask == 4, node.geometry is SCNSphere, let anchor = node.parent else { return }
            let column = Int(round((Double(anchor.position.x) + 9) / 2.25))
            let row = Int(round((Double(anchor.position.z) + 9 * 1.0773) / (2.25 * 1.0773)))
            actual[BoardPosition(row, column)] = node
        }
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        for (position, stone) in expected {
            let mesh = try XCTUnwrap(actual[position], file: file, line: line)
            let color = try XCTUnwrap((mesh.geometry?.firstMaterial?.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB), file: file, line: line)
            XCTAssertEqual(color.redComponent, stone == .black ? 0.02 : 1, accuracy: 0.001,
                           "Wrong rendered color at \(position)", file: file, line: line)
            let sphere = try XCTUnwrap(mesh.geometry as? SCNSphere, file: file, line: line)
            XCTAssertEqual(sphere.radius, 2.25 * 0.48 * (stone == .black ? 1 : 0.98), accuracy: 0.001,
                           "Wrong stone size at \(position)", file: file, line: line)
        }
    }

    func testExistingIntersectionCanChangeColorInBothDirectionsWithoutChangingOtherStones() throws {
        let scene = SceneManager3D(); scene.updateBoardSize(9)
        let a = BoardPosition(0, 0), b = BoardPosition(0, 1)
        for board: [BoardPosition: Stone] in [[a: .black, b: .white], [a: .white, b: .white], [a: .white, b: .black], [a: .black, b: .black]] {
            render(board, in: scene)
            try assertColors(board, in: scene)
        }
    }

    func testSwitchFromSuicideExampleToKoAndRewindKeepsEveryStoneColorCorrect() throws {
        let scene = SceneManager3D(); scene.updateBoardSize(9)
        let player = SGFPlayer()
        // A8 is white in the suicide example, but black in the ko example.
        for sgf in [
            "(;SZ[9]RU[New Zealand]AB[aa]AW[ab][bb][ca])",
            "(;SZ[9]RU[Japanese]AB[ba][ab][bc]AW[bb][ca][db][cc];B[cb])"
        ] {
            player.load(game: SGFGame.from(tree: try SGFParser.parse(text: sgf)))
            render(player.board.stones, in: scene)
            try assertColors(player.board.stones, in: scene)
        }
        for index in [1, 0, 1, 0] {
            player.seek(to: index)
            render(player.board.stones, in: scene)
            try assertColors(player.board.stones, in: scene)
        }
    }
}
