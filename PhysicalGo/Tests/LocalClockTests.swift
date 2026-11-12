import Foundation

@MainActor func runLocalClockTests() throws {
    var count=0
    func check(_ value:Bool,_ message:String) {count += 1;precondition(value,message)}
    func near(_ a:Double,_ b:Double)->Bool {abs(a-b)<0.00001}
    var settings=LocalClockSettings(kind:.byoyomi,mainSeconds:10,periodSeconds:5,periods:3)
    var engine=LocalClockEngine(settings:settings)
    engine.resume(at:0);engine.advance(to:10)
    check(engine.black.overtime && engine.black.periods==3 && engine.black.remaining==5,"Main time transition lost period")
    engine.advance(to:15)
    check(engine.black.periods==2 && engine.black.remaining==5,"Period loss boundary")
    check(engine.move(black:true,at:17),"Byoyomi move rejected")
    check(engine.black.periods==2 && engine.black.remaining==5 && !engine.blackToPlay,"Byoyomi reset restored lost period")
    engine.advance(to:20);check(engine.white.remaining==7,"Other side was charged during opponent turn")
    check(!engine.move(black:true,at:20),"Duplicate or wrong-color clock press")
    engine.pause(at:20);engine.advance(to:500)
    check(engine.white.remaining==7,"Paused clock ran")
    engine.resume(at:600);engine.advance(to:607)
    check(engine.white.overtime && engine.white.periods==3,"Resume counted paused interval")
    engine.advance(to:622);check(engine.expiredBlack==false && !engine.running,"Byoyomi timeout")
    check(!engine.move(black:false,at:623),"Late move rescued timeout")
    settings.mainSeconds=0;engine=LocalClockEngine(settings:settings,blackToPlay:false)
    check(engine.white.overtime && !engine.blackToPlay,"Handicap/zero-main setup")
    engine.resume(at:0);engine.advance(to:14.99)
    check(engine.expiredBlack==nil && engine.white.periods==1,"Premature final-period timeout")
    engine.advance(to:15);check(engine.expiredBlack==false,"Exact boundary timeout")
    settings=LocalClockSettings(kind:.fischer,mainSeconds:10,incrementSeconds:3,maximumSeconds:12)
    engine=LocalClockEngine(settings:settings);engine.resume(at:0)
    check(engine.move(black:true,at:0.5) && engine.black.remaining==12,"Fischer cap")
    check(engine.move(black:false,at:3) && engine.white.remaining==10.5,"Fischer increment")
    engine.advance(to:15);check(engine.expiredBlack==true,"Fischer timeout gained increment")
    settings=LocalClockSettings(kind:.canadian,mainSeconds:5,periodSeconds:20,stonesPerPeriod:2)
    engine=LocalClockEngine(settings:settings);engine.resume(at:0)
    check(engine.move(black:true,at:7) && engine.black.stones==1 && engine.black.remaining==18,"Canadian first overtime move")
    check(engine.move(black:false,at:8),"White move")
    check(engine.move(black:true,at:10) && engine.black.stones==2 && engine.black.remaining==20,"Canadian block reset")
    engine.advance(to:100);check(engine.expiredBlack==false,"Canadian timeout")
    settings=LocalClockSettings(kind:.simple,periodSeconds:7)
    engine=LocalClockEngine(settings:settings);engine.resume(at:0);_ = engine.move(black:true,at:6)
    check(engine.black.remaining==7 && engine.white.remaining==7,"Per-move reset")
    engine.advance(to:13);check(engine.expiredBlack==false,"Per-move timeout")
    settings=LocalClockSettings(kind:.absolute,mainSeconds:60)
    engine=LocalClockEngine(settings:settings);engine.resume(at:10);engine.advance(to:20);engine.advance(to:15)
    check(engine.black.remaining==50,"Backward timestamp changed clock")
    _ = engine.move(black:true,at:30);check(engine.black.remaining==40,"Absolute got bonus")
    check(LocalClockEngine.display(59.01)=="1:00" && LocalClockEngine.display(0.01)=="0:01" && LocalClockEngine.display(3600)=="1:00:00","Clock display rounding")
    check(LocalClockSettings(kind:.fischer,mainSeconds:100,maximumSeconds:10).validationError != nil,"Invalid cap accepted")
    // Callback frequency must not affect results, including skipped periods and long gaps.
    for kind in LocalClockSettings.Kind.allCases where kind != .none {
        for duration in [0.1,9.9,10.0,11.0,30.0,1000.0] {
            let config=LocalClockSettings(kind:kind,mainSeconds:10,periodSeconds:7,periods:4)
            var once=LocalClockEngine(settings:config),many=once
            once.resume(at:0);many.resume(at:0);once.advance(to:duration)
            for i in 1...100 {many.advance(to:duration*Double(i)/100)}
            check(near(once.black.remaining,many.black.remaining) && once.black.periods==many.black.periods && once.expiredBlack==many.expiredBlack,"Clock depends on timer frequency: \(kind) \(duration)")
        }
    }
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("clock-test-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("test.sgf")
    let clock=LocalGameClock();clock.audible=false
    clock.configure(.init(kind:.fischer,mainSeconds:60,incrementSeconds:5),blackToPlay:true)
    clock.bind(to:url,signature:"start");clock.ready(at:0)
    clock.recordMove(number:1,black:true,at:10);clock.bind(to:url,signature:"move1")
    check(clock.engine.black.remaining==55 && !clock.engine.blackToPlay,"Controller move switch")
    clock.recordMove(number:1,black:true,at:12)
    check(clock.engine.black.remaining==55 && clock.moves.count==1,"Duplicate increment")
    try clock.flushStorage()
    let restored=LocalGameClock();restored.audible=false
    restored.restore(from:url,signature:"move1",moveCount:1,blackToPlay:false)
    check(restored.enabled && !restored.running && restored.engine.black.remaining==55,"Restore lost clocks or resumed them")
    clock.undo(to:0,blackToPlay:true,at:11)
    check(!clock.running && clock.engine.blackToPlay && clock.engine.black.remaining==50,"Undo clock press")
    clock.recover(toBlack:false,reason:"Ambiguous sequence",at:12)
    clock.resume(at:13);check(!clock.running && clock.needsCorrection,"Ambiguous chronology resumed without correction")
    var corrected=clock.engine.black;corrected.remaining=40
    clock.correct(black:corrected,white:clock.engine.white,blackToPlay:false,moveCount:3,at:14)
    clock.resume(at:15);clock.recordMove(number:4,black:false,at:16)
    check(clock.running && clock.engine.blackToPlay && !clock.needsCorrection,"Correction did not restore clock sequence")
    clock.pause(at:16);try clock.flushStorage()
    let bad=LocalGameClock();bad.audible=false;bad.restore(from:url,signature:"wrong game",moveCount:1,blackToPlay:false)
    check(!bad.enabled && bad.saveError != nil,"Mismatched saved clocks accepted")
    let lag=LocalGameClock();lag.audible=false
    lag.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true);lag.ready(at:0)
    lag.tick(at:10.5);check(lag.engine.expiredBlack==true,"Expected visible expiry")
    lag.recordMove(number:1,black:true,at:10.5,observedAt:9.5)
    check(lag.engine.expiredBlack==nil && near(lag.engine.black.remaining,0.5) && near(lag.engine.white.remaining,9) && !lag.engine.blackToPlay,"Confirmation delay falsely timed out an on-time move")
    lag.pause(at:10.5)
    lag.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true);lag.ready(at:0);lag.tick(at:11)
    lag.recordMove(number:1,black:true,at:11,observedAt:10.1)
    check(lag.engine.expiredBlack==true,"Actually late move rescued timeout")
    lag.configure(.init(kind:.absolute,mainSeconds:10),blackToPlay:true);lag.ready(at:0)
    lag.pause(at:5);lag.resume(at:10);lag.recordMove(number:1,black:true,at:11,observedAt:4)
    check(near(lag.engine.black.remaining,4),"Evidence crossed a pause boundary")
    lag.pause(at:11)
    // Exercise recorder integration, handicap start, automatic recognition, passes and SGF.
    let recorder=GameRecorder(storage:directory);recorder.clock.audible=false
    var now=ProcessInfo.processInfo.systemUptime
    recorder.start(size:9,now:now,handicap:2,clockSettings:.init(kind:.byoyomi,mainSeconds:60))
    check(!recorder.clock.running,"Clock ran during handicap setup")
    func feed(_ board:BoardSnapshot) {
        for _ in 0..<8 {
            now += 0.21
            recorder.consume(BoardObservation(readings:(0..<81).map {i in
                let color=board.grid[i/9][i%9]
                return IntersectionReading(row:i/9,col:i%9,occupancy:color == .black ? .black:color == .white ? .white:.empty,confidence:1,delta:0)
            },size:9),now:now)
        }
    }
    feed(recorder.positions[0]);check(recorder.clock.running && !recorder.clock.engine.blackToPlay,"Handicap clock failed to start on White")
    let player=SGFPlayer();player.load(game:recorder.game);_ = player.tryPlayMove(color:.white,x:0,y:0)
    feed(player.board)
    check(recorder.moveCount==1 && recorder.clock.engine.blackToPlay && recorder.clock.moves.count==1,"Recognized stone did not switch clock")
    let tree=try SGFParser.parse(text:recorder.sgf())
    check(tree.mainLineNodes[0].props["TM"]==["60"] && tree.mainLineNodes[0].props["OT"] != nil && tree.mainLineNodes[1].props["WL"] != nil,"Clock SGF export missing")
    recorder.pause();check(!recorder.clock.running,"Recording pause did not pause clock")
    recorder.pass();check(recorder.moveCount==2 && !recorder.clock.engine.blackToPlay,"Pass did not switch clock")
    recorder.pass();check(recorder.state == .finished && !recorder.clock.running,"Two passes did not stop clock")
    try recorder.flushStorage()
    let reread=GameRecorder(storage:nil);reread.clock.audible=false;try reread.restoreSavedGame(from:recorder.autosaveURL!)
    check(reread.clock.enabled && !reread.clock.running && reread.moveCount==3,"Recorder restore lost clock")
    print("PASS: \(count) local-clock checks: six modes, exact boundaries, overtime, increments, duplicate presses, frequency independence, pause, handicap, recognition, pass, undo, correction, persistence and SGF")
}
