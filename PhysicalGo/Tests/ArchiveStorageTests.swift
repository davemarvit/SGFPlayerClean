import Foundation
@main struct ArchiveStorageTests {
    @MainActor static func main() throws {
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("storage-flex-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:root)}
        try Data(repeating:0,count:100).write(to:root.appendingPathComponent(".DS_Store"))
        let store=DiagnosticArchiveStorage(roots:[root],limit:2_000_000)
        let available=try store.allocate(payload:1_000_000,minimumPayload:100) {limit,_ in limit}
        precondition(available==999_900,"Small protected metadata prevented continuous capture")
        do {_=try store.allocate(payload:1_000_000) {_,_ in ()};preconditionFailure("Automatic clip lost its reservation")} catch {}
        precondition(fm.fileExists(atPath:root.appendingPathComponent(".DS_Store").path))
        let file=root.appendingPathComponent("lease")
        var active:DiagnosticArchiveLock?=try DiagnosticArchiveLock(file)
        do {_=try DiagnosticArchiveLock(file);preconditionFailure("Active lease was acquired twice")} catch {}
        withExtendedLifetime(active) {};active=nil
        let reopened=try DiagnosticArchiveLock(file);withExtendedLifetime(reopened) {}
        print("PASS: archive allocation tolerates metadata, reserves full automatic clips, protects unknown files, and releases writer locks")
    }
}
