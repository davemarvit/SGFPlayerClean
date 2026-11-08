import AppKit
import SwiftUI

@main struct ClockReviewTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        try runLocalClockTests()
        var checks=0
        func check(_ value:Bool,_ text:String) {checks += 1;precondition(value,text)}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("clock-review-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let recorder=GameRecorder(storage:root);recorder.clock.audible=false
        var now=ProcessInfo.processInfo.systemUptime
        recorder.start(size:9,now:now,clockSettings:.init(kind:.canadian,mainSeconds:600))
        let empty=BoardObservation(readings:(0..<81).map {.init(row:$0/9,col:$0%9,occupancy:.empty,confidence:1,delta:0)},size:9)
        for _ in 0..<6 {now += 0.21;recorder.consume(empty,now:now)}
        check(recorder.clock.running,"Test clock never started")
        recorder.clock.recover(toBlack:true,reason:"Several moves were recovered together.",at:now)
        recorder.clock.recordMove(number:3,black:false,at:now)
        check(recorder.clock.needsCorrection && recorder.clock.notice.contains("Several moves"),"Later move hid original review reason")
        recorder.pause()
        let black=recorder.clock.engine.black,white=recorder.clock.engine.white
        let sgf=recorder.sgf()
        var invalid=black;invalid.remaining=0
        check(!recorder.confirmClockReview(black:invalid,white:white,resume:true),"Invalid time accepted")
        check(recorder.state == .paused && recorder.clock.requiresReview,"Invalid review resumed play")
        let output=URL(fileURLWithPath:"PhysicalGo/.build/ClockReviewUI")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func render<V:View>(_ view:V,_ name:String,width:CGFloat,height:CGFloat)throws {
            let host=NSHostingView(rootView:view);host.frame=NSRect(x:0,y:0,width:width,height:height)
            let window=NSWindow(contentRect:host.frame,styleMask:[.titled],backing:.buffered,defer:false)
            window.contentView=host;window.orderFront(nil)
            RunLoop.main.run(until:Date().addingTimeInterval(0.1))
            host.appearance=NSAppearance(named:.darkAqua);host.layoutSubtreeIfNeeded()
            let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            window.orderOut(nil)
        }
        try render(LocalClockPanel(clock:recorder.clock,recorder:recorder),"review-action",width:1280,height:300)
        try render(LocalClockCorrection(clock:recorder.clock,recorder:recorder,resumeAfterReview:true),"review-sheet",width:570,height:470)
        check(recorder.confirmClockReview(black:black,white:white,resume:true),"Unchanged agreed times rejected")
        check(!recorder.clock.needsCorrection && !recorder.clock.running && [.recording,.verifying].contains(recorder.state),"Review skipped board verification")
        check(recorder.clock.engine.black.remaining==black.remaining && recorder.clock.engine.white.remaining==white.remaining,"Review altered agreed times")
        check(recorder.sgf()==sgf,"Clock review changed saved moves")
        var blocked=empty;blocked.lightingBlocked=true
        recorder.consume(blocked,now:now+0.2)
        check(!recorder.clock.running,"Blocked view started clocks")
        for _ in 0..<8 {now += 0.21;recorder.consume(empty,now:now)}
        check(recorder.synchronized && recorder.clock.running && recorder.clock.engine.blackToPlay,"Verified board failed to resume correct clock")
        recorder.pause();recorder.clock.recover(toBlack:true,reason:"Review",at:now)
        let restored=LocalGameClock();restored.audible=false
        // Read the actual checkpoint signature, then exercise persisted review.
        let file=recorder.autosaveURL!,clockFile=file.deletingPathExtension().appendingPathExtension("clock.json")
        let data=try JSONSerialization.jsonObject(with:Data(contentsOf:clockFile)) as! [String:Any]
        restored.restore(from:file,signature:data["signature"] as! String,moveCount:0,blackToPlay:true)
        check(restored.requiresReview && restored.notice.contains("Review & resume"),"Restored review gave misleading resume instructions")
        check(recorder.confirmClockReview(black:black,white:white,resume:false) && recorder.state == .paused && !recorder.clock.running,"Save-only review resumed play")
        recorder.finish()
        check(!recorder.confirmClockReview(black:black,white:white,resume:true),"Review reopened finished game")
        print("PASS: \(checks) clock-review checks plus native review action and sheet renders")
    }
}
