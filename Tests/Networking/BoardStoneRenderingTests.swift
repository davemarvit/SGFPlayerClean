import XCTest
import SceneKit
@testable import SGFPlayerNetworking

final class BoardStoneRenderingTests: XCTestCase {
    func testPreviewNumbersRemainAttachedThroughSceneRefreshesAndClearOnRestoration() throws {
        let scene = SceneManager3D(); scene.updateBoardSize(9)
        let a = BoardPosition(2, 2), b = BoardPosition(3, 3)
        func labels() -> [SCNNode] {
            var labels: [SCNNode] = []
            scene.scene.rootNode.enumerateChildNodes { node, _ in
                if node.name == "ai-variation-number" { labels.append(node) }
            }
            return labels
        }
        render([a: .black], in: scene)
        let first = AIVariationFrame(stones: [a: .black], numbers: [a: 1], caption: "Preview")
        scene.updateVariationNumbers(frame: first)
        let label = try XCTUnwrap(labels().first)
        let stone = try XCTUnwrap(label.parent?.childNode(withName: "board-stone", recursively: false))
        let radius = try XCTUnwrap(stone.geometry as? SCNSphere).radius
        let labelHeight = Double(stone.position.y) + Double(radius) * Double(stone.scale.y) + 0.02
        XCTAssertEqual(Double(label.position.y), labelHeight, accuracy: 0.001)
        scene.updateVariationNumbers(frame: first)
        XCTAssertTrue(labels().first === label, "Ordinary refreshes must not remove and recreate visible numbers")
        render([a: .black, b: .white], in: scene)
        scene.updateVariationNumbers(frame: AIVariationFrame(stones: [a: .black, b: .white], numbers: [a: 1, b: 2], caption: "Preview"))
        XCTAssertEqual(labels().count, 2)
        XCTAssertTrue(labels().contains { $0 === label }, "Earlier numbers stay attached when the next stone lands")
        scene.updateVariationNumbers(frame: AIVariationFrame(stones: [a: .white, b: .white], numbers: [a: 3, b: 2], caption: "Preview"))
        let replacement = try XCTUnwrap(labels().first { ($0.geometry as? SCNText)?.string as? String == "3" })
        XCTAssertTrue((replacement.geometry?.firstMaterial?.diffuse.contents as? NSColor)?.isEqual(NSColor.black) == true)
        scene.updateVariationNumbers(frame: nil)
        XCTAssertTrue(labels().isEmpty)
    }

    func testAnalysisAnnotationsWaitForLandingAndNeverCastShadows() throws {
        let scene = SceneManager3D()
        let settings = AppSettings.shared
        let originalDrop = settings.showDropInAnimation
        settings.showDropInAnimation = true
        defer { settings.showDropInAnimation = originalDrop }
        let stone = RenderStone(id: BoardPosition(2, 2), color: .black, offset: .zero)
        let candidate = AIMoveInfo(move: "D4", visits: 100, winrate: 0.6, scoreLead: 2, pv: nil)
        func hints() {
            scene.updateAIHints(moves: [candidate], isAvailable: true, root: nil, nextMove: nil)
        }
        hints()
        scene.updateStones(from: [stone], lastMove: stone.id, moveIndex: 1, settings: settings, animate: true)
        XCTAssertTrue(try XCTUnwrap(scene.scene.rootNode.childNode(withName: "AI_HINT", recursively: true)).isHidden,
                      "Existing annotations hide as soon as placement starts")
        hints()
        let badge = try XCTUnwrap(scene.scene.rootNode.childNode(withName: "AI_HINT", recursively: true))
        XCTAssertTrue(badge.isHidden, "Streaming analysis must stay hidden during placement")
        XCTAssertFalse(badge.castsShadow)
        var textCount = 0
        badge.enumerateChildNodes { node, _ in
            XCTAssertFalse(node.castsShadow, "Annotations cannot project numbers onto a passing stone")
            if node.geometry is SCNText {
                textCount += 1
                XCTAssertEqual(node.geometry?.firstMaterial?.lightingModel, .constant)
            }
        }
        XCTAssertEqual(textCount, 2)
        scene.updateStones(from: [stone], lastMove: stone.id, moveIndex: 1, settings: settings, animate: false)
        XCTAssertFalse(badge.isHidden, "Cancelling animation restores values immediately")
        scene.updateAIHints(moves: [candidate], isAvailable: false, root: nil, nextMove: nil)
        XCTAssertNil(scene.scene.rootNode.childNode(withName: "AI_HINT", recursively: true), "Disabled AI stays clear")
    }

    private func render(_ stones: [BoardPosition: Stone], in scene: SceneManager3D) {
        scene.updateStones(from: stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) },
                           lastMove: nil, moveIndex: 0, settings: AppSettings.shared, animate: false)
    }

    private func assertColors(_ expected: [BoardPosition: Stone], in scene: SceneManager3D,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        var actual: [BoardPosition: SCNNode] = [:]
        scene.scene.rootNode.enumerateChildNodes { node, _ in
            // Actual board-stone meshes, excluding the ghost and the board geometry.
            guard node.name == "board-stone", node.categoryBitMask == 4,
                  node.geometry is SCNSphere, let anchor = node.parent else { return }
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
