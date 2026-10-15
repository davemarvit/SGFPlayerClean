import XCTest
@testable import SGFPlayerNetworking

final class SGFParserTests: XCTestCase {
    func testNestedContinuationRetainsAll132MovesAndPlayback() throws {
        // Same tree shape as the reported OGS export, without copying a user's game.
        let moves = (0..<132).map { index in
            let x = String(UnicodeScalar(97 + index % 19)!)
            let y = String(UnicodeScalar(97 + index / 19)!)
            return ";\(index.isMultiple(of: 2) ? "B" : "W")[\(x)\(y)]"
        }
        let text = "(;FF[4]SZ[19]RU[AGA]KM[7.5]" + moves.joined(separator: "(") + String(repeating: ")", count: 132)
        let game = SGFGame.from(tree: try SGFParser.parse(text: text))
        XCTAssertEqual(game.moves.count, 132)
        let player = SGFPlayer()
        player.load(game: game)
        XCTAssertEqual(player.maxIndex, 132)
        player.stepForward(); player.stepForward()
        XCTAssertEqual(player.currentIndex, 2)
        player.seek(to: 132)
        XCTAssertEqual(player.lastMove, MoveRef(color: .white, x: 17, y: 6))
        player.seek(to: 0)
        XCTAssertTrue(player.board.stones.isEmpty)
        XCTAssertEqual(player.maxIndex, 132)
    }

    func testFirstVariationContinuesMainLineWithoutAppendingAlternatives() throws {
        let tree = try SGFParser.parse(text: "(;SZ[9];B[aa](;W[bb](;B[cc];W[dd])(;B[ee]))(;W[ff];B[gg];W[hh];B[ii]))")
        let game = SGFGame.from(tree: tree)
        XCTAssertEqual(game.moves.count, 4)
        XCTAssertEqual(game.moves.compactMap { $0.1?.0 }, [0, 1, 2, 3])
    }

    func testCompleteVariationTreeSurvivesGameConversion() throws {
        let text = "(;SZ[9];B[aa](;W[bb]C[main](;B[cc])(;B[dd]N[alternative]LB[ee:A]))(;W[ff]C[other];B[gg]XX[private value]))"
        let game = SGFGame.from(tree: try SGFParser.parse(text: text))
        let tree = try XCTUnwrap(game.sourceTree)
        XCTAssertEqual(tree.branches.count, 5)
        XCTAssertEqual(tree.branches[0].children, [1, 4])
        XCTAssertEqual(tree.branches[1].children, [2, 3])
        XCTAssertEqual(tree.branches[3].sequence.first?.props["B"], ["dd"])
        XCTAssertEqual(tree.branches[3].sequence.first?.props["N"], ["alternative"])
        XCTAssertEqual(tree.branches[3].sequence.first?.props["LB"], ["ee:A"])
        XCTAssertEqual(tree.branches[4].sequence.first?.props["C"], ["other"])
        XCTAssertEqual(tree.branches[4].sequence.last?.props["XX"], ["private value"])
        XCTAssertEqual(game.moves.count, 3)
        XCTAssertEqual(game.moves.last?.1?.0, 2)
    }

    func testCommentsEscapesAndSiblingPropertiesCannotChangeTreeStructure() throws {
        let text = #"(;SZ[9]C[brackets \] and slash \\ (;W[zz\])];B[aa](;W[bb])(;W[cc]C[)))) (;B[dd\] malformed-looking text]))"#
        let tree = try SGFParser.parse(text: text)
        XCTAssertEqual(tree.mainLineNodes.first?.props["C"], [#"brackets ] and slash \ (;W[zz])"#])
        XCTAssertEqual(SGFGame.from(tree: tree).moves.count, 2)
        XCTAssertEqual(SGFGame.from(tree: tree).moves.last?.1?.0, 1)
    }

    func testSetupCommentsAndPassesAlongMainLine() throws {
        let game = SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[9]AB[aa][cc]PL[W]KM[0.5](;C[continuation];W[];B[dd];W[]))"))
        XCTAssertEqual(game.setup.count, 2)
        XCTAssertEqual(game.initialPlayer, .white)
        XCTAssertEqual(game.moves.count, 3)
        guard game.moves.count == 3 else { return }
        XCTAssertNil(game.moves[0].1)
        XCTAssertNil(game.moves[2].1)
    }

    func testMalformedTreesDoNotSilentlyLoadPartialGames() {
        for text in ["(;B[aa]", "(;B[aa", "(;B)", "()", "(;B[aa](;W[bb])", "(;B[aa](;W[bb]);B[cc])"] {
            XCTAssertThrowsError(try SGFParser.parse(text: text), text)
        }
    }

    func testDeepContinuationsDoNotRequireRecursiveStack() throws {
        let tree = try SGFParser.parse(text: String(repeating: "(;C[node]", count: 10_000) + String(repeating: ")", count: 10_000))
        XCTAssertEqual(tree.mainLineNodes.count, 10_000)
    }

    func testFirstGameInCollectionAndEscapedLineBreaks() throws {
        let tree = try SGFParser.parse(text: "\u{FEFF} (;SZ[9]C[one\\\r\ntwo\rthree];B[aa])(;SZ[19];W[bb])")
        XCTAssertEqual(tree.mainLineNodes.first?.props["C"], ["onetwo\nthree"])
        let game = SGFGame.from(tree: tree)
        XCTAssertEqual(game.boardSize, 9)
        XCTAssertEqual(game.moves.count, 1)
        XCTAssertEqual(game.moves.first?.0, .black)
    }
}
