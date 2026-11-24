import Foundation

/// Independent persistence and unit-boundary checks; temporary files only.
@main struct StoneSetProfileReviewTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String) {
        precondition(value,message);checks+=1
    }
    static func rejects(_ body:()throws->Void,_ message:String) {
        do {try body();preconditionFailure(message)} catch {checks+=1}
    }
    static func candidate()->StoneOpticalHeightCandidate {
        .init(value:0.2,units:.rowPitch,referenceBoardPitchID:"original-board-spacing",
              measurementModelID:"review-model",measurementModelVersion:"1",setupModelID:"original-setup",
              geometryHypothesisID:"conditional-grid",geometryAssumptions:["Original intrinsics required"],
              confidence:.init(description:"Uncalibrated evidence",sampleCount:1),
              uncertainty:.init(kind:.unknown,description:"Unknown uncertainty"),
              compatibility:.init(description:"No cross-setup validation"),
              captures:[.init(captureID:"original-capture",imageSHA256:String(repeating:"a",count:64),metadataSHA256:String(repeating:"b",count:64))],
              sourceCodeSHA256:["source.swift":String(repeating:"c",count:64)])
    }
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("stone-set-independent-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("library.json")
        let store=StoneSetProfileStore(fileURL:file)
        var profile=StoneSetProfile(name:"Original set")
        profile.white.opticalHeightCandidates=[candidate()]
        check(store.save(profile),"Initial valid library must save")
        let before=try Data(contentsOf:file),memory=store.library
        var large=profile
        large.white.opticalHeightCandidates[0].confidence.description=String(repeating:"x",count:2_000_001)
        check(!store.save(large),"A successful save must not create a library its own loader rejects")
        check(store.library==memory && store.error != nil,"Oversized save must preserve selected in-memory data")
        check(try Data(contentsOf:file)==before,"Oversized save must preserve original disk bytes")
        let reloaded=StoneSetProfileStore(fileURL:file)
        check(reloaded.error==nil && reloaded.selected?.id==profile.id,"Previous library must remain reloadable after rejected save")
        store.select(UUID())
        check(store.library==memory && store.error != nil,"Invalid selection must preserve existing selection")
        check(try Data(contentsOf:file)==before,"Invalid selection must preserve original file")

        let blocker=root.appendingPathComponent("ordinary-file")
        let sentinel=Data("preserve me".utf8);try sentinel.write(to:blocker)
        let blocked=StoneSetProfileStore(fileURL:blocker.appendingPathComponent("library.json"))
        check(!blocked.save(profile),"Directory creation/write failure must be reported")
        check(blocked.library.profiles.isEmpty && blocked.selected==nil && blocked.error != nil,"Failed filesystem save cannot appear selected in memory")
        check(try Data(contentsOf:blocker)==sentinel,"Write failure must preserve unrelated file bytes")

        var relative=candidate()
        relative.metricConversion = .init(rowPitchMm:23,source:"Measured original board")
        try relative.validate()
        check(abs(relative.opticalMillimetres!-4.6)<1e-12 && relative.units == .rowPitch && relative.value==0.2,"Conversion must retain original relative measurement")
        relative.value=Double.greatestFiniteMagnitude
        rejects({try relative.validate()},"Overflowing metric conversion must be rejected")
        var metric=candidate();metric.units = .millimetres;metric.metricScaleSource="Independent original metric scale"
        try metric.validate()
        metric.metricConversion = .init(rowPitchMm:23,source:"Another board")
        rejects({try metric.validate()},"Already metric candidates cannot silently receive a second pitch conversion")
        var interval=candidate();interval.uncertainty.lower=0.1
        rejects({try interval.validate()},"Unknown uncertainty must not retain claimed numeric bounds")
        var missingSetup=candidate();missingSetup.setupModelID=" \n "
        rejects({try missingSetup.validate()},"Original setup identity cannot be empty")
        print("PASS: \(checks) independent stone-set persistence/unit checks")
    }
}
