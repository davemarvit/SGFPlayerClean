import Foundation

/// Independent transaction failures through the real controller and store.
/// Every file and bridge request belongs to a temporary directory.
@MainActor enum PhysicalAIPracticeCaptureReviewTests {
    private struct InjectedFailure:Error {}
    private final class Writes {
        var fail:String?
        func write(_ data:Data,to url:URL)throws {
            if fail == url.lastPathComponent || (fail == "sgf" && url.pathExtension == "sgf") {throw InjectedFailure()}
            try data.write(to:url,options:.atomic)
        }
    }
    private static func original()->PhysicalAI.Snapshot {
        var settings=PhysicalAISettings();settings.size=19;settings.humanBlack=false
        var timing=PhysicalAITiming();timing.resume(at:100);timing.move(black:true,at:112.5);timing.pause(at:146.75)
        return .init(id:UUID(),settings:settings,
            moves:[.init(point:72,decisionReceivedAtUnix:1234),.init(point:180),.init(point:300,decisionReceivedAtUnix:1250)],
            timing:timing)
    }
    private static func seed(_ value:PhysicalAI.Snapshot,in folder:URL)throws->Data {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
        object["futureMetadata"]=["preserve":"original bytes, including unknown fields"]
        let data=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
        try data.write(to:folder.appendingPathComponent("current.json"))
        return data
    }
    private static func controller(_ folder:URL,writes:Writes)->PhysicalAI {
        PhysicalAI(directory:folder,generate:{_,_ in "pass"},
            laser:PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false),
            practiceStore:PhysicalAIPracticeStore(directory:folder,write:{try writes.write($0,to:$1)}),uptime:{200})
    }
    static func run() async throws -> Int {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("practice-independent-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        // Failure before or at the authoritative write cannot partially install
        // a new game, reset elapsed time, or discard future snapshot metadata.
        for stage in ["previous-game.json","sgf","current.json"] {
            let folder=root.appendingPathComponent("failure-"+stage),saved=original()
            let bytes=try seed(saved,in:folder),writes=Writes(),ai=controller(folder,writes:writes)
            let timing=ai.timing,draft=ai.draft
            writes.fail=stage
            check(!ai.loadPracticePosition(.singleCapture),"Injected load failure must be reported: "+stage)
            check(try Data(contentsOf:folder.appendingPathComponent("current.json"))==bytes,"Failed load must preserve authoritative bytes: "+stage)
            check(ai.snapshot?.id==saved.id && ai.phase == .paused && ai.timing==timing,"Failed load must preserve game/phase/clock: "+stage)
            check(ai.draft==draft,"Failed load must preserve setup settings")
            writes.fail=nil
            check(ai.loadPracticePosition(.singleCapture),"A failed load must allow a clean retry")
            check(ai.snapshot?.id != saved.id && ai.snapshot!.moves.allSatisfy{$0.decisionReceivedAtUnix==nil},"Fixture has new identity and no invented decision receipts")
            check(ai.returnFromPracticePosition(),"Retried load must retain usable original backup")
            check(try Data(contentsOf:folder.appendingPathComponent("current.json"))==bytes,"Return must preserve original unknown fields and timestamps exactly")
        }
        do {
            let folder=root.appendingPathComponent("return-retry"),saved=original()
            let originalBytes=try seed(saved,in:folder),writes=Writes(),ai=controller(folder,writes:writes)
            check(ai.loadPracticePosition(.twoStoneCapture),"Return failure fixture loads")
            let current=folder.appendingPathComponent("current.json"),testBytes=try Data(contentsOf:current)
            let testID=ai.snapshot!.id,context=ai.snapshot!.practiceTest!,timing=ai.timing
            let store=PhysicalAIPracticeStore(directory:folder),backup=store.backupURL(context)
            let backupBytes=try Data(contentsOf:backup)
            writes.fail="current.json"
            check(!ai.returnFromPracticePosition(),"Restore current failure must be reported")
            check(try Data(contentsOf:current)==testBytes,"Failed restore must retain authoritative practice data")
            check(ai.snapshot?.id==testID && ai.phase == .paused && ai.timing==timing,"Failed restore must not install prior game in memory")
            let archived=backup.deletingLastPathComponent().appendingPathComponent("last-test.json")
            check(try Data(contentsOf:archived)==testBytes,"Outgoing test is preserved before restore commit")
            writes.fail=nil
            check(ai.returnFromPracticePosition(),"Already-written outgoing archive must not prevent retry")
            check(try Data(contentsOf:current)==originalBytes,"Successful retry restores exact original save")
            check(try Data(contentsOf:backup)==backupBytes,"Return attempts cannot modify immutable original backup")
        }
        do {
            let folder=root.appendingPathComponent("same-test-stale"),saved=original()
            _=try seed(saved,in:folder);let writes=Writes(),ai=controller(folder,writes:writes)
            check(ai.loadPracticePosition(.singleCapture),"Stale-current fixture loads")
            let current=folder.appendingPathComponent("current.json"),testBytes=try Data(contentsOf:current)
            var changed=try JSONSerialization.jsonObject(with:testBytes) as! [String:Any]
            changed["externalNote"]="same UUID, changed authoritative bytes"
            let changedBytes=try JSONSerialization.data(withJSONObject:changed,options:[.sortedKeys]);try changedBytes.write(to:current,options:.atomic)
            check(!ai.returnFromPracticePosition(),"Same-ID external edits must fence stale Return")
            check(try Data(contentsOf:current)==changedBytes,"Stale Return cannot overwrite external metadata")
            let unrelated=original(),unrelatedBytes=try JSONEncoder().encode(unrelated)
            try unrelatedBytes.write(to:current,options:.atomic)
            check(!ai.returnFromPracticePosition(),"An unrelated later game must fence stale Return")
            check(try Data(contentsOf:current)==unrelatedBytes,"Stale Return cannot overwrite unrelated later game")
            let reopened=controller(folder,writes:Writes())
            check(reopened.snapshot?.id==unrelated.id && !reopened.canReturnFromPracticePosition,"Reopened later game cannot inherit old test-return authority")
        }
        // Restart at either fallible return write. The newly constructed
        // controller must recover authority from disk, not the old instance.
        for ended in [false,true] {
            for stage in ["last-test.json","current.json"] {
                let folder=root.appendingPathComponent("restart-\(ended)-"+stage)
                var saved=original();saved.ended=ended;saved.result=ended ? "W+R":nil
                let originalBytes=try seed(saved,in:folder),writes=Writes(),ai=controller(folder,writes:writes)
                check(ai.loadPracticePosition(.twoStoneCapture),"Restart fixture loads from paused or finished game")
                let test=ai.snapshot!,context=test.practiceTest!,current=folder.appendingPathComponent("current.json")
                let testBytes=try Data(contentsOf:current),store=PhysicalAIPracticeStore(directory:folder)
                let backup=store.backupURL(context),backupBytes=try Data(contentsOf:backup)
                writes.fail=stage
                check(!ai.returnFromPracticePosition(),"Injected return failure is visible before restart: "+stage)
                check(try Data(contentsOf:current)==testBytes,"Interrupted return preserves authoritative test bytes")
                let reopened=controller(folder,writes:Writes())
                check(reopened.snapshot?.id==test.id && reopened.canReturnFromPracticePosition && reopened.phase == .paused,
                    "Reconstructed controller owns the same paused test and durable return context")
                check(reopened.returnFromPracticePosition(),"Return retries successfully after controller reconstruction")
                check(try Data(contentsOf:current)==originalBytes,"Restarted retry restores unknown metadata and original bytes exactly")
                check(reopened.snapshot?.id==saved.id && reopened.timing==saved.timing && reopened.phase == (ended ? .finished:.paused),
                    "Restarted retry restores original identity, clocks and finished/paused state")
                check(try Data(contentsOf:backup)==backupBytes,"Restarted retry cannot alter immutable backup")
                check(try Data(contentsOf:backup.deletingLastPathComponent().appendingPathComponent("last-test.json"))==testBytes,
                    "Restarted retry archives outgoing test before restoration")
                let restored=controller(folder,writes:Writes())
                check(restored.snapshot?.id==saved.id && !restored.canReturnFromPracticePosition,
                    "A second reconstruction cannot resurrect old fixture-return authority")
                check(restored.laser.target==nil && restored.laser.playSession==nil,
                    "Restoration and reconstruction cannot activate an old laser target")
            }
        }
        for missing in [false,true] {
            let folder=root.appendingPathComponent(missing ? "missing-backup":"corrupt-backup"),saved=original()
            let originalBytes=try seed(saved,in:folder),ai=controller(folder,writes:Writes())
            check(ai.loadPracticePosition(.singleCapture),"Damaged-backup fixture loads")
            let context=ai.snapshot!.practiceTest!,current=folder.appendingPathComponent("current.json")
            let testBytes=try Data(contentsOf:current),backup=PhysicalAIPracticeStore(directory:folder).backupURL(context)
            let backupBytes=try Data(contentsOf:backup)
            if missing {try FileManager.default.removeItem(at:backup)}
            else {try Data("damaged synthetic backup".utf8).write(to:backup,options:.atomic)}
            let reopened=controller(folder,writes:Writes())
            check(!reopened.returnFromPracticePosition(),"Missing or corrupted backup must fail closed after restart")
            check(try Data(contentsOf:current)==testBytes && reopened.snapshot?.id==context.testID,
                "Rejected restoration preserves authoritative test file and in-memory identity")
            check(reopened.phase == .paused && reopened.practiceError != nil && reopened.laser.target==nil,
                "Backup failure stays paused with actionable error and no laser target")
            // Repair only this test's deliberately damaged temporary backup;
            // production never guesses replacement bytes or discards a game.
            try backupBytes.write(to:backup,options:.atomic)
            check(reopened.returnFromPracticePosition(),"Exact backup repair permits retry without replacing the test")
            check(try Data(contentsOf:current)==originalBytes,"Retry after exact repair restores original bytes")
        }
        do {
            let folder=root.appendingPathComponent("wrong-backup-identity"),saved=original()
            _=try seed(saved,in:folder);let writes=Writes(),ai=controller(folder,writes:writes)
            check(ai.loadPracticePosition(.singleCapture),"Backup identity fixture loads")
            let current=folder.appendingPathComponent("current.json"),context=ai.snapshot!.practiceTest!
            let backup=PhysicalAIPracticeStore(directory:folder).backupURL(context)
            var object=try JSONSerialization.jsonObject(with:Data(contentsOf:backup)) as! [String:Any]
            object["testID"]=UUID().uuidString
            let badBackup=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]);try badBackup.write(to:backup,options:.atomic)
            var forged=ai.snapshot!
            forged.practiceTest = .init(position:context.position,testID:context.testID,previousGameID:context.previousGameID,
                backupSHA256:PhysicalAIPracticeStore.digest(badBackup))
            let forgedBytes=try JSONEncoder().encode(forged);try forgedBytes.write(to:current,options:.atomic)
            let reopened=controller(folder,writes:Writes())
            check(!reopened.returnFromPracticePosition(),"Matching hash must not authorize another test's backup record")
            check(try Data(contentsOf:current)==forgedBytes,"Rejected backup identity must preserve current game")
        }
        do {
            let folder=root.appendingPathComponent("controller-only-latch"),saved=original()
            _=try seed(saved,in:folder)
            let laser=PhysicalLaserGuidance(directory:folder.appendingPathComponent("bridge"),automatic:false,wallTime:{1000},uptime:{200})
            let ai=PhysicalAI(directory:folder,generate:{_,_ in "pass"},laser:laser,uptime:{200},wallTime:{1000})
            func request()throws->PhysicalLaserGuidance.Request {
                try JSONDecoder().decode(PhysicalLaserGuidance.Request.self,from:Data(contentsOf:laser.directory.appendingPathComponent("request.json")))
            }
            func status(_ state:String="off")throws {
                let r=try request()
                let evidence=PhysicalLaserGuidance.EvidenceAfter(streamEpoch:laser.frames.streamEpoch,frameID:1,timestampSource:"cameraPresentation")
                var s=PhysicalLaserGuidance.DriverStatus(schemaVersion:r.schemaVersion,producer:laser.producer,sequence:r.sequence,
                    updatedAtUnix:1000,mode:"hardware",state:state,laserOn:false,offSinceUnix:state=="off" ? 999:nil,
                    detail:"Independent simulated receipt",evidenceAfter:state=="off" ? evidence:nil,setupId:"review-setup",
                    capabilities:["darkMotorStandbyV1"],playSession:r.playSession,cameraContext:r.cameraContext,streamEpoch:r.streamEpoch,
                    motorsHeld:false,motorBusPowered:false,
                    thermal:.init(policy:"warm_hold",sampleSequence:1,receivedAtUnix:1000,sampleAgeUpperMs:100,
                        baseC:20,tiltC:21,maxBaseC:20,maxTiltC:21,unavailableReason:"power_off"))
                if state=="fault" {s.reasonCode="controller_fault";s.requiresNewRevision=true}
                try JSONEncoder().encode(s).write(to:laser.directory.appendingPathComponent("status.json"),options:.atomic)
                laser.tick()
            }
            laser.setPlaySession(.init(source:"ai",session:saved.id,size:19));laser.setStandbyEnabled(true);laser.setEnabled(true)
            let frame=PhysicalLaserFrameBroker.Frame(streamEpoch:laser.frames.streamEpoch,frameID:100,capturedAtUptime:200,
                arrivedAtUptime:200,capturedAtUnix:1000,timestampSource:"cameraPresentation",presentationSeconds:200)
            laser.noteFrame(frame);laser.observeCamera(hand:false,valid:true,capturedAt:200,now:200,context:"review-camera")
            try status();try status()
            check(try request().schemaVersion==2,"Fault case must enter actual schema2 shutdown lifecycle")
            laser.setPlaySession(nil)
            try status("fault")
            check(laser.controllerResetRequired && !laser.gameFaultNeedsRecheck && laser.playSession==nil,"Closing receipt must produce real controller-only latch without game scope")
            check(ai.loadPracticePosition(.emptyHumanBlack),"Controller-only fault may be preserved in a separate paused test")
            check(ai.snapshot?.guidanceInterruption=="controller_fault" && ai.snapshot?.laserRecheckReason=="controller_fault","New test UUID must durably inherit controller-only recovery requirement")
            ai.resume();check(ai.phase == .paused,"New practice cannot Resume past inherited controller-only fault")
            check(ai.returnFromPracticePosition(),"Prior game can be restored while preserving controller-only fault")
            let reopened=controller(folder,writes:Writes())
            check(reopened.snapshot?.id==saved.id && reopened.laser.controllerResetRequired && reopened.laser.gameFaultNeedsRecheck,"Controller-only requirement survives return and app reconstruction")
        }
        return checks
    }
}
