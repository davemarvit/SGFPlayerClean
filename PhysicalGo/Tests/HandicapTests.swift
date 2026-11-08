import Foundation

@MainActor func runHandicapTests() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("handicap-tests-"+UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:directory)}
    var now=0.0,checks=0
    func check(_ value:Bool,_ message:String) {checks += 1;precondition(value,message)}
    func feed(_ recorder:GameRecorder,_ board:BoardSnapshot,override:[Int:Occupancy]=[:],frames:Int=6) {
        for _ in 0..<frames {
            now += 0.21
            recorder.consume(BoardObservation(readings:(0..<board.size*board.size).map {i in
                let stone=board.grid[i/board.size][i%board.size]
                return IntersectionReading(row:i/board.size,col:i%board.size,occupancy:override[i] ?? (stone == .black ? .black:stone == .white ? .white:.empty),confidence:1,delta:0)
            },size:board.size),now:now)
        }
    }
    for size in [9,13,19] {
        for handicap in 2...9 {
            let recorder=GameRecorder(storage:directory)
            recorder.start(size:size,now:now,info:SGFGame.Info(komi:"0.5",rules:"AGA"),handicap:handicap)
            let setup=recorder.positions[0],first=recorder.game.setup[0]
            check(recorder.game.setup.count==handicap && recorder.moveCount==0 && recorder.nextPlayer == .white,"Bad handicap initialization")
            check(Set(recorder.game.setup.map {$0.2*size+$0.1}).count==handicap,"Duplicate handicap point")
            feed(recorder,setup,override:[first.2*size+first.1:.empty])
            check(recorder.state == .verifying,"Missing handicap stone accepted")
            feed(recorder,setup,override:[0:.black])
            check(recorder.state == .verifying,"Extra stone accepted")
            feed(recorder,setup,override:[first.2*size+first.1:.white])
            check(recorder.state == .verifying,"Wrong color accepted")
            feed(recorder,setup,override:[first.2*size+first.1:.uncertain])
            check(recorder.state == .verifying,"Hidden setup stone accepted")
            feed(recorder,setup,frames:2);recorder.pause();recorder.resume()
            feed(recorder,setup,frames:2)
            check(recorder.state == .verifying,"Interrupted setup retained stability")
            feed(recorder,setup)
            check(recorder.state == .recording && recorder.moveCount==0,"Setup did not verify")
            let engine=SGFPlayer();engine.load(game:recorder.game)
            check(engine.tryPlayMove(color:.white,x:0,y:0)==nil,"White cannot play first")
            feed(recorder,engine.board,frames:10)
            check(recorder.moveCount==1 && recorder.game.moves[0].0 == .white && recorder.nextPlayer == .black,"White first move not recorded")
            var info=recorder.game.info;info.rules="Japanese";info.playerBlack="Player B";recorder.updateInfo(info)
            check(recorder.game.info.rules=="AGA" && recorder.game.info.playerBlack=="Player B","Info changed live rules")
            recorder.pause();try recorder.savePendingCheckpoint()
            let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:recorder.autosaveURL!)
            check(restored.moveCount==1 && restored.game.handicap==handicap && restored.game.setup.count==handicap && restored.nextPlayer == .black,"SGF restore lost setup or turn")
            restored.undo()
            check(restored.moveCount==0 && restored.nextPlayer == .white && restored.game.setup.count==handicap,"Undo removed handicap setup")
        }
    }
    for rules in LocalGameSetup.rules {
        let recorder=GameRecorder(storage:directory)
        recorder.start(size:9,now:now,info:SGFGame.Info(rules:rules))
        feed(recorder,recorder.positions[0]);recorder.pause();try recorder.savePendingCheckpoint()
        let restored=GameRecorder(storage:nil);try restored.restoreSavedGame(from:recorder.autosaveURL!)
        check(restored.game.info.rules==rules && restored.game.analysisSettings.playRules != nil,"Rules failed round trip")
        check(restored.nextPlayer == .black && restored.game.setup.isEmpty,"Even game wrong turn")
    }
    print("PASS: \(checks) handicap/rules checks: 9/13/19 boards, 2–9 stones, setup verification, interruptions, White first, SGF/checkpoint restore, undo and locked rules")
}
