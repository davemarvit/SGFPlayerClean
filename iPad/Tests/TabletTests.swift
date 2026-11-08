import XCTest
import UIKit
@testable import QuietGo_iPad

@MainActor final class TabletTests: XCTestCase {
    func testAnalysisPreferenceAndHistoryIdentity() throws {
        let prior = AppSettings.shared.analysisEnabled
        defer { AppSettings.shared.analysisEnabled = prior }
        let game = TabletGame(restore: false)
        let analysis = TabletAnalysis()
        let opening = analysis.key(game.player)
        XCTAssertEqual(opening, analysis.key(game.player))
        game.play(pass: true); game.play(pass: true)
        XCTAssertNotEqual(opening, analysis.key(game.player), "Equal boards with different ko histories must not share results")
        game.select(0)
        XCTAssertEqual(opening, analysis.key(game.player))
        AppSettings.shared.analysisEnabled = false
        XCTAssertFalse(game.canAnalyze)
        analysis.analyze(game.player)
        XCTAssertFalse(analysis.running)
        analysis.analyzeGame(game)
        XCTAssertFalse(analysis.sweeping)
    }
    func testFullGameReviewPreservesBoardAndVariations() async throws {
        let prior = AppSettings.shared.analysisEnabled
        AppSettings.shared.analysisEnabled = true
        defer { AppSettings.shared.analysisEnabled = prior }
        let game = TabletGame(restore: false)
        try game.load(text: "(;SZ[9]RU[Japanese]KM[6.5];B[cc](;W[dd])(;W[ee]))", name: "Sweep")
        game.step(1)
        let node = game.tree.selectedID
        let record = game.exportedSGF
        let analysis = TabletAnalysis()
        analysis.analyzeGame(game)
        let deadline = Date().addingTimeInterval(180)
        while analysis.sweeping && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(analysis.sweeping)
        XCTAssertEqual(analysis.completed, analysis.total)
        XCTAssertGreaterThan(analysis.total, 1)
        XCTAssertEqual(game.tree.selectedID, node)
        XCTAssertEqual(game.exportedSGF, record)
        XCTAssertEqual(game.player.currentIndex, 1)
        XCTAssertNotNil(analysis.result)
        let restored = TabletAnalysis()
        restored.restore(game.player)
        XCTAssertEqual(restored.result?.rootInfo?.visits, analysis.result?.rootInfo?.visits)
    }
    func testReviewModeFollowsImportsNewGamesAndRestoration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = TabletGame(storageDirectory: folder)
        XCTAssertEqual(game.mode, .localPlay)
        game.tap(at: BoardPosition(3, 3))
        let original = game.exportedSGF
        game.selectLocalMode(.review)
        XCTAssertEqual(game.mode, .review)
        XCTAssertEqual(game.exportedSGF, original)
        XCTAssertEqual(TabletGame(storageDirectory: folder).mode, .review)
        game.newGame(size: 9)
        XCTAssertEqual(game.mode, .localPlay)
        try game.load(text: "(;SZ[13];B[dd])", name: "Review SGF")
        XCTAssertEqual(game.mode, .review)
        game.selectLocalMode(.localPlay)
        XCTAssertEqual(game.player.board.size, 13)
        XCTAssertEqual(TabletGame(storageDirectory: folder).mode, .localPlay)
    }
    func testEquipmentLayoutKeepsBoardAndBowlsVisibleAndTapsAccurate() {
        for (size, portrait) in [(CGSize(width: 834, height: 1000), true),
                                 (CGSize(width: 914, height: 650), false),
                                 (CGSize(width: 390, height: 650), true),
                                 (CGSize(width: 700, height: 400), false)] {
            let layout = TabletTableLayout(size: size, portrait: portrait)
            XCTAssertEqual(layout.board.height / layout.board.width, 1.0773, accuracy: 0.0001)
            let table = CGRect(origin: .zero, size: size)
            let equipment = [layout.whiteBowl, layout.blackBowl, layout.whiteCaptures, layout.blackCaptures]
            XCTAssertTrue(table.contains(layout.board))
            for (index, rect) in equipment.enumerated() {
                XCTAssertTrue(table.contains(rect))
                XCTAssertFalse(rect.intersects(layout.board))
                XCTAssertNil(layout.intersection(at: CGPoint(x: rect.midX, y: rect.midY), boardSize: 19))
                for other in equipment.dropFirst(index + 1) { XCTAssertFalse(rect.intersects(other)) }
            }
            // Artwork measurements: 442/512 bowl body, 808/1024 and 851/1024
            // lid bodies. Both visible lids should be ~87% of their bowl body,
            // with the raised seating rings just inside the 0.72-canvas mouth.
            let bowlBody = layout.blackBowl.width * 442 / 512
            let mouth = layout.blackBowl.width * 0.72
            for (lid, bodyPixels, lipPixels) in [(layout.blackCaptures, CGFloat(808), CGFloat(760)),
                                                (layout.whiteCaptures, CGFloat(851), CGFloat(800))] {
                let body = lid.width * bodyPixels / 1024
                let lip = lid.width * lipPixels / 1024
                XCTAssertTrue((0.85...0.89).contains(body / bowlBody), "Lid body fits its bowl, accounting for image padding")
                XCTAssertLessThan(lip, mouth, "Seating lip fits inside the opening")
                XCTAssertGreaterThan(lip, mouth * 0.96, "Lid still seats snugly")
            }
            for count in [9, 13, 19] {
                XCTAssertEqual(layout.intersection(at: CGPoint(x: layout.board.midX, y: layout.board.midY), boardSize: count), BoardPosition(count / 2, count / 2))
                let marginX = layout.board.width * 0.065, marginY = layout.board.height * 0.065
                XCTAssertEqual(layout.intersection(at: CGPoint(x: layout.board.minX + marginX, y: layout.board.minY + marginY), boardSize: count), BoardPosition(0, 0))
                XCTAssertEqual(layout.intersection(at: CGPoint(x: layout.board.maxX - marginX, y: layout.board.maxY - marginY), boardSize: count), BoardPosition(count - 1, count - 1))
                for row in 0..<count {
                    for col in 0..<count {
                        let point = CGPoint(x: layout.board.minX + marginX + CGFloat(col) * layout.board.width * 0.87 / CGFloat(count-1),
                                            y: layout.board.minY + marginY + CGFloat(row) * layout.board.height * 0.87 / CGFloat(count-1))
                        XCTAssertEqual(layout.intersection(at: point, boardSize: count), BoardPosition(row, col))
                    }
                }
            }
        }
        XCTAssertGreaterThan(TabletTableLayout(size: CGSize(width: 834, height: 1000), portrait: true).board.width, 640)
        XCTAssertGreaterThan(TabletTableLayout(size: CGSize(width: 914, height: 790), portrait: false).board.width, 600)
    }

    func testEquipmentArtworkAndCountsFollowCaptureAndRewind() throws {
        for color: Stone in [.black, .white] {
            for count in [0, 1, 90, color == .black ? 181 : 180] {
                XCTAssertNotNil(TabletBowlImages.image(color: color, remaining: count))
            }
        }
        XCTAssertNotNil(UIImage(named: "go_lid_1.png"))
        XCTAssertNotNil(UIImage(named: "go_lid_2.png"))
        let game = TabletGame(restore: false)
        try game.load(text: "(;SZ[9]AB[ab][ba][cb]AW[bb]PL[B])", name: "Equipment capture")
        let before = GoEquipment3D.supplyCounts(for: game.player)
        XCTAssertEqual(before.black, 178); XCTAssertEqual(before.white, 179)
        game.tap(at: BoardPosition(2, 1))
        XCTAssertEqual(game.player.capturesByBlack, 1)
        XCTAssertEqual(GoEquipment3D.supplyCounts(for: game.player).black, 177)
        XCTAssertEqual(GoEquipment3D.supplyCounts(for: game.player).white, 179, "Captured stones stay in lids")
        game.step(-1)
        XCTAssertEqual(game.player.capturesByBlack, 0)
        XCTAssertEqual(GoEquipment3D.supplyCounts(for: game.player).black, before.black)
        game.step(1); game.play(pass: true)
        XCTAssertEqual(game.player.capturesByBlack, 1)
        XCTAssertEqual(GoEquipment3D.supplyCounts(for: game.player).white, 179, "Passing does not consume a stone")
    }

    func testDirectBoardTapPlacesOnceAndScoringOnlyMarks() throws {
        let game = TabletGame(restore: false); game.newGame(size: 9)
        game.tap(at: BoardPosition(2,2))
        XCTAssertEqual(game.player.currentIndex, 1)
        XCTAssertEqual(game.player.board.stones[BoardPosition(2,2)], .black)
        XCTAssertNil(game.selectedPoint)
        game.tap(at: BoardPosition(2,2))
        XCTAssertEqual(game.player.currentIndex, 1)
        game.tap(at: BoardPosition(6,6))
        XCTAssertEqual(game.player.currentIndex, 2)
        game.beginScoring(); game.tap(at: BoardPosition(2,2))
        XCTAssertEqual(game.player.currentIndex, 2)
        XCTAssertTrue(try XCTUnwrap(game.scoring).deadStones.contains(BoardPosition(2,2)))
        XCTAssertNotNil(UIImage(named: TatamiTexture.assetName), "Shared tatami artwork must be bundled")
    }
    func testEditingPreservesBranchesAndRoundTrips() throws {
        let game=TabletGame(restore:false)
        try game.load(text:"(;SZ[9]RU[Japanese]KM[6.5];B[cc](;W[gg]C[original])(;W[cg]))",name:"Branches")
        game.step(1)
        XCTAssertEqual(game.player.currentIndex,1)
        game.pick(BoardPosition(4,4)); game.play()
        XCTAssertEqual(game.player.board.stones[BoardPosition(4,4)],.white)
        let exported=game.exportedSGF
        let reopened=TabletGame(restore:false)
        try reopened.load(text:exported,name:"Round trip")
        reopened.step(1)
        XCTAssertEqual(reopened.currentNode.children.count,3)
        reopened.select(reopened.currentNode.children[0])
        XCTAssertEqual(reopened.currentNode.comment,"original")
        XCTAssertEqual(reopened.player.board.stones[BoardPosition(6,6)],.white)
        XCTAssertNil(reopened.player.board.stones[BoardPosition(4,4)])
    }
    func testCaptureUndoAndPass() throws {
        let game=TabletGame(restore:false)
        try game.load(text:"(;SZ[9]RU[Japanese]KM[6.5]AB[ab][ba][cb]AW[bb]PL[B])",name:"Capture")
        game.pick(BoardPosition(2,1));game.play()
        XCTAssertNil(game.player.board.stones[BoardPosition(1,1)])
        XCTAssertEqual(game.player.capturesByBlack,1)
        game.step(-1)
        XCTAssertEqual(game.player.board.stones[BoardPosition(1,1)],.white)
        XCTAssertEqual(game.player.capturesByBlack,0)
        game.step(1);game.play(pass:true)
        XCTAssertEqual(game.player.currentIndex,2)
        XCTAssertEqual(game.player.turn,.black)
    }
    func testSessionRestorationAndArchive() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let game=TabletGame(storageDirectory:directory)
        game.newGame(size:9);game.pick(BoardPosition(2,2));game.play()
        game.play(pass:true);game.step(-1)
        let restored=TabletGame(storageDirectory:directory)
        XCTAssertEqual(restored.exportedSGF,game.exportedSGF)
        XCTAssertEqual(restored.player.currentIndex,1)
        restored.newGame(size:13)
        let archives=try FileManager.default.contentsOfDirectory(at:directory.appendingPathComponent("Saved Games"),includingPropertiesForKeys:nil)
        XCTAssertEqual(archives.count,1)
        XCTAssertEqual(try String(contentsOf:archives[0],encoding:.utf8),game.exportedSGF)
        XCTAssertEqual(restored.player.board.size,13)
    }
    func testInvalidImportDoesNotReplaceGame() throws {
        let game=TabletGame(restore:false);game.newGame(size:9)
        game.pick(BoardPosition(2,2));game.play()
        let before=game.exportedSGF
        XCTAssertThrowsError(try game.load(text:"not an SGF",name:"Broken"))
        XCTAssertThrowsError(try game.load(text:"(;SZ[99])",name:"Too large"))
        XCTAssertEqual(before,game.exportedSGF)
    }
    func testScoringDoesNotPlaceStones() {
        let game=TabletGame(restore:false);game.newGame(size:9)
        game.pick(BoardPosition(2,2));game.play();game.beginScoring()
        let before=game.exportedSGF
        game.pick(BoardPosition(2,2))
        XCTAssertTrue(game.scoring!.deadStones.contains(BoardPosition(2,2)))
        game.play(pass:true)
        XCTAssertEqual(game.exportedSGF,before)
    }
    func testNativeKataGoReturnsLegalCandidates() async throws {
        let game=TabletGame(restore:false);game.newGame(size:9)
        game.pick(BoardPosition(2,2));game.play()
        let ai=TabletAnalysis();ai.analyze(game.player)
        let deadline=Date().addingTimeInterval(120)
        while ai.running && Date()<deadline {try await Task.sleep(for:.milliseconds(100))}
        XCTAssertFalse(ai.running)
        XCTAssertNil(ai.message)
        let result=try XCTUnwrap(ai.result)
        XCTAssertGreaterThan(result.rootInfo?.visits ?? 0,0)
        XCTAssertTrue((0...1).contains(result.rootInfo!.winrate))
        for move in result.moveInfos ?? [] {
            if move.move == "pass" {continue}
            let p=try XCTUnwrap(AIVariation.position(move.move,size:9))
            XCTAssertNil(game.player.moveRejection(color:game.player.turn,x:p.col,y:p.row))
        }
        game.newGame(size:19)
        ai.analyze(game.player)
        while ai.running && Date()<deadline {try await Task.sleep(for:.milliseconds(100))}
        XCTAssertNil(ai.message)
        XCTAssertGreaterThan(ai.result?.rootInfo?.visits ?? 0,0)
        ai.analyze(game.player);ai.cancel()
        while ai.running && Date()<deadline {try await Task.sleep(for:.milliseconds(100))}
        XCTAssertNil(ai.result)
    }
}
