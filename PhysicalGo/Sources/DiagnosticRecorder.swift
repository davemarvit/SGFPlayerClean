import Foundation
import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Developer/test captures stay outside the SGF library and move-evidence buffer.
enum CaptureFolders {
    static var root:URL {
        if let path=Bundle.main.object(forInfoDictionaryKey:"PhysicalGoCaptureDirectory") as? String {
            return URL(fileURLWithPath:path,isDirectory:true)
        }
        return URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Captures",isDirectory:true)
    }
    static var samples:URL {root.appendingPathComponent("Samples",isDirectory:true)}
    static var diagnostics:URL {root.appendingPathComponent("Diagnostics",isDirectory:true)}
}

@MainActor final class DiagnosticRecorder:ObservableObject {
    struct Ticket:Equatable {let session:UUID;let frame:Int}
    struct Operation {let session:UUID;let id:Int;let frame:Int?}
    enum State {case idle,capturing,finishing,stopped,failed}
    @Published private(set) var state:State = .idle
    @Published private(set) var status="Diagnostic capture is off."
    @Published private(set) var folder:URL?
    @Published private(set) var savedFrames=0
    @Published private(set) var savedBytes:Int64=0
    @Published var limitGB=10
    private let archiveStorage:DiagnosticArchiveStorage?
    var isCapturing:Bool {state == .capturing}
    var isOpen:Bool {worker != nil && (state == .capturing || state == .finishing)}
    var canStart:Bool {worker == nil}
    private let root:URL
    private var worker:DiagnosticWriter?
    private var sessionID=UUID()
    private var nextFrame=0,nextOperation=0,nextAsset=0,pendingWrites=0
    private var operations=[Int:Operation]()
    private var finishing=false
    private var endReason="Stopped by user"
    private var lastReference:CGImage?
    private var referencePath:String?
    private var lastAnchorRevision:Int?
    private var anchorPath:String?
    private var anchorInfo:[String:Any]?
    private let maximumPendingFrames:Int
    init(root:URL=CaptureFolders.diagnostics,maximumPendingFrames:Int=12,archiveStorage:DiagnosticArchiveStorage?=nil) {
        self.root=root;self.maximumPendingFrames=maximumPendingFrames
        self.archiveStorage=archiveStorage ?? (root==CaptureFolders.diagnostics ? .shared:nil)
    }
    static func value<T:Encodable>(_ value:T?)->Any {
        guard let value,let data=try? JSONEncoder().encode(value),let json=try? JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed) else {return NSNull()}
        return json
    }
    func start(context:[String:Any],byteLimit:Int64?=nil,reserveBytes:Int64=2_000_000_000) throws {
        guard canStart else {return}
        let id=UUID(),formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd HH-mm-ss"
        let url=root.appendingPathComponent("Diagnostic \(formatter.string(from:Date())) \(id.uuidString.prefix(8))",isDirectory:true)
        let requested=byteLimit ?? min(Int64(limitGB)*1_000_000_000,DiagnosticArchiveStorage.defaultLimit-DiagnosticArchiveStorage.metadataAllowance)
        // Cheap validation stays synchronous; directory scans, rotation and
        // opening the archive run before writes on the writer's serial queue.
        if let archiveStorage,requested<=0 || requested+DiagnosticArchiveStorage.metadataAllowance>archiveStorage.limit {
            throw NSError(domain:"PhysicalGo.Diagnostics",code:2,userInfo:[NSLocalizedDescriptionKey:"Diagnostic storage allowance is too small for this capture."])
        }
        let writer=DiagnosticWriter(folder:url,limit:requested,reserve:reserveBytes,context:context,
            archiveStorage:archiveStorage,minimumPayload:byteLimit==nil ? 64_000_000:nil)
        worker=writer;sessionID=id;folder=url;nextFrame=0;nextOperation=0;nextAsset=0;pendingWrites=0
        operations=[:];finishing=false;endReason="Stopped by user";lastReference=nil;referencePath=nil;lastAnchorRevision=nil;anchorPath=nil;anchorInfo=nil
        savedFrames=0;savedBytes=0;state = .capturing;status="Saving diagnostic frames · game recording is separate."
        writer.onFailure={ [weak self] message in
            guard let self,self.sessionID==id else {return}
            self.state = .failed;self.status="Diagnostic capture stopped: \(message). Saved files are retained; game recording continues."
            self.operations=[:];self.worker=nil;self.lastReference=nil
        }
    }
    func capture(_ image:CGImage,at time:Double,context:[String:Any],reference:CGImage?,anchor:AutoGridDetector.TrackingAnchor?,anchorRevision:Int)->Ticket? {
        guard isCapturing,let worker else {return nil}
        guard pendingWrites<maximumPendingFrames else {
            stop(reason:"Disk writer could not keep up; capture ended before dropping a frame",failure:true,cancelOperations:true)
            return nil
        }
        nextFrame += 1
        let ticket=Ticket(session:sessionID,frame:nextFrame)
        var assets=[DiagnosticWriter.Asset]()
        if let reference {
            if lastReference !== reference {
                nextAsset += 1;referencePath=String(format:"assets/reference-%06d.png",nextAsset)
                lastReference=reference;assets.append(.png(referencePath!,reference))
            }
        } else {lastReference=nil;referencePath=nil}
        if let anchor {
            if lastAnchorRevision != anchorRevision {
                nextAsset += 1;anchorPath=String(format:"assets/anchor-%06d.gray",nextAsset)
                lastAnchorRevision=anchorRevision
                anchorInfo=["pixels":anchorPath!,"width":anchor.frame.width,"height":anchor.frame.height,
                    "calibration":Self.value(anchor.calibration),"fittedGrid":Self.value(anchor.fittedGrid)]
                assets.append(.bytes(anchorPath!,Data(anchor.frame.pixels)))
            }
        } else {lastAnchorRevision=nil;anchorPath=nil;anchorInfo=nil}
        var entry=context
        entry["event"]="frame";entry["frameID"]=ticket.frame;entry["captureUptime"]=time
        entry["time"]=Date().timeIntervalSince1970;entry["image"]=String(format:"frames/%06d.png",ticket.frame)
        entry["width"]=image.width;entry["height"]=image.height
        entry["referenceImage"]=referencePath.map{$0 as Any} ?? NSNull()
        entry["trackingAnchor"]=anchorInfo.map{$0 as Any} ?? NSNull()
        pendingWrites += 1
        worker.frame(image,entry:entry,assets:assets) { [weak self] frames,bytes in
            guard let self,self.sessionID==ticket.session else {return}
            self.pendingWrites=max(0,self.pendingWrites-1);self.savedFrames=frames;self.savedBytes=bytes
        }
        return ticket
    }
    func event(_ name:String,ticket:Ticket?=nil,details:@autoclosure ()->[String:Any]=[:]) {
        guard isOpen,let worker,ticket.map({$0.session==sessionID}) ?? true else {return}
        var entry=details();entry["event"]=name;entry["time"]=Date().timeIntervalSince1970
        entry["uptime"]=ProcessInfo.processInfo.systemUptime
        if let ticket {entry["frameID"]=ticket.frame}
        worker.event(entry)
    }
    func begin(_ kind:String,ticket:Ticket?,details:@autoclosure ()->[String:Any]=[:])->Operation? {
        guard isCapturing,ticket.map({$0.session==sessionID}) ?? true else {return nil}
        nextOperation += 1
        let operation=Operation(session:sessionID,id:nextOperation,frame:ticket?.frame)
        operations[operation.id]=operation
        var entry=details();entry["operationID"]=operation.id;entry["kind"]=kind
        event("operation started",ticket:ticket,details:entry)
        return operation
    }
    func end(_ operation:Operation?,outcome:String,details:@autoclosure ()->[String:Any]=[:]) {
        guard let operation,operation.session==sessionID,operations.removeValue(forKey:operation.id) != nil else {return}
        var entry=details();entry["operationID"]=operation.id;entry["outcome"]=outcome
        event("operation finished",ticket:operation.frame.map{Ticket(session:sessionID,frame:$0)},details:entry)
        finishIfReady()
    }
    func stop(reason:String="Stopped by user",failure:Bool=false,cancelOperations:Bool=false) {
        guard worker != nil,!finishing else {return}
        endReason=reason
        event("capture stopping",details:["reason":reason,"pendingOperations":operations.count])
        state = .finishing;status=failure ? "Diagnostic capture stopped: \(reason). Finishing saved files…" : "Finishing diagnostic files…"
        if cancelOperations {
            for op in operations.values {event("operation canceled",details:["operationID":op.id,"reason":reason])}
            operations=[:]
        }
        finishIfReady(failure:failure)
    }
    private func finishIfReady(failure:Bool=false) {
        guard state == .finishing,operations.isEmpty,!finishing,let writer=worker else {return}
        finishing=true;let id=sessionID,reason=endReason
        writer.finish(reason:reason,status:failure ? "failed" : "complete") { [weak self] in
            guard let self,self.sessionID==id,self.worker != nil else {return}
            self.worker=nil;self.lastReference=nil;self.finishing=false
            self.state=failure ? .failed : .stopped
            self.status=failure ? "Diagnostic capture stopped: \(reason). Saved files are retained." : "Diagnostic capture saved."
        }
    }
    /// Called on application termination. Cancel unfinished analysis explicitly,
    /// then drain the bounded image queue before the process can exit.
    func closeForExit() {
        guard let writer=worker else {return}
        for op in operations.values {event("operation canceled",details:["operationID":op.id,"reason":"Application closing"])}
        operations=[:];state = .finishing
        writer.finishSynchronously(reason:"Application closing")
        worker=nil;lastReference=nil;state = .stopped;status="Diagnostic capture saved."
    }
}

