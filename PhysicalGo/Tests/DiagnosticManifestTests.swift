import Foundation

@main struct DiagnosticManifestTests {
    static func main()throws {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        func object(_ data:Data)throws->NSDictionary {try JSONSerialization.jsonObject(with:data) as! NSDictionary}
        let checkpoint:[String:Any]=["background":["pixels":[["x":1.2,"y":2.3,"valid":true]],"whiteStones":[]],
            "temporal":["references":[["source":"camera \"one\"\n雪","pixels":[1,2,3]]],"clearTimes":[1.1,1.2]]]
        for context:[String:Any] in [[:],["handOutlineCheckpoint":checkpoint,"schemaVersion":1,"initialSGF":"(;SZ[19])"],
            ["reason":NSNull(),"status":"old","framesSaved":99,"bytesWritten":88,"omittedImages":77,"updatedAt":1],
            ["reason":"initial reason","escaped/key":"line\nquote\" slash/ snow雪"]] {
            let cached=try DiagnosticManifest(context:context)
            for (status,reason) in [("recording",nil as String?),("complete","done"),("failed","disk failure")] {
                var expected=context
                expected["status"]=status;expected["reason"]=reason ?? expected["reason"]
                expected["framesSaved"]=25;expected["bytesWritten"]=Int64(9_000_000_001)
                expected["omittedImages"]=100;expected["updatedAt"]=123.25
                let data=try cached.data(status:status,frames:25,bytes:9_000_000_001,omittedImages:100,updatedAt:123.25,reason:reason)
                check(try object(data)==object(JSONSerialization.data(withJSONObject:expected,options:[.prettyPrinted,.sortedKeys])),"Old schema/context overlay changed")
                check(data.first==123 && data.last==125,"Invalid JSON concatenation")
            }
        }
        let mutable=NSMutableDictionary(dictionary:["value":"before"])
        let frozen=try DiagnosticManifest(context:["checkpoint":mutable])
        mutable["value"]="after"
        let frozenObject=try object(frozen.data(status:"complete",frames:0,bytes:0,omittedImages:0,updatedAt:1,reason:nil))
        check((frozenObject["checkpoint"] as? NSDictionary)?["value"] as? String == "before","Cached checkpoint changed after encoding")
        print("PASS \(checks) diagnostic manifest compatibility checks")
        // Optional finite, read-only retained-data CPU benchmark. No image IO,
        // recording replay, camera/app startup, or production archive mutation.
        if CommandLine.arguments.count==2 {
            let file=URL(fileURLWithPath:CommandLine.arguments[1])
            let source=try Data(contentsOf:file)
            let context=try JSONSerialization.jsonObject(with:source) as! [String:Any]
            let began=ProcessInfo.processInfo.systemUptime
            let cached=try DiagnosticManifest(context:context)
            let prepare=ProcessInfo.processInfo.systemUptime-began
            var baseline=[Double](),replacement=[Double](),baselineBytes=0,replacementBytes=0
            for index in 0..<3 {
                try autoreleasepool {
                    var entry=context;entry["framesSaved"]=index;entry["updatedAt"]=123.25
                    entry["status"]="recording";entry["bytesWritten"]=Int64(100);entry["omittedImages"]=5
                    let start=ProcessInfo.processInfo.systemUptime
                    let old=try JSONSerialization.data(withJSONObject:entry,options:[.prettyPrinted,.sortedKeys])
                    baseline.append(ProcessInfo.processInfo.systemUptime-start);baselineBytes=old.count
                    let next=ProcessInfo.processInfo.systemUptime
                    let new=try cached.data(status:"recording",frames:index,bytes:100,omittedImages:5,updatedAt:123.25,reason:nil)
                    replacement.append(ProcessInfo.processInfo.systemUptime-next);replacementBytes=new.count
                    check(try object(old)==object(new),"Retained checkpoint/context differs")
                }
            }
            let result:[String:Any]=["source":file.path,"sourceBytes":source.count,"cachedBytes":cached.cachedBytes,
                "prepareSeconds":prepare,"baselineSerializationSeconds":baseline,"cachedAssemblySeconds":replacement,
                "baselineBytes":baselineBytes,"replacementBytes":replacementBytes,
                "semanticComparisons":3,"noDiskWriteBenchmark":true,"liveSpeedClaim":false]
            print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
        }
    }
}
