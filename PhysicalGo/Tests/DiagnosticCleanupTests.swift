import AppKit

@main struct DiagnosticCleanupTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        let fm=FileManager.default,root=FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic-cleanup-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? fm.removeItem(at:root)}
        let clips=root.appendingPathComponent("clips"),continuous=root.appendingPathComponent("continuous")
        func archive(_ name:String,in folder:URL,status:String="complete",date:Double=1)throws->URL {
            let url=folder.appendingPathComponent("Diagnostic "+name)
            try fm.createDirectory(at:url,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:["schemaVersion":1,"startedAt":date,"updatedAt":date,"status":status]).write(to:url.appendingPathComponent("session.json"))
            try Data("image".utf8).write(to:url.appendingPathComponent("frame.png"))
            return url
        }
        let old=try archive("old",in:clips),other=try archive("continuous",in:continuous)
        let kept=try archive("kept",in:clips);try Data().write(to:kept.appendingPathComponent("KEEP"))
        let active=try archive("active",in:clips,status:"recording")
        var lease:DiagnosticArchiveLock?=try DiagnosticArchiveLock(active.appendingPathComponent(".writer.lock"))
        let legacy=try archive("legacy",in:continuous,status:"recording",date:Date().timeIntervalSince1970)
        let crashed=try archive("crashed",in:clips,status:"recording");try Data().write(to:crashed.appendingPathComponent(".writer.lock"))
        let outside=try archive("outside",in:root)
        let linked=clips.appendingPathComponent("Diagnostic link");try fm.createSymbolicLink(at:linked,withDestinationURL:outside)
        let unknown=clips.appendingPathComponent("Diagnostic unknown");try fm.createDirectory(at:unknown,withIntermediateDirectories:true)
        let sgf=root.appendingPathComponent("game.sgf");try Data("game".utf8).write(to:sgf)
        let first=try DiagnosticArchiveStorage.clearInactive(roots:[clips,continuous])
        check(first.removed==3 && first.failures.isEmpty,"Both archive types and abandoned writer were not removed")
        check(!fm.fileExists(atPath:old.path) && !fm.fileExists(atPath:other.path) && !fm.fileExists(atPath:crashed.path),"Completed camera archives remain")
        check(first.kept==1 && fm.fileExists(atPath:kept.path),"Kept evidence was deleted")
        check(first.active==2 && fm.fileExists(atPath:active.path) && fm.fileExists(atPath:legacy.path),"Active or recent legacy writer was deleted")
        check(first.unrecognized==2 && fm.fileExists(atPath:outside.path) && fm.fileExists(atPath:unknown.path),"Unknown data or link destination was deleted")
        check(try String(contentsOf:sgf)=="game","Cleanup touched games outside archive roots")
        withExtendedLifetime(lease) {};lease=nil
        let second=try DiagnosticArchiveStorage.clearInactive(roots:[clips,continuous])
        check(second.removed==1 && !fm.fileExists(atPath:active.path),"Closed writer could not be cleared")
        let third=try DiagnosticArchiveStorage.clearInactive(roots:[clips,continuous])
        check(third.removed==0,"Repeated cleanup was not harmless")
        let protected=try archive("lock test",in:clips)
        do {
            let lock=try DiagnosticArchiveLock(clips.appendingPathComponent(".rotation.lock"))
            defer {withExtendedLifetime(lock) {}}
            do {_=try DiagnosticArchiveStorage.clearInactive(roots:[clips]);check(false,"Cleanup ignored storage lock")}
            catch {check(fm.fileExists(atPath:protected.path),"Busy storage was partially cleared")}
        }
        let linkedRoot=root.appendingPathComponent("linked-root");try fm.createSymbolicLink(at:linkedRoot,withDestinationURL:clips)
        do {_=try DiagnosticArchiveStorage.clearInactive(roots:[linkedRoot]);check(false,"Symbolic root was accepted")}
        catch {check(fm.fileExists(atPath:protected.path),"Symbolic root deletion escaped scope")}
        let recorder=GameRecorder(storage:root.appendingPathComponent("games"));recorder.clock.audible=false
        recorder.start(size:9,startPaused:true)
        let game=recorder.autosaveURL!,journal=game.deletingPathExtension().appendingPathExtension("observations.jsonl")
        check(fm.fileExists(atPath:journal.path),"Unfinished game lacks recovery evidence")
        check(try !recorder.discardFinishedObservationLog(exportedSGF:recorder.sgf(),keepDiagnostics:false),"Mid-game export cleared recovery evidence")
        recorder.finish()
        let saved=recorder.sgf(),clock=recorder.clock.engine
        check(try !recorder.discardFinishedObservationLog(exportedSGF:saved,keepDiagnostics:true) && fm.fileExists(atPath:journal.path),"Diagnostics mode discarded development evidence")
        check(try !recorder.discardFinishedObservationLog(exportedSGF:"stale export",keepDiagnostics:false) && fm.fileExists(atPath:journal.path),"Stale export cleared current evidence")
        check(try recorder.discardFinishedObservationLog(exportedSGF:saved,keepDiagnostics:false) && !fm.fileExists(atPath:journal.path),"Final normal export did not clear observation log")
        check(recorder.sgf()==saved && recorder.clock.engine==clock && fm.fileExists(atPath:game.path),"Cleanup changed saved game or clock")
        recorder.logClockDiagnostic(["event":"test after cleanup"],now:100)
        check(!fm.fileExists(atPath:journal.path),"Live callbacks recreated cleared log")
        check(try recorder.discardFinishedObservationLog(exportedSGF:saved,keepDiagnostics:false),"Repeat final export failed")
        let restored=GameRecorder(storage:root.appendingPathComponent("games"));restored.clock.audible=false
        try restored.restoreSavedGame(from:game)
        check(!fm.fileExists(atPath:journal.path),"Opening an exported game recreated diagnostic data")
        restored.resume()
        check(fm.fileExists(atPath:journal.path),"Resuming play did not restart recovery evidence")
        print("PASS: \(checks) diagnostic cleanup checks")
    }
}
