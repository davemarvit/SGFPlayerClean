import Foundation

@main struct StoneSetProfileTests {
    static var count=0
    static func check(_ valid:Bool,_ message:String) {
        count+=1
        if !valid {fatalError(message)}
    }
    static func rejects(_ body:()throws->Void,_ message:String) {
        do {try body();fatalError("Accepted: \(message)")} catch {count+=1}
    }
    static func candidate()->StoneOpticalHeightCandidate {
        StoneOpticalHeightCandidate(value:0.22,units:.rowPitch,referenceBoardPitchID:"board-A-spacing",
            measurementModelID:"visible-body",measurementModelVersion:"1",setupModelID:"setup-A",
            geometryHypothesisID:"native-grid",geometryAssumptions:["Conditional camera intrinsics"],
            confidence:.init(description:"Eight explicitly confirmed white stones; uncalibrated support",sampleCount:8),
            uncertainty:.init(kind:.sensitivityRange,lower:0.20,upper:0.27,description:"Sensitivity to two grid hypotheses, not a statistical confidence interval"),
            compatibility:.init(description:"Recheck geometry, spacing and visible-body model in a new setup"),
            heldOutReportID:"top-bottom-heldout",captures:[.init(captureID:"capture-A",imageSHA256:String(repeating:"a",count:64),metadataSHA256:String(repeating:"b",count:64))],
            sourceCodeSHA256:["estimator.py":String(repeating:"c",count:64)])
    }
    @MainActor static func main() throws {
        if CommandLine.arguments.count>1 {
            let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
            let source=URL(fileURLWithPath:CommandLine.arguments[1])
            let imported=try decoder.decode(StoneSetProfile.self,from:Data(contentsOf:source))
            try imported.validate()
            check(!imported.black.opticalHeightCandidates.isEmpty && !imported.white.opticalHeightCandidates.isEmpty,"Actual offline producer supplies separate sourced candidates for both colors")
            check(imported.black.physicalThicknessMm == nil && imported.white.physicalThicknessMm == nil,"Unmeasured physical thickness stays unknown in actual producer output")
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("stone-profile-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("library.json")
        let store=StoneSetProfileStore(fileURL:file)
        check(store.library.profiles.isEmpty && !FileManager.default.fileExists(atPath:file.path),"Opening absent library doesn't write or invent a set")
        var set=StoneSetProfile(name:"Club glass")
        try set.validate()
        check(set.black.physicalThicknessMm == nil && set.white.physicalThicknessMm == nil,"Unknown thickness is a valid default")
        check(store.save(set),"Save named set without thickness or automatic estimate")
        check(store.selected?.id == set.id,"Save selects profile for later calibration")
        set.black.physicalThicknessMm = .init(value:9.1)
        set.white.physicalThicknessMm = .init(value:8.8,uncertaintyMm:0.1)
        let automatic=candidate()
        set.white.opticalHeightCandidates=[automatic]
        check(store.save(set),"Measured thickness and separate camera estimate coexist")
        check(store.selected?.white.physicalThicknessMm?.value == 8.8,"Camera estimate never overwrites physical thickness")
        check(automatic.opticalMillimetres == nil,"Unknown board spacing cannot invent millimetres")
        var metric=automatic;metric.metricConversion = .init(rowPitchMm:23.0,source:"User ruler measurement")
        try metric.validate()
        check(abs(metric.opticalMillimetres!-5.06)<1e-9 && metric.value == automatic.value && metric.units == .rowPitch,"Metric conversion preserves original board-relative quantity")
        var second=automatic;second.candidateID=UUID();second.geometryHypothesisID="independent-ink-grid";second.value=0.25
        set.white.opticalHeightCandidates.append(second)
        check(store.save(set) && store.selected?.white.opticalHeightCandidates.count == 2,"Conflicting geometry hypotheses remain distinct candidates")
        var missingPitch=automatic;missingPitch.referenceBoardPitchID=nil
        rejects({try missingPitch.validate()},"Row-pitch estimate without board-spacing identity")
        var bogusMetric=automatic;bogusMetric.units = .millimetres
        rejects({try bogusMetric.validate()},"Direct metric estimate without metric-scale provenance")
        var noProvenance=automatic;noProvenance.sourceCodeSHA256=[:]
        rejects({try noProvenance.validate()},"Automatic candidate without source hashes")
        var falseProbability=automatic;falseProbability.confidence.calibrationStatus="calibratedProbability"
        rejects({try falseProbability.validate()},"Descriptive support relabeled calibrated probability")
        var missingReport=automatic;missingReport.compatibility.independentSetupValidation = .passed
        rejects({try missingReport.validate()},"Independent validation claim without report")
        var active=automatic;active.status="active"
        rejects({try active.validate()},"Profile cannot claim runtime activation")
        var duplicate=set;duplicate.white.opticalHeightCandidates.append(automatic)
        rejects({try duplicate.validate()},"Candidate identity overwritten or duplicated")
        var badThickness=set;badThickness.black.physicalThicknessMm = .init(value:.nan)
        rejects({try badThickness.validate()},"Nonfinite manual thickness")
        var badInterval=automatic;badInterval.uncertainty.lower=0.23
        rejects({try badInterval.validate()},"Interval excludes point estimate")
        let beforeOversize=try Data(contentsOf:file)
        let selectedBeforeOversize=store.selected?.id
        var oversized=set
        oversized.white.opticalHeightCandidates[0].confidence.description=String(repeating:"x",count:2_000_000)
        check(!store.save(oversized),"Encoded library exceeding the load bound cannot be saved")
        check(try Data(contentsOf:file) == beforeOversize,"Oversized save preserves the previous file bytes")
        check(store.selected?.id == selectedBeforeOversize && store.selected?.white.opticalHeightCandidates[0].confidence.description == set.white.opticalHeightCandidates[0].confidence.description,"Oversized save preserves published selection and model")
        let blockedURL=root.appendingPathComponent("blocked-library.json")
        let blocked=StoneSetProfileStore(fileURL:blockedURL)
        try FileManager.default.createDirectory(at:blockedURL,withIntermediateDirectories:false)
        check(!blocked.save(StoneSetProfile(name:"Cannot write")),"A real file-write failure is reported")
        check(blocked.library.profiles.isEmpty && blocked.error != nil,"Write failure does not publish unsaved data")
        check((try FileManager.default.contentsOfDirectory(at:blockedURL,includingPropertiesForKeys:nil)).isEmpty,"Write failure preserves the conflicting directory")
        let reloaded=StoneSetProfileStore(fileURL:file)
        check(reloaded.selected?.id == set.id && reloaded.selected?.white.opticalHeightCandidates.count == 2,"Named selection and all candidates survive reload")
        reloaded.select(nil)
        check(reloaded.selected == nil && reloaded.library.profiles.count == 1,"Deselect preserves profile data")
        reloaded.select(UUID())
        check(reloaded.selected == nil && reloaded.error != nil,"Unknown selected ID cannot be saved")
        let before=try Data(contentsOf:file)
        var sameName=StoneSetProfile(name:" club GLASS ")
        check(!reloaded.save(sameName),"Duplicate user-visible names rejected")
        check(try Data(contentsOf:file) == before,"Invalid edit leaves saved library byte-identical")
        sameName.name="Travel slate"
        check(reloaded.save(sameName),"Different reusable set can be added")
        let corrupt=root.appendingPathComponent("broken.json")
        let invalid=Data("{bad json".utf8);try invalid.write(to:corrupt)
        let broken=StoneSetProfileStore(fileURL:corrupt)
        check(!broken.save(StoneSetProfile(name:"New")) && broken.error != nil,"Unreadable library blocks replacement")
        check(try Data(contentsOf:corrupt) == invalid,"Failed load never destroys existing bytes")
        print("PASS: \(count) stone-set profile, provenance, selection and persistence checks")
    }
}
