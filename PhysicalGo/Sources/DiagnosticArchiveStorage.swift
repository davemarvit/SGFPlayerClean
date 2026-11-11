import Foundation
import Darwin

/// Advisory locks also protect writers in another app process. A crashed writer
/// releases its lease automatically, so its incomplete archive can rotate later.
final class DiagnosticArchiveLock {
    private let descriptor:Int32
    init(_ file:URL)throws {
        let opened=Darwin.open(file.path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard opened>=0 else {throw CocoaError(.fileWriteUnknown)}
        guard flock(opened,LOCK_EX|LOCK_NB)==0 else {
            Darwin.close(opened)
            throw NSError(domain:"PhysicalGo.Diagnostics",code:1,userInfo:[NSLocalizedDescriptionKey:"Diagnostic storage is busy. The current capture is protected."])
        }
        descriptor=opened
    }
    deinit {flock(descriptor,LOCK_UN);Darwin.close(descriptor)}
}

/// One budget for automatic evidence and continuous diagnostic camera captures.
/// Only recognized archive directories are eligible; recordings and photo labels
/// live elsewhere. KEEP files pin important captures without changing their data.
@MainActor final class DiagnosticArchiveStorage {
    nonisolated static let defaultLimit:Int64=10_000_000_000
    nonisolated static let metadataAllowance:Int64=1_000_000
    let roots:[URL]
    let limit:Int64
    private(set) var rotatedCount=0
    init(roots:[URL],limit:Int64=defaultLimit) {self.roots=roots;self.limit=limit}
    struct ClearResult:Sendable {
        var removed=0,kept=0,active=0,unrecognized=0
        var failures=[String]()
        var message:String {
            var text="Deleted \(removed) diagnostic camera archive(s)."
            if kept>0 {text+=" Preserved \(kept) kept capture(s)."}
            if active>0 {text+=" Preserved \(active) active capture(s)."}
            if unrecognized>0 {text+=" Left \(unrecognized) unrecognized item(s) untouched."}
            if !failures.isEmpty {text+=" Could not delete \(failures.count) item(s): "+failures.joined(separator:"; ")}
            return text
        }
    }
    /// Explicit user cleanup uses the same interprocess locks as rotation. Run
    /// off the UI thread; never follow directory links or remove a live writer.
    nonisolated static func clearInactive(roots:[URL])throws->ClearResult {
        guard let first=roots.first else {return ClearResult()}
        let fm=FileManager.default
        if (try? first.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true {
            throw NSError(domain:"PhysicalGo.Diagnostics",code:4,userInfo:[NSLocalizedDescriptionKey:"Diagnostic archive folder is a symbolic link; no data was deleted."])
        }
        try fm.createDirectory(at:first,withIntermediateDirectories:true)
        let lock=try DiagnosticArchiveLock(first.appendingPathComponent(".rotation.lock"))
        defer {withExtendedLifetime(lock) {}}
        var result=ClearResult()
        for root in Set(roots) where fm.fileExists(atPath:root.path) {
            guard try root.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else {
                result.unrecognized+=1;continue
            }
            for item in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) {
                if item.lastPathComponent==".rotation.lock" {continue}
                do {
                    let info=try item.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                    let manifestURL=item.appendingPathComponent("session.json")
                    guard info.isDirectory==true,info.isSymbolicLink != true,item.lastPathComponent.hasPrefix("Diagnostic "),
                          (try? manifestURL.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true,
                          let data=try? Data(contentsOf:manifestURL),
                          let manifest=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                          manifest["schemaVersion"] as? Int==1,let date=manifest["startedAt"] as? Double,date.isFinite else {
                        result.unrecognized+=1;continue
                    }
                    if fm.fileExists(atPath:item.appendingPathComponent("KEEP").path) {result.kept+=1;continue}
                    let leaseFile=item.appendingPathComponent(".writer.lock")
                    let legacyRecording = !fm.fileExists(atPath:leaseFile.path) && manifest["status"] as? String=="recording" && Date().timeIntervalSince1970-(manifest["updatedAt"] as? Double ?? date)<120
                    guard !legacyRecording,let lease=try? DiagnosticArchiveLock(leaseFile) else {result.active+=1;continue}
                    defer {withExtendedLifetime(lease) {}}
                    try fm.removeItem(at:item)
                    result.removed+=1
                } catch {result.failures.append("\(item.lastPathComponent): \(error.localizedDescription)")}
            }
        }
        return result
    }
    private struct Archive {
        let url:URL,bytes:Int64,date:Double
        let lease:DiagnosticArchiveLock?
        let removable:Bool
    }
    private func bytes(at url:URL)throws->Int64 {
        let info=try url.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.fileSizeKey])
        if info.isSymbolicLink==true {return Int64(info.fileSize ?? 0)}
        if info.isDirectory != true {return Int64(info.fileSize ?? 0)}
        return try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).reduce(0){try $0+bytes(at:$1)}
    }
    /// Keep this lock through writer creation: its manifest reserves its maximum
    /// size before a second process can start a competing capture.
    func allocate<T>(payload:Int64,minimumPayload:Int64?=nil,create:(Int64,Int)->T)throws->T {
        var required=payload+Self.metadataAllowance
        guard payload>0,required<=limit else {
            throw NSError(domain:"PhysicalGo.Diagnostics",code:2,userInfo:[NSLocalizedDescriptionKey:"Diagnostic storage allowance is too small for this capture."])
        }
        let fm=FileManager.default
        try fm.createDirectory(at:roots[0],withIntermediateDirectories:true)
        let lock=try DiagnosticArchiveLock(roots[0].appendingPathComponent(".rotation.lock"))
        defer {withExtendedLifetime(lock) {}}
        var archives=[Archive](),used:Int64=0
        for root in roots where fm.fileExists(atPath:root.path) {
            for item in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey]) {
                let info=try item.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                let actual=try bytes(at:item)
                guard info.isDirectory==true,info.isSymbolicLink != true,item.lastPathComponent.hasPrefix("Diagnostic "),
                      let data=try? Data(contentsOf:item.appendingPathComponent("session.json")),
                      let manifest=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                      manifest["schemaVersion"] as? Int==1,let date=manifest["startedAt"] as? Double,date.isFinite else {used+=actual;continue}
                let leaseFile=item.appendingPathComponent(".writer.lock")
                let legacyRecording = !fm.fileExists(atPath:leaseFile.path) && manifest["status"] as? String=="recording" && Date().timeIntervalSince1970-(manifest["updatedAt"] as? Double ?? date)<120
                let lease=legacyRecording ? nil:try? DiagnosticArchiveLock(leaseFile)
                let pinned=fm.fileExists(atPath:item.appendingPathComponent("KEEP").path)
                let allocation=min(limit,max(0,manifest["byteLimit"] as? Int64 ?? actual))
                let reserved=lease==nil ? max(actual,allocation+Self.metadataAllowance):actual
                used+=reserved
                archives.append(.init(url:item,bytes:reserved,date:date,lease:lease,removable:lease != nil && !pinned))
            }
        }
        let eligible=archives.filter(\.removable).sorted{$0.date==$1.date ? $0.url.path<$1.url.path:$0.date<$1.date}
        let protectedBytes=used-eligible.reduce(0,{$0+$1.bytes})
        var granted=payload
        // Continuous capture uses the available remainder up to its selected
        // maximum; Finder metadata or another writer must not defeat a 10 GB
        // request. Automatic clips still require their entire reserved budget.
        if let minimumPayload {
            granted=min(payload,max(0,limit-protectedBytes-Self.metadataAllowance))
            if granted<minimumPayload {granted=payload}
            required=granted+Self.metadataAllowance
        }
        // Do not delete any evidence if protected data makes this request impossible.
        guard protectedBytes+required<=limit else {
            throw NSError(domain:"PhysicalGo.Diagnostics",code:3,userInfo:[NSLocalizedDescriptionKey:"Diagnostic storage is occupied by active captures, kept evidence or unrecognized files. Close a capture or check the archive folders to make room."])
        }
        var removed=0
        for archive in eligible where used+required>limit {
            try fm.removeItem(at:archive.url);used-=archive.bytes;removed+=1
        }
        rotatedCount+=removed
        return create(granted,removed)
    }
}
