import Foundation
import CoreGraphics

@main struct EpochCacheTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PhysicalGoEpoch-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let output=root.appendingPathComponent("frames")
        let bytes=Data(repeating:255,count:4)
        let oldImage=CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:2,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:bytes as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let newImage=CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:2,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:bytes as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let oldBytes=Data("FAKE_ENCODER_OLD_EPOCH".utf8),newBytes=Data("FAKE_ENCODER_NEW_EPOCH".utf8)
        let blocked=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        var encodes=0,checks=0
        func check(_ value:Bool,_ text:String){checks+=1;precondition(value,text)}
        let broker=PhysicalLaserFrameBroker(directory:output,encodeImage:{image in
            encodes+=1
            if encodes==2 {blocked.signal();precondition(release.wait(timeout:.now()+5) == .success,"Test release timed out")}
            return image === oldImage ? oldBytes:newBytes
        })
        let frame1=broker.frame(capturedAt:1,timestamp:nil,now:1,wall:1001)
        broker.prepare(oldImage,frame:frame1);broker.flushForTesting()
        check(encodes==1,"First old-epoch pixels not cached")
        let frame2=broker.frame(capturedAt:2,timestamp:nil,now:2,wall:1002)
        broker.prepare(oldImage,frame:frame2)
        check(blocked.wait(timeout:.now()+5) == .success,"Encoder did not block")
        broker.resetStream() // Cache clear queues behind the currently running drain.
        let fresh=broker.frame(capturedAt:3,timestamp:nil,now:3,wall:1003)
        check(fresh.frameID==frame1.frameID && fresh.streamEpoch != frame1.streamEpoch,"Did not reproduce reused ID after reset")
        broker.offer(newImage,frame:fresh,cameraID:"test",context:"new",reference:nil,current:nil,hand:true,aligned:false)
        release.signal();broker.flushForTesting()
        let path=output.appendingPathComponent("latest.json")
        let manifest=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:path))
        let published=try Data(contentsOf:output.appendingPathComponent(manifest.imageFile))
        check(manifest.frame==fresh && manifest.handObstructed==true && !manifest.alignmentValid,"New-frame metadata mismatched")
        check(published==newBytes,"New-epoch verdict was attached to old-epoch pixels")
        check(encodes==3,"Expected cache miss/re-encode behavior differs")
        // Existing same-epoch prepared reuse still works.
        let next=broker.frame(capturedAt:4,timestamp:nil,now:4,wall:1004)
        broker.prepare(newImage,frame:next);broker.flushForTesting();let beforeOffer=encodes
        broker.offer(newImage,frame:next,cameraID:"test",context:"new",reference:nil,current:nil,hand:false,aligned:true);broker.flushForTesting()
        check(encodes==beforeOffer,"Same-epoch preparation was not reused")
        let final=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:path))
        check(final.frame==next && final.handObstructed==false && final.alignmentValid,"Same-frame safety pairing regressed")
        // Startup orphan cleanup happens once, then queue-owned retention
        // keeps four protocol images across subsequent frames and stream resets.
        let retainedRoot=root.appendingPathComponent("retention")
        try FileManager.default.createDirectory(at:retainedRoot,withIntermediateDirectories:true)
        for id in 1...9 {try oldBytes.write(to:retainedRoot.appendingPathComponent("\(UUID())-\(id).png"))}
        let unrelated=retainedRoot.appendingPathComponent("holiday.png")
        try oldBytes.write(to:unrelated)
        let retention=PhysicalLaserFrameBroker(directory:retainedRoot,encodeImage:{_ in newBytes})
        for i in 1...12 {
            if i==7 {retention.resetStream()}
            let f=retention.frame(capturedAt:Double(i),timestamp:nil,now:Double(i),wall:1000+Double(i))
            retention.offer(newImage,frame:f,cameraID:"test",context:"retention",reference:nil,current:nil,hand:false,aligned:true)
            retention.flushForTesting()
            let files=try FileManager.default.contentsOfDirectory(at:retainedRoot,includingPropertiesForKeys:nil)
            check(files.filter{$0.pathExtension=="png" && $0.lastPathComponent != unrelated.lastPathComponent}.count==4,"protocol image retention grew or ignored startup orphans")
            check(FileManager.default.fileExists(atPath:unrelated.path),"cleanup deleted unrelated image")
            let latest=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:retainedRoot.appendingPathComponent("latest.json")))
            check(latest.frame==f && FileManager.default.fileExists(atPath:retainedRoot.appendingPathComponent(latest.imageFile).path),"manifest references pruned or wrong-epoch pixels")
        }
        // A failed manifest write must leave the old manifest AND its pixels
        // usable. The new image is an orphan and must be removed even though
        // directory-wide cleanup is no longer repeated on every frame.
        let failureRoot=root.appendingPathComponent("failure")
        var failManifest=false
        let failing=PhysicalLaserFrameBroker(directory:failureRoot,encodeImage:{_ in newBytes},writeFile:{data,url in
            if failManifest && url.lastPathComponent=="latest.json" {throw CocoaError(.fileWriteOutOfSpace)}
            try EphemeralAtomicFile.write(data,to:url)
        })
        let firstFrame=failing.frame(capturedAt:1,timestamp:nil,now:1,wall:1001)
        failing.offer(newImage,frame:firstFrame,cameraID:"test",context:"failure",reference:nil,current:nil,hand:false,aligned:true)
        failing.flushForTesting()
        let originalManifest=try Data(contentsOf:failureRoot.appendingPathComponent("latest.json"))
        failManifest=true
        let rejected=failing.frame(capturedAt:2,timestamp:nil,now:2,wall:1002)
        failing.offer(newImage,frame:rejected,cameraID:"test",context:"failure",reference:nil,current:nil,hand:true,aligned:false)
        failing.flushForTesting()
        let remainingManifest=try Data(contentsOf:failureRoot.appendingPathComponent("latest.json"))
        check(remainingManifest==originalManifest,"failed publication changed previous manifest")
        let files=try FileManager.default.contentsOfDirectory(at:failureRoot,includingPropertiesForKeys:nil)
        check(files.filter{$0.pathExtension=="png"}.count==1,"failed manifest left unbounded orphan PNG")
        // A stream reset during an already-written PNG cannot publish its old
        // metadata or leave that cancelled PNG behind.
        let ioRoot=root.appendingPathComponent("io-reset")
        let ioBlocked=DispatchSemaphore(value:0),ioRelease=DispatchSemaphore(value:0)
        var firstPixelWrite=true
        let ioBroker=PhysicalLaserFrameBroker(directory:ioRoot,encodeImage:{_ in newBytes},writeFile:{data,url in
            try EphemeralAtomicFile.write(data,to:url)
            if url.pathExtension=="png",firstPixelWrite {
                firstPixelWrite=false;ioBlocked.signal()
                precondition(ioRelease.wait(timeout:.now()+5) == .success)
            }
        })
        let obsolete=ioBroker.frame(capturedAt:1,timestamp:nil,now:1,wall:1001)
        ioBroker.offer(oldImage,frame:obsolete,cameraID:"test",context:"io-reset",reference:nil,current:nil,hand:false,aligned:true)
        check(ioBlocked.wait(timeout:.now()+5) == .success,"pixel IO barrier not reached")
        ioBroker.resetStream()
        let replacement=ioBroker.frame(capturedAt:2,timestamp:nil,now:2,wall:1002)
        ioBroker.offer(newImage,frame:replacement,cameraID:"test",context:"io-reset",reference:nil,current:nil,hand:true,aligned:false)
        ioRelease.signal();ioBroker.flushForTesting()
        let current=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:ioRoot.appendingPathComponent("latest.json")))
        check(current.frame==replacement && current.handObstructed==true,"reset during pixel IO published obsolete verdict")
        check(!FileManager.default.fileExists(atPath:ioRoot.appendingPathComponent("\(obsolete.streamEpoch)-\(obsolete.frameID).png").path),"cancelled PNG leaked")
        print("PASS",checks,"broker epoch/cache checks with actual app types")
    }
}
