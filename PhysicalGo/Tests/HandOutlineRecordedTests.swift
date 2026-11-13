import Foundation

enum HandOutlineRecordedTests {
    struct Frame:Decodable {let index:Int;let time:Double;let pose:HandMotionPose?;let source:String;let disks:[[Double]]?}
    struct Group:Decodable {let name:String;let indices:[Int];let lower:Double;let upper:Double;let clearBy:Int?;let lastHand:Int?;let noEstimate:Bool?}
    struct Manifest:Decodable {let version:Int;let width:Int;let cells:Int;let scale:Float;let frames:[Frame];let groups:[Group]}
    static func run(folder:URL=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/HandOutline",isDirectory:true))throws->Int {
        let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:folder.appendingPathComponent("manifest.json")))
        precondition(manifest.version==1 && manifest.width==221 && manifest.cells==19)
        let process=Process(),pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:"/usr/bin/gzip")
        process.arguments=["-dc",folder.appendingPathComponent("pixels.u16.gz").path];process.standardOutput=pipe
        try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        let count=manifest.width*manifest.width
        precondition(process.terminationStatus==0 && data.count==manifest.frames.count*count*6)
        var frames=[Int:HandOutlineFrame]()
        data.withUnsafeBytes {raw in
            for (offset,frame) in manifest.frames.enumerated() {
                var pixels=[HandOutlineFrame.Pixel]();pixels.reserveCapacity(count)
                for i in 0..<count {
                    let at=(offset*count+i)*6
                    let r=UInt16(littleEndian:raw.loadUnaligned(fromByteOffset:at,as:UInt16.self))
                    let g=UInt16(littleEndian:raw.loadUnaligned(fromByteOffset:at+2,as:UInt16.self))
                    let light=UInt16(littleEndian:raw.loadUnaligned(fromByteOffset:at+4,as:UInt16.self))
                    pixels.append(light==65535 ? .invalid:.init(red:Float(r)/manifest.scale-1/3,green:Float(g)/manifest.scale-1/3,light:Float(light)/manifest.scale))
                }
                let stones=(frame.disks ?? []).map {HandOutlineFrame.WhiteStone(x:$0[0],y:$0[1],radiusX:$0[2],radiusY:$0[3])}
                frames[frame.index] = .init(width:manifest.width,cells:manifest.cells,pixels:pixels,whiteStones:stones)
            }
        }
        var checks=0
        let observations=Dictionary(uniqueKeysWithValues:manifest.frames.map{($0.index,$0)})
        for group in manifest.groups {
            var tracker=HandOutlineTracker(),estimates=[ClockPressEstimate](),retainedVisibleLoss=false
            for i in group.indices {
                let observation=observations[i]!
                let result=tracker.observe(frames[i]!,pose:observation.pose,at:observation.time,source:observation.source)
                if result.poseLost,result.obstructed==true,(result.depth ?? 0)>0 {retainedVisibleLoss=true}
                if let estimate=result.estimate {estimates.append(estimate)}
                if let clearBy=group.clearBy,i>=clearBy {
                    precondition(result.obstructed==false,"\(group.name): clear photographed board still blocked at frame\(i)");checks+=1
                }
                if let lastHand=group.lastHand,i==lastHand {
                    precondition(result.obstructed==true && result.estimate==nil,"Visible hand cleared before withdrawal");checks+=1
                }
                if group.name.hasPrefix("Black move 67"),observation.time<=group.lower,observation.time>=849482.79349 {
                    precondition(result.obstructed==true && result.estimate==nil,"Visible hand cleared early in recorded Black67 incident");checks+=1
                }
            }
            if group.noEstimate==true {
                precondition(estimates.isEmpty,"Weak chromatic motion fabricated a clock press");checks+=1
                continue
            }
            precondition(estimates.count==1,"\(group.name): expected one verified exit, got \(estimates.count)");checks+=1
            let e=estimates[0]
            precondition(e.valid && e.estimatedError != nil,"\(group.name): missing uncertainty");checks+=1
            precondition(e.time+e.estimatedError!>=group.lower && e.time-e.estimatedError!<=group.upper,"\(group.name): estimated band misses independent manual interval");checks+=1
            if group.name.hasPrefix("native") {precondition(retainedVisibleLoss,"\(group.name): visible fingers were lost with the pose");checks+=1}
        }
        print("PASS: \(checks) recorded-outline checks in \(folder.lastPathComponent); visible fingers retained and error bands checked against independent labels")
        return checks
    }
}
