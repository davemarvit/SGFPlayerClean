import XCTest
@testable import SGFPlayerNetworking

final class ReviewTreeTests: XCTestCase {
    private func document(_ text: String) throws -> ReviewTree {
        ReviewTree(game: SGFGame.from(tree: try SGFParser.parse(text: text)), analysisID: "fixture", filename: "fixture.sgf")
    }
    private func sameTree(_ a: SGFTree, _ b: SGFTree, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.branches.count, b.branches.count, file: file, line: line)
        for (x, y) in zip(a.branches, b.branches) {
            XCTAssertEqual(x.children, y.children, file: file, line: line)
            XCTAssertEqual(x.sequence.map(\.props), y.sequence.map(\.props), file: file, line: line)
        }
    }
    func testWriterPreservesBranchesCommentsAndUnknownProperties() throws {
        let sgf = #"(;CA[UTF-8]SZ[9]C[日本語 and \] and \\];B[aa](;W[]C[pass](;B[cc])(;B[dd]XX[private][two]LB[ee:A]))(;W[ff];C[comment];B[gg]))"#
        let original = try SGFParser.parse(text: sgf)
        var tree = try document(sgf)
        let saved = SGFWriter.serialize(tree.source)
        for node in tree.nodes { tree.select(node.id) }
        XCTAssertEqual(SGFWriter.serialize(tree.source), saved, "Navigation must not change document")
        sameTree(original, try SGFParser.parse(text: saved))
        sameTree(original, try SGFParser.parse(text: SGFWriter.serialize(try SGFParser.parse(text: saved))))
        let legacy = try SGFParser.parse(text: "(;CA[ISO-8859-1]C[é])")
        XCTAssertTrue(SGFWriter.serialize(legacy).contains("CA[UTF-8]"))
    }
    func testNavigationAndLayout() throws {
        var tree = try document("(;SZ[9];B[aa](;W[bb];C[note];B[])(;W[cc](;B[dd])(;B[ee])))")
        XCTAssertEqual(tree.activePath, [0,1,2,3,4])
        XCTAssertEqual(tree.nodes.map(\.moveNumber), [0,1,2,2,3,2,3,3])
        tree.select(7)
        XCTAssertEqual(tree.activePath, [0,1,5,7])
        XCTAssertFalse(tree.isMainLine)
        XCTAssertEqual(tree.neighbor(direction: -1), 5)
        XCTAssertEqual(tree.sibling(direction: -1), 6)
        tree.select(5)
        XCTAssertEqual(tree.neighbor(direction: 1), 7)
        XCTAssertEqual(tree.sibling(direction: -1), 2)
        tree.select(3); tree.followPlayback(index: 2)
        XCTAssertEqual(tree.selectedID, 3, "Explicit comment selection survives sync")
        tree.followPlayback(index: 3)
        XCTAssertEqual(tree.selectedID, 4)
        XCTAssertTrue(tree.nodes[4].isPass)
        XCTAssertTrue(tree.isMainLine)
        for row in tree.rows { XCTAssertEqual(Set(row.map { tree.columns[$0] }).count, row.count) }
        for node in tree.nodes { if let first = node.children.first { XCTAssertEqual(tree.columns[node.id], tree.columns[first]) } }
    }
    func testBranchCaptureRewindAndRules() throws {
        var tree = try document("(;SZ[5]RU[Japanese]KM[0.5]AB[ba][ab]AW[aa]PL[B](;B[ee])(;B[bb];W[cc]))")
        let player = SGFPlayer()
        tree.select(2)
        player.load(game: try tree.playbackGame()); player.seek(to: 1)
        XCTAssertEqual(player.capturesByBlack, 0)
        // A one-liberty corner white stone: the alternate fills its last liberty.
        tree = try document("(;SZ[5]RU[Japanese]KM[0.5]AB[ba]AW[aa]PL[B](;B[ee])(;B[ab];W[cc]))")
        tree.select(2); player.load(game: try tree.playbackGame()); player.seek(to: 1)
        XCTAssertEqual(player.capturesByBlack, 1)
        XCTAssertNil(player.board.grid[0][0])
        XCTAssertEqual(player.analysisSettings.kataRules, "japanese")
        XCTAssertEqual(player.analysisSettings.effectiveKomi, 0.5)
        player.seek(to: 0); XCTAssertEqual(player.capturesByBlack, 0)
        XCTAssertEqual(player.board.grid[0][0], .white)
        tree.select(1); player.load(game: try tree.playbackGame()); player.seek(to: 1)
        XCTAssertEqual(player.capturesByBlack, 0)
        XCTAssertEqual(player.board.grid[0][0], .white)
    }
    func testSetupRangesAndUnsupportedEditsPreserved() throws {
        var tree = try document("(;SZ[9]AB[aa:bb]AE[aa]PL[W];W[cc];AB[dd]C[edited];B[ee])")
        let prefix = try tree.playbackGame()
        XCTAssertEqual(prefix.setup.count, 3)
        XCTAssertEqual(prefix.initialPlayer, .white)
        XCTAssertEqual(prefix.moves.count, 1, "Do not replay unsupported setup edits as ordinary moves")
        tree.select(2)
        XCTAssertThrowsError(try tree.playbackGame())
        XCTAssertTrue(SGFWriter.serialize(tree.source).contains("AB[dd]"))
    }
    func testCreateBranchDoesNotTruncateOriginalAndReusesExistingChild() throws {
        var tree = try document("(;SZ[9];B[aa];W[bb]C[original];B[cc])")
        tree.select(1)
        tree = tree.addingMove(color: .white, point: BoardPosition(3,3))
        XCTAssertEqual(tree.nodes.count, 5)
        XCTAssertFalse(tree.isMainLine)
        XCTAssertEqual(try tree.playbackGame().moves.last?.1?.0, 3)
        let original = SGFGame.from(tree: tree.source)
        XCTAssertEqual(original.moves.count, 3)
        XCTAssertEqual(original.moves[1].1?.0, 1)
        XCTAssertTrue(SGFWriter.serialize(tree.source).contains("C[original]"))
        let alternative = tree.selectedID
        tree = tree.addingMove(color: .black, point: nil)
        XCTAssertTrue(tree.nodes[tree.selectedID].isPass)
        tree.select(1)
        tree = tree.addingMove(color: .white, point: BoardPosition(3,3))
        XCTAssertEqual(tree.selectedID, alternative)
        XCTAssertEqual(tree.nodes.count, 6)
        XCTAssertEqual(try tree.playbackGame().moves.count, 3)
        let reopened = try document(SGFWriter.serialize(tree.source))
        XCTAssertEqual(reopened.nodes.count, 6)
        XCTAssertEqual(reopened.nodes[1].children.count, 2)
    }
    func testRootMoveAndEmptyGameCanCreateBranches() throws {
        var tree = try document("(;SZ[9]B[aa]C[first];W[bb])")
        XCTAssertTrue(tree.nodes[0].isVirtual)
        tree = tree.addingMove(color: .black, point: BoardPosition(2,2))
        XCTAssertEqual(try tree.playbackGame().moves.count, 1)
        XCTAssertEqual(SGFGame.from(tree: tree.source).moves.count, 2)
        XCTAssertTrue(SGFWriter.serialize(tree.source).contains("C[first]"))
        let empty = ReviewTree(game: SGFGame(), analysisID: "new", filename: "Game.sgf")
        let added = empty.addingMove(color: .black, point: BoardPosition(3,3))
        XCTAssertEqual(added.nodes.count, 2)
        XCTAssertTrue(added.isMainLine)
    }
    func testDraftRecoveryRejectsChangedSourceAndPreservesSelection() throws {
        var tree = try document("(;SZ[9];B[aa];W[bb])")
        tree.select(1)
        tree = tree.addingMove(color: .white, point: BoardPosition(3,3))
        let data = try JSONEncoder().encode(ReviewDraft(tree))
        let draft = try JSONDecoder().decode(ReviewDraft.self, from: data)
        let original = try document("(;SZ[9];B[aa];W[bb])")
        let restored = try XCTUnwrap(draft.restore(over: original))
        XCTAssertEqual(restored.selectedID, tree.selectedID)
        XCTAssertEqual(SGFWriter.serialize(restored.source), SGFWriter.serialize(tree.source))
        XCTAssertNil(try draft.restore(over: document("(;SZ[9];B[cc])")))
    }
    func testKoHistoryFollowsSelectedBranch() throws {
        var tree = try document("(;SZ[5]RU[Japanese]AB[ba][ab][bc]AW[bb][ca][db][cc]PL[B](;B[cb];W[ee];B[de])(;B[ee]))")
        let player = SGFPlayer()
        tree.select(1); player.load(game: try tree.playbackGame()); player.seek(to: 1)
        XCTAssertEqual(player.koPoint, BoardPosition(1,1))
        XCTAssertEqual(player.moveRejection(color: .white, x: 1, y: 1), .ko)
        tree.select(4); player.load(game: try tree.playbackGame()); player.seek(to: 1)
        XCTAssertNil(player.koPoint)
        XCTAssertEqual(player.capturesByBlack, 0)
        tree.select(3); player.load(game: try tree.playbackGame()); player.seek(to: 3)
        XCTAssertNil(player.moveRejection(color: .white, x: 1, y: 1), "Threat and response allow recapture on this path")
    }
    func testDraftCanBeExtendedAfterRecoveryWithoutLosingOriginalIdentity() throws {
        let original = try document("(;SZ[9];B[aa];W[bb])")
        var edited = original
        edited.select(1)
        edited = edited.addingMove(color: .white, point: BoardPosition(2,2))
        var recovered = try XCTUnwrap(ReviewDraft(edited).restore(over: original))
        recovered = recovered.addingMove(color: .black, point: BoardPosition(3,3))
        let reopened = try XCTUnwrap(ReviewDraft(recovered).restore(over: original))
        XCTAssertEqual(reopened.nodes.count, 5)
        XCTAssertEqual(try reopened.playbackGame().moves.count, 3)
        XCTAssertEqual(SGFGame.from(tree: reopened.source).moves.count, 2)
    }

    func testShortVariationsReuseColumnsThroughoutLongGame() throws {
        // Every main-line move has a short alternative: the old leaf-count
        // layout grew to 201 columns, pushing the earliest branches farthest out.
        let text = "(;SZ[19]" + String(repeating: "(;B[]", count: 200)
            + String(repeating: ")(;W[])", count: 200) + ")"
        let tree = try document(text)
        XCTAssertEqual(tree.columnCount, 2)
        XCTAssertTrue(tree.activePath.allSatisfy { tree.columns[$0] == 0 })
        for node in tree.nodes where node.children.count > 1 {
            XCTAssertEqual(tree.columns[node.children[1]], 1)
        }
        XCTAssertEqual(SGFWriter.serialize(tree.source), SGFWriter.serialize(try SGFParser.parse(text: text)))
    }

    func testOverlappingNestedVariationsStaySeparateAndStraight() throws {
        let tree = try document("(;SZ[9];B[](;W[](;B[](;W[];B[])(;W[];B[]))"
            + "(;B[];W[];B[])) (;W[](;B[];W[];B[])(;B[];W[])))")
        XCTAssertEqual(tree.columnCount, 5, "Simultaneous continuations require distinct lanes")
        for row in tree.rows {
            XCTAssertEqual(Set(row.map { tree.columns[$0] }).count, row.count)
        }
        for node in tree.nodes {
            if let first = node.children.first { XCTAssertEqual(tree.columns[first], tree.columns[node.id]) }
            for child in node.children.dropFirst() {
                XCTAssertGreaterThan(tree.columns[child], tree.columns[node.id])
            }
        }
        // Within each row's top half, connecting edges must keep their left-to-
        // right order (shared parents are the only allowed common endpoints).
        for row in tree.rows.dropFirst() {
            let children = row.sorted { tree.columns[$0] < tree.columns[$1] }
            let parents = children.compactMap { tree.nodes[$0].parent.map { tree.columns[$0] } }
            XCTAssertEqual(parents, parents.sorted(), "Connecting lines must not cross")
        }
        let reopened = try document(SGFWriter.serialize(tree.source))
        XCTAssertEqual(reopened.columns, tree.columns)
    }

    func testDeepTreeIsIterativeAndCompact() throws {
        let tree = try document(String(repeating: "(;C[node]", count: 10_000) + String(repeating: ")", count: 10_000))
        XCTAssertEqual(tree.nodes.count, 10_000)
        XCTAssertEqual(tree.columnCount, 1)
        XCTAssertEqual(try SGFParser.parse(text: SGFWriter.serialize(tree.source)).branches.count, 10_000)
    }
}