/// All disk/PNG work is serialized off the detection and main queues. Errors end
/// the diagnostic stream visibly; they never change the camera or recorder state.
private final class DiagnosticWriter {
    enum Asset {case png(String,CGImage),bytes(String,Data)}
    let folder:URL
    private let queue=DispatchQueue(label:"PhysicalGo.diagnostic-writer",qos:.utility)
    private var limit:Int64
    private let reserve:Int64
    private var lease:DiagnosticArchiveLock?
    private var handle:FileHandle?
    private var bytes:Int64=0,frames=0,closed=false
    private var context:[String:Any]
    private var lastSync=0.0
    var onFailure:((String)->Void)?
    init(folder:URL,limit:Int64,reserve:Int64,context:[String:Any],archiveStorage:DiagnosticArchiveStorage?,minimumPayload:Int64?) {
        self.folder=folder;self.limit=limit;self.reserve=reserve;self.context=context
        queue.async {
            do {
                if let archiveStorage {
                    try archiveStorage.allocate(payload:limit,minimumPayload:minimumPayload) { granted,removed in
                        self.limit=granted
                        self.context["archiveByteLimit"]=archiveStorage.limit;self.context["rotatedArchives"]=removed
                        self.context["retentionPolicy"]="Oldest unpinned, inactive camera archives rotate automatically. KEEP files preserve selected archives."
                        return Result {try self.open()}
                    }.get()
                } else {try self.open()}
            } catch {self.abort(error)}
        }
    }
    private func open() throws {
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("frames"),withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("assets"),withIntermediateDirectories:true)
        lease=try DiagnosticArchiveLock(folder.appendingPathComponent(".writer.lock"))
        let url=folder.appendingPathComponent("events.jsonl");try Data().write(to:url,options:.atomic)
        handle=try FileHandle(forWritingTo:url)
        self.context["schemaVersion"]=1;self.context["startedAt"]=Date().timeIntervalSince1970
        self.context["byteLimit"]=limit;self.context["reserveBytes"]=reserve
        if self.context["capturePolicy"] == nil {
            self.context["capturePolicy"]="Lossless PNG for every frame delivered to the app (~5 fps); includes skipped, frozen and rejected frames. Native camera frames between app deliveries are not captured."
        }
        try manifest(status:"recording",reason:nil)
    }
    private func manifest(status:String,reason:String?) throws {
        var entry=context;entry["status"]=status;entry["framesSaved"]=frames;entry["bytesWritten"]=bytes
        entry["updatedAt"]=Date().timeIntervalSince1970
        if let reason {entry["reason"]=reason}
        try JSONSerialization.data(withJSONObject:entry,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("session.json"),options:.atomic)
    }
    private func png(_ image:CGImage)throws->Data {
        let data=NSMutableData()
        guard let dest=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else {throw failure("PNG encoder unavailable")}
        CGImageDestinationAddImage(dest,image,nil)
        guard CGImageDestinationFinalize(dest) else {throw failure("Could not encode PNG")}
        return data as Data
    }
    private func failure(_ text:String)->NSError {NSError(domain:"PhysicalGo.Diagnostics",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
    private func checkSpace(_ amount:Int) throws {
        guard bytes+Int64(amount)<=limit else {throw failure("storage limit reached")}
        let attributes=try FileManager.default.attributesOfFileSystem(forPath:folder.path)
        if let free=attributes[.systemFreeSize] as? NSNumber,free.int64Value-Int64(amount)<reserve {throw failure("low free disk space")}
    }
    private func append(_ entry:[String:Any],enforceLimit:Bool=true)throws {
        var data=try JSONSerialization.data(withJSONObject:entry,options:.sortedKeys);data.append(10)
        if enforceLimit {try checkSpace(data.count)}
        try handle?.write(contentsOf:data);bytes += Int64(data.count)
        let now=ProcessInfo.processInfo.systemUptime
        if now-lastSync>=1 {try handle?.synchronize();lastSync=now}
    }
    private func save(_ data:Data,path:String)throws {
        try checkSpace(data.count);try data.write(to:folder.appendingPathComponent(path),options:.atomic);bytes += Int64(data.count)
    }
    private func abort(_ error:Error) {
        guard !closed else {return}
        let message=error.localizedDescription
        try? append(["event":"capture failed","reason":message,"time":Date().timeIntervalSince1970],enforceLimit:false)
        try? manifest(status:"failed",reason:message)
        closed=true;try? handle?.close();handle=nil;lease=nil
        DispatchQueue.main.async {self.onFailure?(message)}
    }
    func event(_ entry:[String:Any]) {
        queue.async {
            guard !self.closed else {return}
            do {try self.append(entry)}catch {self.abort(error)}
        }
    }
    func frame(_ image:CGImage,entry:[String:Any],assets:[Asset],completion:@escaping(Int,Int64)->Void) {
        queue.async {
            autoreleasepool {
                guard !self.closed else {return}
                do {
                    for asset in assets {
                        switch asset {
                        case .png(let path,let image):try self.save(self.png(image),path:path)
                        case .bytes(let path,let data):try self.save(data,path:path)
                        }
                    }
                    try self.save(self.png(image),path:entry["image"] as! String)
                    try self.append(entry);self.frames += 1
                    if self.frames%25==0 {try self.manifest(status:"recording",reason:nil)}
                    let frames=self.frames,bytes=self.bytes
                    DispatchQueue.main.async {completion(frames,bytes)}
                }catch {self.abort(error)}
            }
        }
    }
    private func complete(_ reason:String,status:String="complete") {
        guard !closed else {return}
        do {
            try append(["event":"capture ended","reason":reason,"time":Date().timeIntervalSince1970],enforceLimit:false)
            try manifest(status:status,reason:reason);try handle?.synchronize();try handle?.close();handle=nil;closed=true;lease=nil
        }catch {abort(error)}
    }
    func finish(reason:String,status:String="complete",completion:@escaping()->Void) {
        queue.async {self.complete(reason,status:status);DispatchQueue.main.async {completion()}}
    }
    func finishSynchronously(reason:String) {queue.sync {complete(reason)}}
}

@MainActor extension DiagnosticArchiveStorage {
    static let shared=DiagnosticArchiveStorage(roots:[
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Physical Go/Move Evidence"),
        CaptureFolders.diagnostics])
}
