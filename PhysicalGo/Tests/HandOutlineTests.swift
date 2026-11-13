import Foundation
@main struct HandOutlineTests {
    static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let clear=HandMotionPose(hands:[]),size=9,n=121
        func frame(_ depth:Double?,edge:Int=0,stone:Bool=false)->HandOutlineFrame {
            var pixels=[HandOutlineFrame.Pixel]()
            for row in 0..<n {for col in 0..<n {
                let x=Double(col)/10-2,y=Double(row)/10-2
                let d=[y+0.75,8.75-x,8.75-y,x+0.75][edge],lateral=edge%2==0 ? x:y
                let hand=depth.map{d <= $0 && (2...5).contains(lateral)} ?? false
                let placed=stone && hypot(x-3.5,y-3)<0.45
                pixels.append(hand ? .init(red:0.12,green:-0.02,light:0.55):placed ? .init(red:0,green:0,light:0.95):.init(red:0.10,green:0.02,light:0.65))
            }}
            return .init(width:n,cells:size,pixels:pixels)
        }
        func pose(edge:Int)->HandMotionPose {
            func rotate(_ x:Double,_ y:Double)->(Double,Double) {
                switch edge {case 1:return (8-y,x);case 2:return (8-x,8-y);case 3:return (y,8-x);default:return(x,y)}
            }
            return .init(hands:[(0..<12).map{i in
                let p=rotate(3+Double(i%3)*0.25,i==0 ? -1:0.6+Double(i/3)*0.1)
                return .init(id:i==0 ? "VNHLKWRI":"p\(i)",x:p.0,y:p.1,confidence:0.95)
            }])
        }
        for edge in 0..<4 {
            var tracker=HandOutlineTracker()
            for t in [0.0,0.1,0.2] {_=tracker.observe(frame(nil,edge:edge),pose:clear,at:t,source:"test")}
            for (t,d) in [(0.3,4.0),(0.4,2.0)] {
                check(tracker.observe(frame(d,edge:edge),pose:pose(edge:edge),at:t,source:"test").obstructed==true,"Visible hand was not tracked")
            }
            let lost=tracker.observe(frame(0.5,edge:edge),pose:clear,at:0.5,source:"test")
            check(lost.obstructed==true && lost.poseLost,"Pose loss falsely cleared visible fingers")
            let pending=tracker.observe(frame(-0.5,edge:edge),pose:clear,at:0.6,source:"test")
            check(pending.obstructed==true && pending.estimate==nil,"First clear view bypassed confirmation")
            let done=tracker.observe(frame(nil,edge:edge),pose:clear,at:0.7,source:"test")
            check(done.obstructed==false && done.estimate != nil,"Visual exit was not verified")
            check(done.estimate!.method == .handMotion && abs(done.estimate!.time-0.55)<0.02,"Outline motion did not interpolate crossing")
            check(done.estimate!.observedUpper==0.6 && done.estimate!.estimatedError!>0,"Confirmation delay replaced original press or erased error")
            check(tracker.observe(frame(nil,edge:edge),pose:clear,at:0.8,source:"test").estimate==nil,"One withdrawal emitted two presses")
        }
        var tracker=HandOutlineTracker()
        for t in [0.0,0.1,0.2] {_=tracker.observe(frame(nil),pose:clear,at:t,source:"test")}
        _=tracker.observe(frame(4),pose:pose(edge:0),at:0.3,source:"test")
        let gap=tracker.observe(frame(nil),pose:clear,at:2,source:"test")
        check(gap.estimate==nil && gap.obstructed==nil,"Camera gap fabricated an exit")
        for t in [2.1,2.2] {_=tracker.observe(frame(nil),pose:clear,at:t,source:"test")}
        _=tracker.observe(frame(4),pose:pose(edge:0),at:2.3,source:"test")
        let mixed=tracker.observe(frame(nil),pose:clear,at:2.4,source:"different")
        check(mixed.estimate==nil && mixed.obstructed==nil,"Timestamp source change preserved stale motion")
        var timing=HandOutlineTiming()
        timing.observe(depth:1,at:1);timing.observe(depth:1,at:1.2)
        check(timing.estimate(firstClear:1.4,source:"test")?.method == .handBracket,"Stationary hand invented a speed")
        check(abs(timing.estimate(firstClear:1.4,source:"test")!.time-1.3)<1e-6,"Fallback clock press should use the interval midpoint")
        let dark=HandOutlineFrame(width:n,cells:size,pixels:Array(repeating:.invalid,count:n*n))
        check(tracker.observe(dark,pose:clear,at:2.5,source:"different").obstructed==nil,"Darkness was accepted as visible clearance")
        // A warm lighting change preserves board texture. Real fingertips in
        // that same region must still obstruct it after pose recognition drops.
        func textured(_ depth:Double?,shadow:Bool,edge:Int)->HandOutlineFrame {
            var pixels=[HandOutlineFrame.Pixel]()
            for row in 0..<n {for col in 0..<n {
                let x=Double(col)/10-2,y=Double(row)/10-2
                let d=[y+0.75,8.75-x,8.75-y,x+0.75][edge],lateral=edge%2==0 ? x:y
                let light=Float(0.6+0.12*sin(x*5)+0.12*cos(y*6))
                let region=(2...5).contains(lateral) && d<=4
                if region,let depth,d<=depth {
                    pixels.append(.init(red:0.12,green:-0.02,light:0.55))
                } else if shadow && region {
                    pixels.append(.init(red:0.12,green:-0.02,light:light*0.9+0.02))
                } else {pixels.append(.init(red:0.10,green:0.02,light:light))}
            }}
            return .init(width:n,cells:size,pixels:pixels)
        }
        for edge in 0..<4 {
            var tracker=HandOutlineTracker()
            for t in [0.0,0.1,0.2] {_=tracker.observe(textured(nil,shadow:false,edge:edge),pose:clear,at:t,source:"test")}
            for t in [0.3,0.4] {
                check(tracker.observe(textured(4,shadow:false,edge:edge),pose:pose(edge:edge),at:t,source:"test").obstructed==true,"Texture filter removed a visible hand")
            }
            let fingers=tracker.observe(textured(0.5,shadow:true,edge:edge),pose:clear,at:0.5,source:"test")
            check(fingers.obstructed==true && fingers.estimate==nil,"Lighting change hid remaining fingers")
            let first=tracker.observe(textured(nil,shadow:true,edge:edge),pose:clear,at:0.6,source:"test")
            check(first.obstructed==true && first.estimate==nil,"Texture filter bypassed two-frame clearance")
            let done=tracker.observe(textured(nil,shadow:true,edge:edge),pose:clear,at:0.7,source:"test")
            check(done.obstructed==false && done.estimate?.observedUpper==0.6,"Lighting change prolonged a completed withdrawal")
        }
        let disk=HandOutlineFrame.WhiteStone(x:3.5,y:0,radiusX:0.44,radiusY:0.47)
        var covered=frame(0.5);covered.whiteStones=[disk]
        check(covered.verifiedWhiteStones.isEmpty,"A visible fingertip inherited a stone's clearance mask")
        var wood=frame(nil);wood.whiteStones=[disk]
        check(wood.verifiedWhiteStones.isEmpty,"A shape hint alone masked bare wood")
        var visible=covered.pixels
        for i in visible.indices {let p=covered.grid(i)
            if pow((p.0-disk.x)/disk.radiusX,2)+pow((p.1-disk.y)/disk.radiusY,2)<1 {visible[i] = .init(red:0,green:0,light:0.95)}
        }
        let beside=HandOutlineFrame(width:n,cells:size,pixels:visible,whiteStones:[disk])
        check(beside.verifiedWhiteStones.count==1,"A clear white core was not verified")
        var adjacent=HandOutlineTracker()
        for t in [0.0,0.1,0.2] {_=adjacent.observe(frame(nil),pose:clear,at:t,source:"stone")}
        _=adjacent.observe(frame(4),pose:pose(edge:0),at:0.3,source:"stone")
        for t in [0.4,0.5,0.6] {
            check(adjacent.observe(beside,pose:clear,at:t,source:"stone").obstructed==true,"Stone mask erased adjacent fingers after pose loss")
        }
        var narrow=frame(nil).pixels
        for i in narrow.indices {let p=covered.grid(i)
            if pow((p.0-disk.x)/disk.radiusX,2)+pow((p.1-disk.y)/disk.radiusY,2)<1 {narrow[i] = .init(red:0,green:0,light:0.95)}
            if (3.3...3.7).contains(p.0),p.1 <= -0.45 {narrow[i] = .init(red:0.12,green:-0.02,light:0.55)}
        }
        let rimFinger=HandOutlineFrame(width:n,cells:size,pixels:narrow,whiteStones:[disk])
        check(rimFinger.verifiedWhiteStones.count==1,"Rim-finger fixture must retain its visible white core")
        var rim=HandOutlineTracker()
        for t in [0.0,0.1,0.2] {_=rim.observe(frame(nil),pose:clear,at:t,source:"rim")}
        _=rim.observe(frame(4),pose:pose(edge:0),at:0.3,source:"rim")
        for t in [0.4,0.5,0.6] {
            check(rim.observe(rimFinger,pose:clear,at:t,source:"rim").obstructed==true,"White-stone fringe hid a narrow fingertip at the rim")
        }
        func rimGrain(shadow:Bool,finger:Bool)->HandOutlineFrame {
            var pixels=[HandOutlineFrame.Pixel]()
            for i in 0..<n*n {let p=covered.grid(i),light=Float(0.6+0.015*sin(p.0*5)+0.015*cos(p.1*6))
                if finger,(3.3...3.7).contains(p.0),p.1 <= -0.45 {pixels.append(.init(red:0.12,green:-0.02,light:0.45))}
                else if shadow,(2...5).contains(p.0),p.1 <= -0.35 {pixels.append(.init(red:0.12,green:-0.02,light:light*0.9+0.02))}
                else {pixels.append(.init(red:0.10,green:0.02,light:light))}
            }
            return .init(width:n,cells:size,pixels:pixels)
        }
        var grain=HandOutlineTracker()
        for t in [0.0,0.1,0.2] {_=grain.observe(rimGrain(shadow:false,finger:false),pose:clear,at:t,source:"grain")}
        _=grain.observe(frame(4),pose:pose(edge:0),at:0.3,source:"grain")
        for t in [0.4,0.5,0.6] {
            check(grain.observe(rimGrain(shadow:true,finger:true),pose:clear,at:t,source:"grain").obstructed==true,"Spatial averaging hid a small finger in low-contrast rim grain")
        }
        _=grain.observe(rimGrain(shadow:true,finger:false),pose:clear,at:0.7,source:"grain")
        check(grain.observe(rimGrain(shadow:true,finger:false),pose:clear,at:0.8,source:"grain").obstructed==false,"Preserved low-contrast rim grain remained a hand")
        func cornerPatch(outside:Bool)->HandOutlineFrame {
            var pixels=frame(nil).pixels
            for i in pixels.indices {let p=covered.grid(i)
                if p.0 >= (outside ? 9:6),p.1<=3 {pixels[i] = .init(red:0.12,green:-0.02,light:0.55)}
            }
            return .init(width:n,cells:size,pixels:pixels)
        }
        let cornerPose=HandMotionPose(hands:pose(edge:0).hands.map{$0.map{.init(id:$0.id,x:$0.x+4,y:$0.y,confidence:$0.confidence)}})
        var corner=HandOutlineTracker()
        for t in [0.0,0.1,0.2] {_=corner.observe(frame(nil),pose:clear,at:t,source:"corner")}
        check(corner.observe(cornerPatch(outside:false),pose:cornerPose,at:0.3,source:"corner").obstructed==true,"Actual corner hand was not blocked")
        _=corner.observe(cornerPatch(outside:true),pose:clear,at:0.4,source:"corner")
        check(corner.observe(cornerPatch(outside:true),pose:clear,at:0.5,source:"corner").obstructed==false,"A patch beyond the corner counted as over the board")
        print("PASS: \(checks) outline checks: four edges, lost poses, visual confirmation, original press/error, gaps, timestamp epochs, stationary motion and white-stone mask safety")
        _=try HandOutlineRecordedTests.run()
        _=try HandOutlineRecordedTests.run(folder:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/ClockCatchUpLoss/Outline"))
        _=try HandOutlineRecordedTests.run(folder:URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/A18HandOutline"))
    }
}
