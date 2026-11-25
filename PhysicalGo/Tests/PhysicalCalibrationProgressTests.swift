import Foundation

@main struct PhysicalCalibrationProgressTests {
    static var checks=0
    static func check(_ condition:Bool,_ message:String) {
        checks+=1
        if !condition {fatalError(message)}
    }
    static func data(_ overrides:[String:Any]=[:])->Data {
        var d:[String:Any]=["schemaVersion":1,"runID":"D0E591E0-55FB-48F4-814B-57417E449102","sequence":1,
            "startedAtUnix":1000.0,"startedAtUptime":50.0,"updatedAtUnix":1010.0,
            "elapsedSeconds":10.0,"stageElapsedSeconds":2.0,"bindingActivated":false,
            "state":"running","stage":"fit","mode":"full_calibration","target":"K10",
            "fitCompleted":1,"fitTotal":5,"validationCompleted":0,"validationTotal":9]
        d.merge(overrides){_,new in new}
        return try! JSONSerialization.data(withJSONObject:d)
    }
    static func main() {
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/CalibrationProgress.json")
        var contract=PhysicalCalibrationProgressReader()
        contract.accept(try! Data(contentsOf:fixture),now:1010)
        check(contract.latest?.fitCompleted == 5 && contract.latest?.validationCompleted == 3 && contract.latest?.target == "K10", "Actual Python publisher fixture decodes with intended progress")
        for (file,mode,completed,total) in [("ThreePointProgress.json","three_point_seed",2,3),("FeedbackProgress.json","feedback_check",1,2)] {
            var actual=PhysicalCalibrationProgressReader()
            actual.accept(try! Data(contentsOf:fixture.deletingLastPathComponent().appendingPathComponent(file)),now:1010)
            check(actual.latest?.mode == mode && actual.latest?.completed == completed && actual.latest?.total == total,"Actual minimal publisher contract decodes: \(file)")
        }
        var reader=PhysicalCalibrationProgressReader()
        reader.accept(data(),now:1010)
        check(reader.latest?.completed == 1,"Actual completed point count")
        check(reader.latest?.total == 14,"Fit and validation counts include repeated K10 separately")
        check(!reader.interrupted(now:1012.9),"Fresh update stays current")
        check(reader.interrupted(now:1013.1),"Heartbeat loss stops active presentation")
        reader.accept(Data("broken".utf8),now:1010)
        check(reader.interrupted(now:1010),"Malformed status cannot reuse active claim")
        reader.accept(data(),now:1010)
        check(!reader.unavailable,"A new valid read restores display")
        for bad in [["schemaVersion":2],["bindingActivated":true],["fitCompleted":6],
                    ["state":"candidate_ready"],["elapsedSeconds":1e99],["updatedAtUnix":1013.0],
                    ["target":"I10"],["target":"A0"],["stage":"unknown"],["mode":"unknown"]] as [[String:Any]] {
            var r=PhysicalCalibrationProgressReader();r.accept(data(bad),now:1010)
            check(r.latest == nil,"Reject malformed or misleading status: \(bad)")
        }
        reader.accept(data(["sequence":2,"fitCompleted":2,"elapsedSeconds":11.0,"updatedAtUnix":1011.0]),now:1011)
        reader.accept(data(),now:1011)
        check(reader.latest?.completed == 2 && reader.unavailable,"Old sequence cannot roll back progress")
        let newer="063964DA-D4D6-462E-8A26-A25CD4872732"
        reader.accept(data(["runID":newer,"startedAtUnix":1010.0,"updatedAtUnix":1011.0,"fitCompleted":0]),now:1011)
        check(reader.latest?.runID == newer && reader.latest?.completed == 0,"New run resets progress")
        reader.accept(data(),now:1011)
        check(reader.latest?.runID == newer,"Delayed previous-run writer ignored")
        var complete=PhysicalCalibrationProgressReader()
        complete.accept(data(["fitCompleted":5,"validationCompleted":9,"state":"candidate_ready","stage":"model_review"]),now:1010)
        check(complete.latest?.state == "candidate_ready" && complete.latest?.bindingActivated == false,"Completed measurements never activate map")
        check(!complete.interrupted(now:9999),"Terminal status is dated history, not a live heartbeat")
        complete.accept(data(["sequence":2,"fitCompleted":5,"validationCompleted":9]),now:1011)
        check(complete.latest?.state == "candidate_ready" && complete.unavailable,"Terminal run cannot silently restart")
        var spot=PhysicalCalibrationProgressReader()
        spot.accept(data(["mode":"spot_check","fitCompleted":0,"fitTotal":0,"validationTotal":0,"state":"spot_verified"]),now:1010)
        check(spot.latest?.total == 0 && spot.latest?.state == "spot_verified","Spot check distinct from whole-board calibration")
        // Minimal setup and feedback are distinct workflows, never five-plus-nine
        // calibration or an approval to activate gameplay.
        var seed=PhysicalCalibrationProgressReader()
        let seedFields:[String:Any]=["mode":"three_point_seed","stage":"seed","fitTotal":3,"validationTotal":0]
        seed.accept(data(seedFields),now:1010)
        check(seed.latest?.total == 3 && seed.latest?.workflowTitle == "Three-point laser setup","Three-point seed has truthful route totals")
        check(seed.latest?.countSummary == "1 of 3 seed observations collected","Transit measurements do not appear as extra seed points")
        seed.accept(nil,now:1011)
        check(seed.latest?.fitCompleted == 1 && seed.unavailable,"Interrupted display retains collected observations")
        seed.accept(data(seedFields.merging(["sequence":2,"fitCompleted":3,"state":"seed_ready"]){_,n in n}),now:1011)
        check(seed.latest?.state == "seed_ready" && !seed.unavailable,"Valid terminal seed evidence preserves completed points")
        check(seed.latest?.bindingActivated == false,"Three-point completion cannot activate a binding")
        for mode in ["three_point_seed","feedback_check"] {
            let fields:[String:Any]=["mode":mode,"stage":mode == "three_point_seed" ? "seed":"feedback",
                "fitCompleted":mode == "three_point_seed" ? 1:0,"fitTotal":mode == "three_point_seed" ? 3:0,
                "validationCompleted":0,"validationTotal":mode == "three_point_seed" ? 0:2]
            for terminal in ["candidate_ready","spot_verified",mode == "three_point_seed" ? "feedback_checked":"seed_ready"] {
                var invalid=PhysicalCalibrationProgressReader()
                invalid.accept(data(fields.merging(["state":terminal]){_,n in n}),now:1010)
                check(invalid.latest == nil,"Workflow cannot claim a different terminal meaning")
            }
            var incomplete=PhysicalCalibrationProgressReader()
            incomplete.accept(data(fields.merging(["state":mode == "three_point_seed" ? "seed_ready":"feedback_checked"]){_,n in n}),now:1010)
            check(incomplete.latest == nil,"Incomplete workflow cannot claim success")
        }
        var feedback=PhysicalCalibrationProgressReader()
        let feedbackFields:[String:Any]=["mode":"feedback_check","stage":"feedback","fitCompleted":0,"fitTotal":0,"validationCompleted":1,"validationTotal":2,"target":"P15"]
        feedback.accept(data(feedbackFields),now:1010)
        check(feedback.latest?.countSummary == "1 of 2 feedback targets reached in this run","Remaining-target run does not claim a seven-target uninterrupted pass")
        feedback.accept(data(feedbackFields.merging(["sequence":2,"validationTotal":7]){_,n in n}),now:1010)
        check(feedback.unavailable && feedback.latest?.total == 2,"A run cannot change its route totals")
        feedback.accept(data(feedbackFields.merging(["sequence":3,"validationCompleted":2,"state":"feedback_checked"]){_,n in n}),now:1010)
        check(feedback.latest?.completed == 2 && feedback.latest?.state == "feedback_checked","Feedback success counts only completed targets")
        check(!feedback.interrupted(now:2000),"Completed feedback timing stays dated history")
        var mutation=PhysicalCalibrationProgressReader()
        mutation.accept(data(),now:1010)
        mutation.accept(data(seedFields.merging(["sequence":2]){_,n in n}),now:1010)
        check(mutation.unavailable && mutation.latest?.mode == "full_calibration","A run cannot change workflow identity")
        var missing=PhysicalCalibrationProgressReader();missing.accept(nil,now:1010)
        check(missing.latest == nil,"Missing status leaves panel absent")
        check(PhysicalCalibrationProgressReader.read(URL(fileURLWithPath:"/not/a/progress/file")) == nil,"Missing file is harmless")
        print("PASS: \(checks) calibration progress parsing, lifetime and run-transition checks")
    }
}
