import AppKit
import Foundation

@main struct ReviewFlickerTests {
    @MainActor static func main() throws {
        setbuf(stdout,nil);NSApplication.shared.setActivationPolicy(.accessory)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("review-flicker-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let r=GameRecorder(storage:folder);r.clock.audible=false
        r.start(size:9,clockSettings:.init(mainSeconds:300));r.resume()
        var now=ProcessInfo.processInfo.systemUptime,board=[Occupancy](repeating:.empty,count:81),checks=0
        func check(_ ok:Bool,_ message:String) {checks+=1;precondition(ok,message)}
        func feed(_ states:[Occupancy],_ count:Int) {
            for _ in 0..<count {
                now+=0.21
                r.consume(.init(readings:states.enumerated().map{.init(row:$0.offset/9,col:$0.offset%9,occupancy:$0.element,confidence:1,delta:0)},size:9,capturedAt:now,handObstructed:false),now:now)
            }
        }
        feed(board,10);board[10] = .black;feed(board,12);board[20] = .white;feed(board,12)
        check(r.moveCount==2,"Initial moves failed")
        r.clock.recover(toBlack:true,reason:"Test interrupted timing",at:now)
        let record=r.sgf(),black=r.clock.engine.black.remaining,white=r.clock.engine.white.remaining
        for _ in 0..<4 {
            var missing=board;missing[20] = .empty
            feed(missing,100) // Exceeds the previous 12-second escalation timeout.
            check(r.reviewHistory.unresolved==0 && !r.hasDeferredMoves,"Missing stone became a chronology review")
            check(r.adjustmentIssues[20] != nil,"Persistent absence lost its actionable issue")
            feed(board,100)
            check(r.reviewHistory.unresolved==0 && !r.hasDeferredMoves,"Restoration became a new move review")
            check(r.sgf()==record && r.moveCount==2,"Flicker changed saved history")
            check(!r.clock.running && r.clock.requiresReview && r.clock.engine.black.remaining==black
                && r.clock.engine.white.remaining==white,"Flicker changed held clock balances or cleared timing review")
        }
        print("PASS: \(checks) prolonged missing/restored-stone review checks")
    }
}
