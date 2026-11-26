import Foundation

@main struct HandBoardBoundaryTests {
    static func main()throws {
        setbuf(stdout,nil);var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;if !value {print("FAIL",message)};precondition(value,message)}
        let wood=HandBoardBoundary(size:9,vertices:[.init(x:-0.9,y:-0.9),.init(x:8.9,y:-0.9),
            .init(x:8.9,y:8.9),.init(x:-0.9,y:8.9)])!
        check(wood.contains(x:-0.8,y:4),"Wood margin beyond old grid guard is inside")
        check(!wood.contains(x:-1.0,y:4),"Outside wood is outside")
        check(!wood.contains(x:-1.0,y:-0.5),"Outside corner cannot borrow another edge's inside depth")
        check(try JSONDecoder().decode(HandBoardBoundary.self,from:JSONEncoder().encode(wood))==wood,"Boundary round trip")
        check(HandBoardBoundary(size:9,vertices:Array(wood.vertices.reversed()))==nil,"Reversed polygon rejected")
        for offset in 1..<4 {
            check(HandBoardBoundary(size:9,vertices:Array(wood.vertices[offset...])+Array(wood.vertices[..<offset]))==nil,
                  "Cyclic vertex rotation must not relabel top/right/bottom/left")
        }
        check(HandBoardBoundary(size:9,vertices:[.init(x:1,y:1),.init(x:7,y:1),.init(x:7,y:7),.init(x:1,y:7)])==nil,"Boundary excluding intersections rejected")
        check(HandBoardBoundary(size:9,vertices:[.init(x:-3,y:-1),.init(x:9,y:-1),.init(x:9,y:9),.init(x:-1,y:9)])==nil,"Boundary outside sampled image rejected")
        let skew=HandBoardBoundary(size:9,vertices:[.init(x:-0.9,y:-1.1),.init(x:8.8,y:-0.8),.init(x:9.1,y:8.9),.init(x:-0.7,y:9.2)])!
        check(skew.contains(x:0,y:0) && skew.contains(x:8,y:8),"Nonrectangular wood supported")
        // Root's November25 camera-only measurement. The physical border is
        // narrower than the old +/-0.75cell guard on this actual setup.
        let measured=HandBoardBoundary(size:19,vertices:[.init(x:-0.6642,y:-0.5702),.init(x:18.595,y:-0.5964),
            .init(x:18.6244,y:18.5844),.init(x:-0.6348,y:18.5637)])!
        for edge in 0..<4 {
            let a=measured.vertices[edge],b=measured.vertices[(edge+1)%4]
            let dx=b.x-a.x,dy=b.y-a.y,length=hypot(dx,dy)
            for along in [0.03,0.5,0.97] {
                let x=a.x+(b.x-a.x)*along,y=a.y+(b.y-a.y)*along
                let outside=HandMotionPose.Point(id:"finger",x:x+dy/length*0.08,y:y-dx/length*0.08,confidence:0.9)
                let inside=HandMotionPose.Point(id:"finger",x:x-dy/length*0.08,y:y+dx/length*0.08,confidence:0.9)
                check(HandMotionPose(hands:[[outside]]).obstructed(size:19,boundary:measured)==false,"Measured exterior ignored")
                check(HandMotionPose(hands:[[inside]]).obstructed(size:19,boundary:measured)==true,"Measured shallow interior detected")
            }
        }
        let clear=HandMotionPose(hands:[]),n=121
        func rotate(_ x:Double,_ y:Double,_ edge:Int)->(Double,Double) {
            switch edge {case 1:return (8-y,x);case 2:return (x,8-y);case 3:return (y,x);default:return(x,y)}
        }
        func frame(edge:Int=0,tip:Double?=nil,lateral:Double=4,boundary:HandBoardBoundary?=wood)->HandOutlineFrame {
            var pixels=[HandOutlineFrame.Pixel]()
            for row in 0..<n {for col in 0..<n {
                let x=Double(col)/10-2,y=Double(row)/10-2
                let d=[y+0.9,8.9-x,8.9-y,x+0.9][edge],side=edge%2==0 ? x:y
                let hand=tip.map{d<=$0 && abs(side-lateral)<0.4} ?? false
                pixels.append(hand ? .init(red:0.20,green:-0.04,light:0.4):
                    .init(red:0.10,green:0.02,light:Float(0.55+0.05*sin(x*4)+0.05*cos(y*3))))
            }}
            return .init(width:n,cells:9,pixels:pixels,boundary:boundary)
        }
        func pose(edge:Int,y:Double,lateral:Double=4,reliable:Bool=true)->HandMotionPose {
            let count=reliable ? 8:1
            return .init(hands:[(0..<count).map{i in
                let p=rotate(lateral+Double(i%2)*0.05,y-Double(i/2)*0.05,edge)
                return .init(id:"j\(i)",x:p.0,y:p.1,confidence:0.9)
            }],reliable:reliable)
        }
        for edge in 0..<4 {for lateral in [0.0,4.0,8.0] {
            var tracker=HandOutlineTracker()
            for t in [0.0,0.1,0.2] {_=tracker.observe(frame(),pose:clear,at:t,source:"wood")}
            // Moving outside the physical wood, including an incomplete pose,
            // must not invalidate fresh unchanged pixels just inside that edge.
            for (t,tip) in [(0.3,-0.3),(0.4,-0.15),(0.5,-0.2)] {
                let outside=pose(edge:edge,y:-1.2,lateral:lateral,reliable:false)
                check(tracker.observe(frame(edge:edge,tip:tip,lateral:lateral),pose:outside,at:t,source:"wood").obstructed==false,
                      "Sparse outside-only motion interrupted edge\(edge), lateral\(lateral)")
            }
            let shallow=pose(edge:edge,y:-0.7,lateral:lateral)
            check(shallow.obstructed(size:9,boundary:wood)==true,"Shallow physical wood entry is obstructing")
            check(tracker.observe(frame(edge:edge,tip:0.3,lateral:lateral),pose:shallow,at:0.6,source:"wood").obstructed==true,
                  "Shallow entry without grid penetration must stop")
            for t in [0.7,0.8] {
                let lost=tracker.observe(frame(edge:edge,tip:0.3,lateral:lateral),pose:clear,at:t,source:"wood")
                check(lost.obstructed==true,
                      "Tracked shallow hand must not disappear when joints are missed: edge\(edge), lateral\(lateral), time\(t), \(lost.reason)")
            }
            check(tracker.observe(frame(edge:edge,tip:-0.2,lateral:lateral),pose:pose(edge:edge,y:-1.2,lateral:lateral),at:0.9,source:"wood").obstructed==true,
                  "First exit remains pending independent visual confirmation")
            check(tracker.observe(frame(edge:edge,tip:-0.3,lateral:lateral),pose:pose(edge:edge,y:-1.2,lateral:lateral),at:1.0,source:"wood").obstructed==false,
                  "Outside-only movement must not retain an exited hand")
            // Partial interior pose has no clearance proof and cannot exploit
            // the new outside-only exception.
            let partial=pose(edge:edge,y:-0.7,lateral:lateral,reliable:false)
            check(tracker.observe(frame(edge:edge,tip:0.3,lateral:lateral),pose:partial,at:1.1,source:"wood").obstructed != false,
                  "Sparse interior pose must remain unknown/blocked")
        }}
        // Exterior motion, isolated edge/corner stones and the laser dot do
        // not create a crossing hand. Texture-preserving light changes are
        // nuisance controls, not clearance from mean brightness alone.
        for edge in 0..<4 {for lateral in [0.0,4.0,8.0] {
            for scenario in ["outside","black","white","dot","exposure","shadow","shadow finger","outside texture finger","bowl bridge"] {
                let background=frame()
                var pixels=background.pixels
                for i in pixels.indices {
                    let (x,y)=background.grid(i),d=[y+0.9,8.9-x,8.9-y,x+0.9][edge],side=edge%2==0 ? x:y
                    let center=rotate(lateral,0,edge),disk=hypot(x-center.0,y-center.1)<0.45
                    switch scenario {
                    case "outside":if d < -0.05 && abs(side-lateral)<0.4 {pixels[i] = .init(red:0.2,green:-0.04,light:0.4)}
                    case "black":if disk {pixels[i] = .init(red:0,green:0,light:0.03)}
                    case "white":if disk {pixels[i] = .init(red:0,green:0,light:0.95)}
                    case "dot":if hypot(x-center.0,y-center.1)<0.15 {pixels[i] = .init(red:0.6,green:-0.3,light:0.95)}
                    case "exposure":pixels[i].light=pixels[i].light*1.15+0.02
                    case "shadow","shadow finger","outside texture finger":
                        if d<1.2 && abs(side-lateral)<0.4 {pixels[i].light*=0.75}
                        if scenario != "shadow",d>=0,d<0.4,abs(side-lateral)<0.3 {
                            pixels[i] = scenario=="outside texture finger" ? .init(red:0.10,green:0.02,light:0.40):
                                .init(red:0.04,green:0,light:0.95)
                        }
                    default:
                        let bowl=d < -0.15 && abs(side-lateral)<0.5
                        let bridge=d<1 && abs(side-lateral)<0.01
                        if disk || bowl || bridge {pixels[i] = .init(red:0,green:0,light:0.05)}
                    }
                }
                let changed=HandOutlineFrame(width:n,cells:9,pixels:pixels,boundary:wood)
                var tracker=HandOutlineTracker()
                for t in [0.0,0.1,0.2] {_=tracker.observe(background,pose:clear,at:t,source:"controls")}
                for t in [0.3,0.4] {
                    let finger=scenario=="shadow finger" || scenario=="outside texture finger"
                    check(tracker.observe(changed,pose:clear,at:t,source:"controls").obstructed==finger,
                          "Outside/stone/light control seeded hand: \(scenario), edge\(edge), lateral\(lateral)")
                }
            }
        }}
        for edge in 0..<4 {for lateral in [0.0,4.0,8.0] {
            var missed=HandOutlineTracker()
            for t in [0.0,0.1,0.2] {_=missed.observe(frame(),pose:clear,at:t,source:"missed")}
            check(missed.observe(frame(edge:edge,tip:0.3,lateral:lateral),pose:clear,at:0.3,source:"missed").obstructed==true,
                  "Boundary-crossing shallow fingertip must seed without a hand pose")
        }}
        var missed=HandOutlineTracker()
        for t in [0.0,0.1,0.2] {_=missed.observe(frame(),pose:clear,at:t,source:"missed")}
        var mismatch=frame()
        mismatch.boundary=HandBoardBoundary(size:19,vertices:[.init(x:-1,y:-1),.init(x:19,y:-1),.init(x:19,y:19),.init(x:-1,y:19)])
        check(missed.observe(mismatch,pose:clear,at:0.4,source:"missed").obstructed==nil,"Wrong board-size perimeter is unknown")
        print("PASS: \(checks) explicit wood-boundary checks; camera detector recall is not simulated")
    }
}
