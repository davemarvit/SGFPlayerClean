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
    private var epoch=UUID()
    private var nextID: UInt64=0
    private var pending: Item?
    private var pendingPreparation: (CGImage,Frame)?
    private var working=false
    private let encodeImage: ((CGImage)->Data?)?
    private var publishedFrame: Frame?
    private var preparedPixels:[FrameIdentity:Data]=[:] // queue-owned, at most two analyzed frames
    private var retained=[URL]() // queue-owned; at most four published PNGs
    init(directory: URL,encodeImage:((CGImage)->Data?)?=nil) {self.directory=directory;self.encodeImage=encodeImage}
    var streamEpoch: UUID {lock.lock();defer {lock.unlock()};return epoch}
    func resetStream() {
        lock.lock();epoch=UUID();nextID=0;pending=nil;pendingPreparation=nil;lock.unlock()
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
        pending=Item(image:image,manifest:manifest)
        let start = !working;working=true;lock.unlock()
        if start {queue.async {[self] in drain()}}
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
                    guard frame.streamEpoch==streamEpoch,let pixels=encode(image),frame.streamEpoch==streamEpoch else {return}
                    preparedPixels[FrameIdentity(frame)]=pixels
                    for key in preparedPixels.keys.sorted(by:{$0.frameID<$1.frameID}).dropLast(2) {preparedPixels.removeValue(forKey:key)}
                }
            } else {working=false;lock.unlock();return}
        }
    }
    private func publish(_ item: Item) {
        let m=item.manifest
        guard m.frame.streamEpoch==streamEpoch else {return}
        if let old=publishedFrame,old.streamEpoch==m.frame.streamEpoch,old.frameID>=m.frame.frameID {return}
        guard let pixels=preparedPixels.removeValue(forKey:FrameIdentity(m.frame)) ?? encode(item.image),
              m.frame.streamEpoch==streamEpoch else {return}
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let file=directory.appendingPathComponent(m.imageFile)
            try (pixels as Data).write(to:file,options:.atomic)
            guard m.frame.streamEpoch==streamEpoch else {try? FileManager.default.removeItem(at:file);return}
            let published=Manifest(schemaVersion:1,frame:m.frame,publishedAtUnix:Date().timeIntervalSince1970,
                                   imageFile:m.imageFile,encoding:m.encoding,width:m.width,height:m.height,
                                   cameraID:m.cameraID,cameraContext:m.cameraContext,referenceCalibration:m.referenceCalibration,
                                   currentCalibration:m.currentCalibration,handObstructed:m.handObstructed,alignmentValid:m.alignmentValid)
            try JSONEncoder().encode(published).write(to:directory.appendingPathComponent("latest.json"),options:.atomic)
            publishedFrame=m.frame
            retained.append(file)
            while retained.count>4 {try? FileManager.default.removeItem(at:retained.removeFirst())}
            // Also bound files left by an earlier app process. Only remove names
            // belonging to this protocol, never arbitrary files in the folder.
            let existing=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
            let pngs=existing.filter {url in
                let parts=url.deletingPathExtension().lastPathComponent.split(separator:"-")
                return url.pathExtension=="png" && parts.count==6 && UInt64(parts.last!) != nil && UUID(uuidString:parts.dropLast().joined(separator:"-")) != nil
            }.sorted {((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
            for old in pngs.dropFirst(4) {try? FileManager.default.removeItem(at:old)}
        } catch {
            // No usable new manifest is published on failure. Readers enforce
            // freshness, never interpreting an old image as a new camera sample.
        }
    }
    func flushForTesting() {queue.sync {}}
}
