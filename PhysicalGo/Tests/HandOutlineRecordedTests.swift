import Foundation

enum HandOutlineRecordedTests {
    struct Frame:Decodable {let index:Int;let time:Double;let pose:HandMotionPose?;let source:String}
    struct Group:Decodable {let name:String;let indices:[Int];let lower:Double;let upper:Double}
    struct Manifest:Decodable {let version:Int;let width:Int;let cells:Int;let scale:Float;let frames:[Frame];let groups:[Group]}
    static func run()throws->Int {
        let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/HandOutline",isDirectory:true)
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
                frames[frame.index] = .init(width:manifest.width,cells:manifest.cells,pixels:pixels)
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
            }
            precondition(estimates.count==1,"\(group.name): expected one verified exit, got \(estimates.count)");checks+=1
            let e=estimates[0]
            precondition(e.valid && e.estimatedError != nil,"\(group.name): missing uncertainty");checks+=1
            precondition(e.time+e.estimatedError!>=group.lower && e.time-e.estimatedError!<=group.upper,"\(group.name): estimated band misses independent manual interval");checks+=1
            if group.name.hasPrefix("native") {precondition(retainedVisibleLoss,"\(group.name): visible fingers were lost with the pose");checks+=1}
        }
        print("PASS: \(checks) recorded-outline checks across three captured withdrawals at native/5 fps sampling; pose loss retained and error bands checked against independent labels")
        return checks
    }
}
