import XCTest
@testable import SGFPlayerNetworking

final class AIVariationTests: XCTestCase {
    private func candidate(_ moves: [String]) -> AIMoveInfo {
        AIMoveInfo(move: moves.first ?? "pass", visits: 50, winrate: 0.5, scoreLead: 0, pv: moves)
    }
    private func game(_ text: String) throws -> SGFPlayer {
        let p = SGFPlayer(); p.load(game: SGFGame.from(tree: try SGFParser.parse(text: text))); return p
    }
    func testVariationAtEarlierMoveLeavesHistoryBoardAndPrisonersUntouched() throws {
        let p = try game("(;SZ[9]RU[Japanese];B[aa];W[bb];B[cc])")
        p.seek(to: 1)
        let board = p.board
        let frames = AIVariation.frames(candidate: candidate(["C7", "D6", "pass", "E5"]), game: p)
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[0].stones[BoardPosition(2,2)], .white)
        XCTAssertEqual(frames[1].numbers[BoardPosition(3,3)], 2)
        XCTAssertTrue(frames[2].caption.contains("White passes"))
        XCTAssertEqual(frames[3].numbers[BoardPosition(4,4)], 4)
        XCTAssertEqual(p.board, board); XCTAssertEqual(p.currentIndex, 1); XCTAssertEqual(p.maxIndex, 3)
        XCTAssertEqual(p.capturesByBlack, 0); XCTAssertEqual(p.capturesByWhite, 0)
    }
    func testCaptureAndKoUseGameRulesWithoutChangingRealCaptures() throws {
        let p = try game("(;SZ[5]RU[Japanese]AB[ba][ab][bc]AW[bb][ca][db][cc])")
        let frames = AIVariation.frames(candidate: candidate(["C4", "B4"]), game: p)
        XCTAssertEqual(frames.count, 1, "Illegal immediate ko recapture ends preview")
        XCTAssertNil(frames[0].stones[BoardPosition(1,1)])
        XCTAssertEqual(frames[0].numbers[BoardPosition(1,2)], 1)
        XCTAssertEqual(p.board.stones[BoardPosition(1,1)], .white)
        XCTAssertEqual(p.capturesByBlack, 0)
    }
    func testCapturedPreviewStonesLoseTheirNumbers() throws {
        let p = try game("(;SZ[5]RU[Japanese]AW[ab])")
        let frames = AIVariation.frames(candidate: candidate(["A5", "B5"]), game: p)
        XCTAssertEqual(frames.count, 2)
        XCTAssertNil(frames[1].numbers[BoardPosition(0,0)])
        XCTAssertNil(frames[1].stones[BoardPosition(0,0)])
        XCTAssertEqual(frames[1].numbers[BoardPosition(0,1)], 2)
    }
    func testMalformedOccupiedAndMismatchedVariationsDoNotInventPasses() throws {
        let p = try game("(;SZ[9]AB[aa])")
        for moves in [["I5"], ["T19"], ["A09"], ["A9"], ["nonsense"]] {
            XCTAssertTrue(AIVariation.frames(candidate: candidate(moves), game: p).isEmpty)
        }
        let mismatch = AIMoveInfo(move: "B8", visits: 50, winrate: 0.5, scoreLead: 0, pv: ["C7"])
        XCTAssertTrue(AIVariation.frames(candidate: mismatch, game: p).isEmpty)
        XCTAssertEqual(AIVariation.frames(candidate: candidate(["B8", "C7", "D6"]), game: p, limit: 2).count, 2)
        XCTAssertEqual(AIVariation.position("J1", size: 9), BoardPosition(8,8))
    }
}
