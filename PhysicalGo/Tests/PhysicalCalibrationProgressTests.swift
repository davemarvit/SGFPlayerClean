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
        var missing=PhysicalCalibrationProgressReader();missing.accept(nil,now:1010)
        check(missing.latest == nil,"Missing status leaves panel absent")
        check(PhysicalCalibrationProgressReader.read(URL(fileURLWithPath:"/not/a/progress/file")) == nil,"Missing file is harmless")
        print("PASS: \(checks) calibration progress parsing, lifetime and run-transition checks")
    }
}
