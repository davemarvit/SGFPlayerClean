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
        print("PASS",checks,"broker epoch/cache checks with actual app types")
    }
}
