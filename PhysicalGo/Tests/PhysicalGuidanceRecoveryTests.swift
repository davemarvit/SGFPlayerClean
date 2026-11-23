import Foundation
@main struct PhysicalGuidanceRecoveryTests {
    typealias R=PhysicalGuidanceRecovery<String,String,Int>
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ name:String) {precondition(condition,name);checks+=1}
        let epoch=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
        let scope=R.Scope(schema:2,session:"game",context:"camera",epoch:epoch)
        let operation=R.Operation(target:"E5",owner:"game")
        let receipt=R.Receipt(scope:scope,setup:"setup",offSince:0,watermark:1)
        func begin(_ target:String?="E5",schema:Int=2)->R.Event {
            .begin(.init(schema:schema,session:"game",context:"camera",epoch:epoch),.init(target:target,owner:target==nil ? nil:"game"),setup:"setup",cause:.hand,at:0)
        }
        func observe(_ at:Double,target:String?="E5",now:Double?=nil,admitted:Bool=true,off:R.Receipt?=nil,hasOFF:Bool=true,cause:R.Cause? = .hand,scope current:R.Scope?=nil)->R.Event {
            .observe(.init(scope:current ?? scope,target:target,enabled:true,cause:cause,receipt:hasOFF ? off ?? receipt:nil,clearAt:at,frameAdmissible:admitted,now:now ?? at))
        }
        func verify(_ at:Double,now:Double?=nil,clear:Double?=nil,off:Bool=true,admitted:Bool=true)->R.Event {
            .verify(.init(enabled:true,hasTarget:true,capturedAt:at,clearAt:clear ?? at,healthyOFF:off,frameAdmissible:admitted,now:now ?? at))
        }
        func replay(_ events:[R.Event],_ name:String)->[R.Effect] {
            var reducer=R(),baseline=GuidanceRecoveryBaseline(),effects:[R.Effect]=[]
            for (i,event) in events.enumerated() {
                let actual=reducer.reduce(event),expected=baseline.reduce(event)
                check(actual==expected,"Baseline effect parity \(name) #\(i)")
                check(reducer.isPending==baseline.isPending,"Baseline ownership parity \(name) #\(i)")
                effects.append(actual)
            }
            return effects
        }
        let ready:[R.Event]=[begin(),observe(0.25),observe(0.50),observe(0.75)]
        let direct=replay(ready+[verify(0.75)],"target verifier handoff")
        check(direct[3] == .none && direct[4] == .recovered(at:0.75,cause:.hand),"Targetful proof holds OFF until purpose verifier")
        let targetless=replay([begin(nil),observe(0.25,target:nil),observe(0.5,target:nil),observe(0.75,target:nil)],"targetless")
        check(targetless.last! == .recovered(at:0.75,cause:.hand),"Targetless recovery completes without target verifier")
        for t in [0.499999,0.5,0.500001] {
            let result=replay(ready+[verify(0.75,now:0.75+t)],"freshness boundary")
            check((result.last! != .none)==(t<0.5),"Half-second verification freshness is strict")
        }
        for delta in [0.0000005,0.000001,0.000002] {
            let result=replay(ready+[verify(0.75+delta,clear:0.75)],"exact verdict stamp")
            check((result.last! != .none)==(delta<0.000001),"Verification belongs to exact verdict")
        }
        for (first,last) in [(0.25,0.699999),(0.25,0.70),(0.25,0.700001)] {
            let result=replay([begin(),observe(first),observe(0.5),observe(last),verify(last)],"witness span")
            check((result.last! != .none)==(last-first>=0.45),"Witness span retains baseline floating point threshold")
        }
        for gap in [0.599999,0.6,0.600001] {
            let end=0.25+gap
            let result=replay([begin(),observe(0.25),observe(end),observe(end+0.25),verify(end+0.25)],"witness gap")
            check((result.last! != .none)==(end-0.25<=0.6),"Large witness gap restarts streak")
        }
        let duplicate=replay([begin(),observe(0.25),observe(0.25,admitted:false),observe(0.5),observe(0.5,admitted:false),observe(0.75),verify(0.75)],"frame-before-verdict duplicate")
        check(duplicate.last! == .recovered(at:0.75,cause:.hand),"New publication before duplicate verdict does not erase witnesses")
        for changed in [R.Receipt(scope:scope,setup:"setup",offSince:0.1,watermark:1),R.Receipt(scope:scope,setup:"setup",offSince:0,watermark:2)] {
            let result=replay(ready+[observe(0.75,admitted:false,off:changed),verify(0.75)],"changed OFF boundary before duplicate")
            check(result.last! == .none,"Changed boundary revokes ready proof before duplicate handling")
        }
        for invalid in [observe(0.75,hasOFF:false),observe(0.75,now:1.25),observe(0.8,admitted:false)] {
            let result=replay(ready+[invalid,verify(0.75)],"missing or stale proof")
            check(result.last! == .none,"Missing/stale evidence resets witnesses")
        }
        for bad in [R.Scope(schema:1,session:"game",context:"camera",epoch:epoch),R.Scope(schema:2,session:"other",context:"camera",epoch:epoch),R.Scope(schema:2,session:"game",context:"other",epoch:epoch),R.Scope(schema:2,session:"game",context:"camera",epoch:nil)] {
            let result=replay(ready+[observe(0.75,scope:bad),verify(0.75)],"scope revocation")
            check(result[result.count-2] == .scopeChanged && result.last! == .none,"Scope change cannot consume old proof")
        }
        for bad in [R.Receipt(scope:scope,setup:"other",offSince:0,watermark:1),R.Receipt(scope:.init(schema:2,session:"game",context:"camera",epoch:nil),setup:"setup",offSince:0,watermark:1)] {
            let result=replay(ready+[observe(0.75,off:bad),verify(0.75)],"wrong receipt")
            check(result.last! == .none,"Wrong setup or missing v2 epoch resets proof")
        }
        let retarget=R.Event.retarget(scope,.init(target:"F5",owner:"game"),cause:.hand,permitted:true,at:0.8)
        let changed=replay(ready+[retarget,verify(0.75),observe(1,target:"F5"),observe(1.25,target:"F5"),observe(1.5,target:"F5"),verify(1.5)],"same-game retarget")
        check(changed[4] == .requestOFF && changed[5] == .none && changed.last! == .recovered(at:1.5,cause:.hand),"Retarget earns new OFF and independent witnesses")
        let foreign=replay(ready+[.retarget(scope,.init(target:"foreign",owner:"other"),cause:.hand,permitted:true,at:0.8)],"foreign target")
        check(foreign.last! == .none,"Active session cannot disguise target's foreign owner")
        let noOwner=R.Scope(schema:1,session:nil,context:"camera",epoch:epoch)
        let noOwnerTrace=replay([.begin(noOwner,.init(target:nil,owner:nil),setup:nil,cause:.hand,at:0),.retarget(noOwner,.init(target:"E5",owner:nil),cause:.hand,permitted:true,at:1)],"missing owner")
        check(noOwnerTrace.last! == .none,"Absent owner cannot authorize a new target")
        for terminal in [R.Event.cancel,observe(0.75,cause:nil)] {
            let result=replay(ready+[terminal,verify(0.75)],"pause/hard/superseding cancellation")
            check(result.last! == .none,"Cancelled proof never grants admission")
        }
        for cause in R.Cause.allCases {
            let result=replay(ready+[observe(0.75,cause:cause),verify(0.75)],"typed cause")
            check(result.last! == .recovered(at:0.75,cause:cause),"Recovered effect carries the current typed cause")
        }
        // Deterministic event-order permutations compare the frozen baseline
        // after every event, including duplicates, delayed receipts and retargets.
        var seed:UInt64=0x5eed
        for trace in 0..<200 {
            var events:[R.Event]=[begin()],time=0.0
            for _ in 0..<40 {
                seed=seed &* 6364136223846793005 &+ 1
                time+=Double((seed>>32)%4)*0.125
                switch seed%9 {
                case 0:events.append(observe(time,admitted:false))
                case 1:events.append(observe(time,hasOFF:false))
                case 2:events.append(verify(time))
                case 3:events.append(.retarget(scope,operation,cause:.hand,permitted:true,at:time))
                case 4:events.append(.begin(scope,operation,setup:"setup",cause:.camera,at:time))
                default:events.append(observe(time))
                }
            }
            _=replay(events,"seeded \(trace)")
        }
        print("PASS \(checks) scoped guidance recovery checks")
    }
}
