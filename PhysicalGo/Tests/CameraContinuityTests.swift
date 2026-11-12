import Foundation

@MainActor func runCameraContinuityTests() throws {
    var checks=0
    func check(_ ok:Bool,_ text:String) {checks += 1;precondition(ok,text)}
    var gate=CameraViewContinuity()
    for i in 0..<200 {check(!gate.observe(unverified:24,total:361,now:Double(i)*0.21),"Partial uncertainty paused the clock")}
    gate.reset()
    for i in 0..<70 {
        let unreadable=i%20 != 19
        check(!gate.observe(unverified:unreadable ? 250:9,total:361,now:Double(i)*0.21),"Useful views did not reset sustained-loss timer")
    }
    gate.reset()
    for i in 0..<48 {check(!gate.observe(unverified:250,total:361,now:Double(i)*0.21),"True loss paused before ten seconds")}
    check(gate.observe(unverified:250,total:361,now:10.1),"Sustained true loss never paused")
    check(!gate.observe(unverified:250,total:361,now:10.1),"Duplicate timestamp counted as evidence")
    check(!gate.observe(unverified:250,total:361,now:15),"Camera gap inherited prior timer")
    gate.reset();check(!gate.observe(unverified:250,total:361,now:16),"Reset inherited prior timer")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("camera-continuity-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/CameraContinuity")
    let original=try SGFParser.parse(text:String(contentsOf:fixture.appendingPathComponent("game.sgf"),encoding:.utf8))
    let originalGame=SGFGame.from(tree:original)
    struct Frame:Decodable {let time:Double;let position:String;let lightingBlocked:Bool}
    func observation(_ cells:[Occupancy])->BoardObservation {
        .init(readings:cells.enumerated().map {.init(row:$0.offset/19,col:$0.offset%19,occupancy:$0.element,confidence:1,delta:0)},size:19)
    }
    var time=ProcessInfo.processInfo.systemUptime
    for move in [37,39] {
        let tree=SGFTree(branches:[.init(sequence:Array(original.mainLineNodes.prefix(move+1)))])
        let url=root.appendingPathComponent("move-\(move).sgf")
        try SGFWriter.serialize(tree).write(to:url,atomically:true,encoding:.utf8)
        let r=GameRecorder(storage:nil);r.clock.audible=false
        try r.restoreSavedGame(from:url)
        check(r.moveCount==move,"Replay fixture wrong starting point")
        r.clock.configure(.init(kind:.absolute,mainSeconds:300),blackToPlay:r.nextPlayer == .black,baseMove:move)
        r.resume()
        let board=r.positions.last!.grid.flatMap {$0}.map {$0 == .black ? Occupancy.black:$0 == .white ? .white:.empty}
        for _ in 0..<8 {time += 0.21;r.consume(observation(board),now:time)}
        check(r.clock.running,"Replay clock never started")
        var pauses=0;r.clock.onAutomaticPause={_ in pauses += 1}
        let frames=try JSONDecoder().decode([Frame].self,from:Data(contentsOf:fixture.appendingPathComponent("move-\(move).json")))
        let start=time+0.21
        for f in frames {
            time=start+f.time-frames[0].time
            let cells=f.position.map {$0 == "B" ? Occupancy.black:$0 == "W" ? .white:$0 == "?" ? .uncertain:.empty}
            var view=observation(cells);view.lightingBlocked=f.lightingBlocked
            r.consume(view,now:time)
        }
        if move==37 {
            check(pauses==0 && r.clock.running,"A partial view stopped the independently recovered move")
        } else {
            // These archived occupancy snapshots contain separate appearances,
            // but no retained clock presses or hand-clear completion metadata.
            check(pauses==1 && r.clock.requiresReview && !r.clock.running,"Missing timing was silently inferred from the retained positions")
            check(r.clock.moves.isEmpty && r.clock.provisionalMoves.isEmpty,"The incomplete evidence invented individual presses or increments")
        }
        if move==37 {
            check(r.moveCount>=38,"Retained views failed to recover next move")
            let saved=r.game.moves[37],expected=originalGame.moves[37]
            check(saved.0==expected.0 && saved.1?.0==expected.1?.0 && saved.1?.1==expected.1?.1,"Recovered a different move")
        } else {
            check(r.moveCount==39 && r.hasDeferredMoves,"Ambiguity was discarded or invented into SGF")
        }
        print("Actual move \(move) replay: \(frames.count) frames, \(pauses) pauses, \(r.moveCount) saved moves, deferred review=\(r.hasDeferredMoves)")
        r.pause();check(!r.clock.running,"Manual pause was ignored")
    }
    // Integration: true broad loss still pauses, and partial views never erase
    // retained observations or force the clock to stop.
    let r=GameRecorder(storage:nil);r.clock.audible=false
    r.start(size:19,clockSettings:.init(kind:.absolute,mainSeconds:300))
    let empty=[Occupancy](repeating:.empty,count:361)
    for _ in 0..<8 {time += 0.21;r.consume(observation(empty),now:time)}
    check(r.clock.running,"Sustained-loss test never started")
    for _ in 0..<70 {time += 0.21;r.consume(observation(Array(repeating:.uncertain,count:361)),now:time)}
    check(!r.clock.running && r.clock.automaticPause != nil,"Sustained unreadable board did not pause")
    r.pause()
    for _ in 0..<10 {time += 0.21;r.consume(observation(empty),now:time)}
    check(!r.clock.running,"Readable board overrode manual pause")
    print("PASS: \(checks) camera continuity checks: partial views, resets, duplicate frames, actual pauses replayed, deferred review, real loss and manual pause")
}
