import Foundation

@main struct PhysicalAICheckingProgressTests {
    static func main() throws {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        var progress=PhysicalAICheckingProgress()
        func observe(_ t:Double,reason:PhysicalAICheckingProgress.Reason = .requiredIntersections,points:[Int]=[87,121],scope:String="game-1",captured:Double?=nil,empty:Bool=true)->PhysicalAICheckingProgress.Help? {
            progress.observe(scope:scope,reason:reason,points:points,size:19,emptyGame:empty,capturedAt:captured ?? t,now:t)
        }
        for t in stride(from:0.0,through:2.9,by:0.1) {check(observe(t)==nil,"Transient checking produced premature help")}
        let first=observe(3.1)!
        check(first.points==[87,121] && first.emptyGame,"Persistent required points were lost")
        check(observe(3.2,points:[27])==first,"Presentation refreshed faster than one second")
        check(observe(4.2,points:[27])?.points==[27],"Current reason/points failed to refresh")
        progress.reset() // Hand/dark interruption and explicit pause reset presentation only.
        check(progress.help==nil,"Hand/pause retained an old point warning")
        check(observe(10)==nil && observe(10.2)==nil,"Withdrawal reused a stale delay")
        check(observe(10.2,captured:10.2)==nil,"Duplicate camera frame advanced progress")
        for t in [10.4,10.8,11.2,11.6,12.0,12.4,12.8,13.2] {_=observe(t)}
        check(progress.help != nil,"Fresh unresolved withdrawal never regained help")
        check(observe(13.3,scope:"game-2")==nil,"New scope retained old help")
        check(observe(20,scope:"game-2")==nil,"Long camera gap counted as fresh assessments")
        check(observe(22,scope:"game-2",captured:20)==nil,"Stale observation advanced progress")
        progress.reset()
        for t in stride(from:0.0,through:4.0,by:0.2) {_=observe(t,reason:Int(t*5)%2==0 ? .ambiguousPlacement:.stablePosition,empty:false)}
        check(progress.followsAmbiguousPlacement && progress.help != nil,"Alternating ambiguous/stable frames hid a persistent placement delay")
        check(!progress.help!.recovery.contains("capture an empty reference"),"Occupied-game help offered empty-board capture")
        for t in [5.0,5.2,5.4,5.6,6.0] {_=observe(t,points:Array(0..<40)+[-1,400],empty:false)}
        check(progress.help!.points.count==8 && progress.help!.totalPoints==40,"Point presentation escaped bounds or counted invalid points")
        for turns in 0..<4 {
            let help=PhysicalAICheckingProgress.Help(reason:.requiredIntersections,points:[0],totalPoints:1,emptyGame:true)
            let label=BoardCoordinates.name(point:0,size:19,orientation:.init(turns))
            check(label==["A19","T19","T1","A1"][turns],"Orientation fixture changed")
            check(help.explanation {BoardCoordinates.name(point:$0,size:19,orientation:.init(turns))}.contains(label),"Help used canonical rather than displayed coordinates")
        }
        struct Recording:Decodable {
            struct Frame:Decodable {let capturedAt,ageSeconds:Double;let points:[Int]}
            let frames:[Frame]
        }
        let file=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/CheckingProgress/retained-startup.json")
        let recording=try JSONDecoder().decode(Recording.self,from:Data(contentsOf:file))
        progress.reset();var firstHelp:Double?
        let began=recording.frames[0].capturedAt+recording.frames[0].ageSeconds
        for frame in recording.frames {
            let now=frame.capturedAt+frame.ageSeconds
            if progress.observe(scope:"retained-startup",reason:.requiredIntersections,points:frame.points,size:19,emptyGame:true,capturedAt:frame.capturedAt,now:now) != nil,firstHelp==nil {firstHelp=now}
        }
        check(recording.frames.count==600 && firstHelp != nil,"Retained60-second startup stall remained silent")
        check(firstHelp!-began>=3 && firstHelp!-began<3.3,"Retained stall missed the bounded explanation time")
        check(progress.help?.reason == .requiredIntersections && !(progress.help?.points.isEmpty ?? true),"Retained stall lost required-point explanation")
        progress.reset() // A real controller-confirmed board must clear the presentation.
        check(progress.help==nil,"Valid later recovery left a stale warning")
        print("PASS: \(checks) checking-progress checks; retained600-frame stall, bounded help, pause/gap/scope, orientation and recovery")
    }
}
