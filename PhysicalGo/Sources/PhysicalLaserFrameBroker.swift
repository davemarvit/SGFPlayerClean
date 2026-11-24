import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Latest-only, immutable, unrotated frames for the optical controller. Camera
/// callbacks only hand off references; compression and disk IO run on this queue.
final class PhysicalLaserFrameBroker: @unchecked Sendable {
    struct Frame: Codable, Equatable {
        let streamEpoch: UUID
        let frameID: UInt64
        let capturedAtUptime: Double
        let arrivedAtUptime: Double
        let capturedAtUnix: Double
        let timestampSource: String
        let presentationSeconds: Double?
    }
    struct Manifest: Codable {
        let schemaVersion: Int
        let frame: Frame
        let publishedAtUnix: Double
        let imageFile: String
        let encoding: String
        let width: Int
        let height: Int
        let cameraID: String
        let cameraContext: String
        let referenceCalibration: BoardCalibration?
        let currentCalibration: BoardCalibration?
        let handObstructed: Bool?
        let alignmentValid: Bool
    }
    /// Clearance supervision only. No image locator: consumers must continue
    /// to read the independently timestamped PNG manifest for optical evidence.
    struct SafetyManifest: Codable {
        let schemaVersion: Int
        let kind: String
        let frame: Frame
        var publishedAtUnix: Double
        let width: Int
        let height: Int
        let cameraID: String
        let cameraContext: String
        let referenceCalibration: BoardCalibration?
        let currentCalibration: BoardCalibration?
        let handObstructed: Bool?
        let alignmentValid: Bool
    }
    private struct FrameIdentity: Hashable {
        let streamEpoch: UUID
        let frameID: UInt64
        init(_ frame: Frame) {streamEpoch=frame.streamEpoch;frameID=frame.frameID}
    }
    private struct Item {
        let image: CGImage
        let manifest: Manifest
    }
    let directory: URL
    private let lock=NSLock()
    private let queue=DispatchQueue(label:"PhysicalGo.laserFrames",qos:.userInitiated)
    private let safetyQueue=DispatchQueue(label:"PhysicalGo.laserSafety",qos:.userInitiated)
    private var epoch=UUID()
    private var nextID: UInt64=0
    private var pending: Item?
    private var pendingPreparation: (CGImage,Frame)?
    private var working=false
    private var safetyPending: SafetyManifest?
    private var safetyWorking=false
    private var lastOffered: Frame? // lock-owned; immutable, advancing observations
    private let encodeImage: ((CGImage)->Data?)?
    private let writeFile:(Data,URL)throws->Void
    private var directoryPrepared=false // queue-owned; orphan scan is once per broker
    private var publishedFrame: Frame?
    private var preparedPixels:[FrameIdentity:Data]=[:] // queue-owned, at most two analyzed frames
    private var retained=[URL]() // queue-owned; at most four published PNGs
    init(directory: URL,encodeImage:((CGImage)->Data?)?=nil,
         writeFile:@escaping (Data,URL)throws->Void = {try EphemeralAtomicFile.write($0,to:$1)}) {
        self.directory=directory;self.encodeImage=encodeImage;self.writeFile=writeFile
    }
    var streamEpoch: UUID {lock.lock();defer {lock.unlock()};return epoch}
    func resetStream() {
        lock.lock();epoch=UUID();nextID=0;pending=nil;pendingPreparation=nil
        safetyPending=nil;lastOffered=nil;lock.unlock()
        // Leave any old safety file to fail its epoch/age checks. Removing it
        // could make a reader mistake a failed new producer for a legacy one.
        queue.async { [self] in
            preparedPixels.removeAll()
            guard let owned=publishedFrame else {return}
            // Readers must also compare the request's streamEpoch. An old
            // manifest may exist briefly while its queued IO finishes.
            let url=directory.appendingPathComponent("latest.json")
            if let data=try? Data(contentsOf:url),let old=try? JSONDecoder().decode(Manifest.self,from:data),
               old.frame.streamEpoch==owned.streamEpoch,old.frame.streamEpoch != streamEpoch {
                try? FileManager.default.removeItem(at:url)
            }
        }
    }
    func frame(capturedAt: Double, timestamp: CameraFrameTimestamp?, now: Double, wall: Double)->Frame {
        lock.lock();defer {lock.unlock()};nextID+=1
        return .init(streamEpoch:epoch,frameID:nextID,capturedAtUptime:capturedAt,
                     arrivedAtUptime:timestamp?.arrivedAt ?? now,capturedAtUnix:wall-(now-capturedAt),
                     timestampSource:timestamp?.source ?? "callback",presentationSeconds:timestamp?.presentationSeconds)
    }
    /// Encode alongside recognition, but publish nothing until that exact frame's
    /// hand/alignment checks arrive through offer(). Never borrow another frame's verdict.
    func prepare(_ image:CGImage,frame:Frame) {
        lock.lock()
        guard frame.streamEpoch==epoch else {lock.unlock();return}
        pendingPreparation=(image,frame)
        let start = !working;working=true;lock.unlock()
        if start {queue.async {[self] in drain()}}
    }
    private func encode(_ image:CGImage)->Data? {
        if let encodeImage {return encodeImage(image)}
        let pixels=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(pixels,UTType.png.identifier as CFString,1,nil) else {return nil}
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else {return nil}
        return pixels as Data
    }
    func offer(_ image: CGImage, frame: Frame, cameraID: String, context: String,
               reference: BoardCalibration?, current: BoardCalibration?, hand: Bool?, aligned: Bool) {
        let manifest=Manifest(schemaVersion:1,frame:frame,publishedAtUnix:0,
                              imageFile:"\(frame.streamEpoch)-\(frame.frameID).png",encoding:"PNG",
                              width:image.width,height:image.height,cameraID:cameraID,cameraContext:context,
                              referenceCalibration:reference,currentCalibration:current,handObstructed:hand,alignmentValid:aligned)
        lock.lock()
        guard frame.streamEpoch==epoch else {lock.unlock();return}
        if let old=lastOffered,old.streamEpoch==frame.streamEpoch,old.frameID>=frame.frameID {
            lock.unlock();return
        }
        lastOffered=frame
        pending=Item(image:image,manifest:manifest)
        safetyPending=SafetyManifest(schemaVersion:2,kind:"cameraSafety",frame:frame,publishedAtUnix:0,
            width:image.width,height:image.height,cameraID:cameraID,cameraContext:context,
            referenceCalibration:reference,currentCalibration:current,handObstructed:hand,alignmentValid:aligned)
        let start = !working,safetyStart = !safetyWorking
        working=true;safetyWorking=true;lock.unlock()
        if safetyStart {safetyQueue.async {[self] in drainSafety()}}
        if start {queue.async {[self] in drain()}}
    }
    private func drainSafety() {
        while true {
            lock.lock()
            guard var item=safetyPending else {safetyWorking=false;lock.unlock();return}
            safetyPending=nil;lock.unlock()
            guard item.frame.streamEpoch==streamEpoch else {continue}
            let began=ProcessInfo.processInfo.systemUptime
            do {
                // Independent from PNG compression, image retention and pixel IO.
                // No filesystem work runs under the shared admission lock.
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                item.publishedAtUnix=Date().timeIntervalSince1970
                let bytes=try JSONEncoder().encode(item)
                guard item.frame.streamEpoch==streamEpoch else {continue}
                try writeFile(bytes,directory.appendingPathComponent("safety.json"))
                PhysicalLatencyTrace.shared?.record("laser_safety_published",fields:[
                    "frameID":String(item.frame.frameID),"streamEpoch":item.frame.streamEpoch.uuidString],metrics:[
                        "totalSeconds":ProcessInfo.processInfo.systemUptime-began,
                        "captureAgeSeconds":Date().timeIntervalSince1970-item.frame.capturedAtUnix])
            } catch {
                // Atomic failure retains the prior message with its ORIGINAL
                // capture/publication times; host expiry must still stop use.
                PhysicalLatencyTrace.shared?.record("laser_safety_publication_failed",fields:[
                    "frameID":String(item.frame.frameID)],metrics:[
                        "totalSeconds":ProcessInfo.processInfo.systemUptime-began])
            }
        }
    }
    private func drain() {
        while true {
            lock.lock()
            if let item=pending {
                pending=nil;lock.unlock()
                autoreleasepool {publish(item)}
            } else if let (image,frame)=pendingPreparation {
                pendingPreparation=nil;lock.unlock()
                autoreleasepool {
                    // An approved frame may already have been encoded by publish().
                    // Never queue redundant compression behind newer safety verdicts.
                    if let old=publishedFrame,old.streamEpoch==frame.streamEpoch,old.frameID>=frame.frameID {return}
                    let began=ProcessInfo.processInfo.systemUptime
                    guard frame.streamEpoch==streamEpoch,let pixels=encode(image),frame.streamEpoch==streamEpoch else {return}
                    PhysicalLatencyTrace.shared?.record("laser_frame_encoding",fields:["frameID":String(frame.frameID),"stage":"prepare"],
                        metrics:["encodeSeconds":ProcessInfo.processInfo.systemUptime-began])
                    preparedPixels[FrameIdentity(frame)]=pixels
                    for key in preparedPixels.keys.sorted(by:{$0.frameID<$1.frameID}).dropLast(2) {preparedPixels.removeValue(forKey:key)}
                }
            } else {working=false;lock.unlock();return}
        }
    }
    private func prepareDirectory()throws {
        guard !directoryPrepared else {return}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // An earlier process may have left protocol images. Discover them once,
        // then maintain the four-file bound from our queue-owned retained list.
        // Unrelated files are never candidates for deletion.
        let existing=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])
        retained=existing.filter {url in
            let parts=url.deletingPathExtension().lastPathComponent.split(separator:"-")
            return url.pathExtension=="png" && parts.count==6 && UInt64(parts.last!) != nil && UUID(uuidString:parts.dropLast().joined(separator:"-")) != nil
        }.sorted {((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
        directoryPrepared=true
    }
    private func makeRoomForPublication()throws {
        // Remove before writing another image. If cleanup fails, stop publishing
        // instead of growing the directory/list without bound. Readers can retry
        // a pruned image using latest.json, as in the existing broker protocol.
        while retained.count>=4 {
            do {try FileManager.default.removeItem(at:retained[0])}
            catch let error as CocoaError where error.code == .fileNoSuchFile {}
            retained.removeFirst()
        }
    }
    private func publish(_ item: Item) {
        let m=item.manifest
        guard m.frame.streamEpoch==streamEpoch else {return}
        if let old=publishedFrame,old.streamEpoch==m.frame.streamEpoch,old.frameID>=m.frame.frameID {return}
        let began=ProcessInfo.processInfo.systemUptime
        let prepared=preparedPixels.removeValue(forKey:FrameIdentity(m.frame))
        guard let pixels=prepared ?? encode(item.image),m.frame.streamEpoch==streamEpoch else {return}
        let encoded=ProcessInfo.processInfo.systemUptime
        var stage="prepare_directory",unpublished:URL?
        defer {if let unpublished {try? FileManager.default.removeItem(at:unpublished)}}
        do {
            try prepareDirectory()
            stage="prune";let pruneBegan=ProcessInfo.processInfo.systemUptime
            try makeRoomForPublication()
            let pruned=ProcessInfo.processInfo.systemUptime
            let file=directory.appendingPathComponent(m.imageFile)
            unpublished=file;stage="pixels"
            try writeFile(pixels,file)
            let pixelsWritten=ProcessInfo.processInfo.systemUptime
            guard m.frame.streamEpoch==streamEpoch else {return}
            let published=Manifest(schemaVersion:1,frame:m.frame,publishedAtUnix:Date().timeIntervalSince1970,
                                   imageFile:m.imageFile,encoding:m.encoding,width:m.width,height:m.height,
                                   cameraID:m.cameraID,cameraContext:m.cameraContext,referenceCalibration:m.referenceCalibration,
                                   currentCalibration:m.currentCalibration,handObstructed:m.handObstructed,alignmentValid:m.alignmentValid)
            stage="manifest"
            try writeFile(JSONEncoder().encode(published),directory.appendingPathComponent("latest.json"))
            let finished=ProcessInfo.processInfo.systemUptime
            publishedFrame=m.frame;retained.append(file);unpublished=nil
            PhysicalLatencyTrace.shared?.record("laser_frame_published",fields:[
                "frameID":String(m.frame.frameID),"streamEpoch":m.frame.streamEpoch.uuidString,
                "preparedPixels":String(prepared != nil)],metrics:[
                    "encodeSeconds":encoded-began,"directorySeconds":pruneBegan-encoded,
                    "pruneSeconds":pruned-pruneBegan,"pixelWriteSeconds":pixelsWritten-pruned,
                    "manifestWriteSeconds":finished-pixelsWritten,"totalSeconds":finished-began,
                    "captureAgeSeconds":Date().timeIntervalSince1970-m.frame.capturedAtUnix])
        } catch {
            PhysicalLatencyTrace.shared?.record("laser_frame_publication_failed",fields:[
                "frameID":String(m.frame.frameID),"stage":stage],metrics:[
                    "totalSeconds":ProcessInfo.processInfo.systemUptime-began])
            // A failed publication leaves the previous manifest unchanged. The
            // unpublished image is removed, and readers enforce original ages.
        }
    }
    func flushSafetyForTesting() {safetyQueue.sync {}}
    func flushForTesting() {safetyQueue.sync {};queue.sync {}}
}
