import Foundation

/// Offline evidence export only. Reuses production tracker; never invokes a game or clock.
@main struct HandClearanceAudit {
    struct Frame:Decodable {let index:Int;let time:Double;let pose:HandMotionPose?;let source:String;let disks:[[Double]]?}
    struct Group:Decodable {let name:String;let indices:[Int];let lower:Double;let upper:Double;let clearBy:Int?;let lastHand:Int?;let noEstimate:Bool?}
    struct Manifest:Decodable {let version:Int;let width:Int;let cells:Int;let scale:Float;let frames:[Frame];let groups:[Group]}
    static func json<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))}
    static func main()throws {
        var rows=[[String:Any]]()
        for name in CommandLine.arguments.dropFirst() {
            let folder=URL(fileURLWithPath:name)
            let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:folder.appendingPathComponent("manifest.json")))
            let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/gzip")
            process.arguments=["-dc",folder.appendingPathComponent("pixels.u16.gz").path];process.standardOutput=pipe
            try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
            let count=manifest.width*manifest.width
            precondition(process.terminationStatus==0 && data.count==manifest.frames.count*count*6)
            var frames=[Int:HandOutlineFrame]()
            data.withUnsafeBytes {raw in
                for (offset,frame) in manifest.frames.enumerated() {
                    let pixels=(0..<count).map {i -> HandOutlineFrame.Pixel in
                        let at=(offset*count+i)*6
                        let r=UInt16(littleEndian:raw.loadUnaligned(fromByteOffset:at,as:UInt16.self))
                        let g=UInt16(littleEndian:raw.loadUnaligned(fromByteOffset:at+2,as:UInt16.self))
                        let light=UInt16(littleEndian:raw.loadUnaligned(fromByteOffset:at+4,as:UInt16.self))
                        return light==65535 ? .invalid:.init(red:Float(r)/manifest.scale-1/3,green:Float(g)/manifest.scale-1/3,light:Float(light)/manifest.scale)
                    }
                    frames[frame.index] = .init(width:manifest.width,cells:manifest.cells,pixels:pixels,
                        whiteStones:(frame.disks ?? []).map{.init(x:$0[0],y:$0[1],radiusX:$0[2],radiusY:$0[3])})
                }
            }
            let observations=Dictionary(uniqueKeysWithValues:manifest.frames.map{($0.index,$0)})
            for group in manifest.groups {
                for fault in ["original","missing-pose","camera-gap"] {
                    var tracker=HandOutlineTracker(),prior:Double?
                    for i in group.indices {
                        let f=observations[i]!,time=f.time+(fault=="camera-gap" && f.time>=group.lower ? 2:0)
                        let drop=fault=="missing-pose" && f.time>=group.lower-0.35 && f.time<=group.upper+0.2
                        let pose=drop ? nil:f.pose
                        let result=tracker.observe(frames[i]!,pose:pose,at:time,source:f.source)
                        let truth:String
                        if i==group.lastHand || (f.time>=group.lower-0.3 && f.time<=group.lower) {truth="hand"}
                        else if f.time>=group.upper && (group.clearBy.map{i>=$0} ?? true) {truth="clear"}
                        else {truth="unlabeled"}
                        rows.append(["case":folder.lastPathComponent+":"+group.name,"fault":fault,"frame":i,"time":time,
                                     "gap":prior.map{time-$0>0.65} ?? false,"truth":truth,"poseClear":pose?.obstructed(size:manifest.cells) == false,
                                     "result":try json(result)])
                        prior=time
                    }
                }
            }
        }
        // An actual visible fingertip can remain motionless in the guard rim with no pose.
        // Test all four sides and a complete pose miss; time alone must not clear it.
        for edge in 0..<4 {
            let n=121,size=9
            func frame(_ depth:Double?)->HandOutlineFrame {
                let pixels=(0..<n*n).map {i -> HandOutlineFrame.Pixel in
                    let x=Double(i%n)/10-2,y=Double(i/n)/10-2
                    let d=[y+0.75,8.75-x,8.75-y,x+0.75][edge],lateral=edge%2==0 ? x:y
                    let covered=depth.map{d<=$0 && (2...5).contains(lateral)} ?? false
                    return covered ? .init(red:0.12,green:-0.02,light:0.55):.init(red:0.10,green:0.02,light:0.65)
                }
                return .init(width:n,cells:size,pixels:pixels)
            }
            func pose()->HandMotionPose {
                .init(hands:[(0..<12).map{i in
                    let x=3+Double(i%3)*0.25,y=i==0 ? -1:0.6+Double(i/3)*0.1
                    let xy=edge==1 ? (8-y,x):edge==2 ? (8-x,8-y):edge==3 ? (y,8-x):(x,y)
                    return .init(id:i==0 ? "VNHLKWRI":"p\(i)",x:xy.0,y:xy.1,confidence:0.95)
                }])
            }
            for mode in ["pose-lost-at-rim","pose-missed-entirely","camera-gap-at-rim"] {
                var tracker=HandOutlineTracker(),prior:Double?
                for i in 0..<40 {
                    let time=Double(i)*0.2+(mode=="camera-gap-at-rim" && i>=8 ? 2:0)
                    let depth:Double?=i<3 ? nil:i<6 ? 4:0.15
                    let p=mode=="pose-missed-entirely" || i<3 || i>=6 ? HandMotionPose(hands:[]):pose()
                    let result=tracker.observe(frame(depth),pose:p,at:time,source:"synthetic")
                    rows.append(["case":"synthetic-rim-edge-\(edge)","fault":mode,"frame":i,"time":time,
                                 "gap":prior.map{time-$0>0.65} ?? false,"truth":i<3 ? "clear":"hand","poseClear":p.obstructed(size:size)==false,
                                 "result":try json(result)])
                    prior=time
                }
            }
        }
        print(String(decoding:try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]),as:UTF8.self))
    }
}
