import Foundation
import CoreGraphics

@main struct PhysicalCameraSafetyTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PhysicalGoSafety-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let bytes=Data(repeating:255,count:4)
        let image=CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:2,
            space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),
            provider:CGDataProvider(data:bytes as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        var checks=0
        func check(_ condition:Bool,_ label:String) {checks+=1;precondition(condition,label)}
        func frame(_ broker:PhysicalLaserFrameBroker)->PhysicalLaserFrameBroker.Frame {
            let now=ProcessInfo.processInfo.systemUptime
            let timestamp=CameraFrameTimestamp(capturedAt:now,arrivedAt:now,source:"cameraPresentation",presentationSeconds:now)
            return broker.frame(capturedAt:now,timestamp:timestamp,now:now,wall:Date().timeIntervalSince1970)
        }
        func offer(_ broker:PhysicalLaserFrameBroker,_ f:PhysicalLaserFrameBroker.Frame,hand:Bool?=false,aligned:Bool=true) {
            broker.offer(image,frame:f,cameraID:"test",context:"test-context",reference:nil,current:nil,hand:hand,aligned:aligned)
        }
        func safety(_ folder:URL)throws->PhysicalLaserFrameBroker.SafetyManifest {
            try JSONDecoder().decode(PhysicalLaserFrameBroker.SafetyManifest.self,from:Data(contentsOf:folder.appendingPathComponent("safety.json")))
        }
        // Neither compression nor pixel writes may hold up new clearance or
        // obstruction evidence. The optical manifest still waits for its pixels.
        for stage in ["encode","pixels"] {
            let folder=root.appendingPathComponent(stage)
            let blocked=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
            var blockedOnce=false
            func block() {
                if !blockedOnce {blockedOnce=true;blocked.signal();precondition(release.wait(timeout:.now()+10) == .success)}
            }
            let broker=PhysicalLaserFrameBroker(directory:folder,encodeImage:{_ in
                if stage=="encode" {block()};return Data("pixels".utf8)
            },writeFile:{data,url in
                if stage=="pixels" && url.pathExtension=="png" {block()}
                try EphemeralAtomicFile.write(data,to:url)
            })
            let first=frame(broker);offer(broker,first)
            check(blocked.wait(timeout:.now()+5) == .success,"missing image stall")
            broker.flushSafetyForTesting()
            check(try safety(folder).frame==first,"safety waits for image")
            check(!FileManager.default.fileExists(atPath:folder.appendingPathComponent("latest.json").path),"image published without pixels")
            Thread.sleep(forTimeInterval:0.7) // Image stall outlasts gameplay's 600 ms budget.
            let hand=frame(broker);offer(broker,hand,hand:true);broker.flushSafetyForTesting()
            let current=try safety(folder)
            check(current.frame==hand && current.handObstructed==true,"fresh hand blocked by image IO")
            check(current.frame.capturedAtUptime==hand.capturedAtUptime,"capture time renewed")
            release.signal();broker.flushForTesting()
            let optical=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:folder.appendingPathComponent("latest.json")))
            check(optical.frame==hand && optical.handObstructed==true,"optical verdict borrowed from another frame")
        }
        // A blocked safety write permits only one newest pending message. A
        // reset fences queued observations; it does not wait on the filesystem.
        let coalesced=root.appendingPathComponent("coalesced")
        let blocked=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        var safetyWrites=0
        let broker=PhysicalLaserFrameBroker(directory:coalesced,encodeImage:{_ in Data("pixels".utf8)},writeFile:{data,url in
            if url.lastPathComponent=="safety.json" {
                safetyWrites+=1
                if safetyWrites==1 {blocked.signal();precondition(release.wait(timeout:.now()+10) == .success)}
            }
            try EphemeralAtomicFile.write(data,to:url)
        })
        let old=frame(broker);offer(broker,old)
        check(blocked.wait(timeout:.now()+5) == .success,"safety stall not reached")
        for _ in 0..<100 {offer(broker,frame(broker))}
        broker.resetStream()
        let newest=frame(broker);offer(broker,newest,hand:nil,aligned:false)
        offer(broker,old) // A late callback from the old epoch cannot replace it.
        release.signal();broker.flushForTesting()
        let final=try safety(coalesced)
        check(safetyWrites==2,"unbounded safety write backlog")
        check(final.frame==newest && final.handObstructed==nil && !final.alignmentValid,"reset or unknown verdict lost")
        let original=try Data(contentsOf:coalesced.appendingPathComponent("safety.json"))
        offer(broker,newest,hand:false,aligned:true);broker.flushForTesting()
        check(try Data(contentsOf:coalesced.appendingPathComponent("safety.json"))==original,"duplicate mutated immutable observation")
        // Failed new safety writes leave original timestamps; fresh optical
        // publication is deliberately NOT fallback authority for the host.
        let failure=root.appendingPathComponent("failure")
        var fail=false
        let failing=PhysicalLaserFrameBroker(directory:failure,writeFile:{data,url in
            if fail && url.lastPathComponent=="safety.json" {throw CocoaError(.fileWriteOutOfSpace)}
            try EphemeralAtomicFile.write(data,to:url)
        })
        offer(failing,frame(failing));failing.flushForTesting()
        let before=try Data(contentsOf:failure.appendingPathComponent("safety.json"))
        fail=true;let rejected=frame(failing);offer(failing,rejected,hand:true);failing.flushForTesting()
        check(try Data(contentsOf:failure.appendingPathComponent("safety.json"))==before,"failed write renewed safety")
        let latest=try JSONDecoder().decode(PhysicalLaserFrameBroker.Manifest.self,from:Data(contentsOf:failure.appendingPathComponent("latest.json")))
        check(latest.frame==rejected,"safety writer blocked independent pixels")
        // Export literal production Swift messages for Python contract checks.
        if let path=ProcessInfo.processInfo.environment["PHYSICAL_GO_SAFETY_FIXTURES"] {
            let exports=URL(fileURLWithPath:path,isDirectory:true)
            for (name,hand,aligned) in [("clear",false as Bool?,true),("hand",true as Bool?,true),
                                       ("unknown",nil as Bool?,true),("misaligned",false as Bool?,false)] {
                let folder=exports.appendingPathComponent(name)
                let exporting=PhysicalLaserFrameBroker(directory:folder)
                let f=frame(exporting);offer(exporting,f,hand:hand,aligned:aligned);exporting.flushForTesting()
                let m=try safety(folder)
                check(m.frame==f && m.schemaVersion==2 && m.kind=="cameraSafety","bad production wire export")
                let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("safety.json"))) as! [String:Any]
                check(raw["imageFile"]==nil && raw["encoding"]==nil,"safety message pretends to contain pixels")
            }
        }
        print("PASS",checks,"independent camera safety delivery checks")
    }
}
