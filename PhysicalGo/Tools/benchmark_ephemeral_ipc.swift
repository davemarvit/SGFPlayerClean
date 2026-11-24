import Foundation

/// Compile with Sources/EphemeralAtomicFile.swift. Private same-filesystem
/// benchmark only; never points at LaserBridge or launches a hardware client.
@main struct BenchmarkEphemeralIPC {
    static func main()throws {
        guard (2...3).contains(CommandLine.arguments.count) else {fatalError("Pass a representative PNG file to read")}
        let pixels=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("PhysicalGoIPC-Benchmark-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let png=root.appendingPathComponent("frame.png"),manifest=root.appendingPathComponent("latest.json"),request=root.appendingPathComponent("request.json")
        let metadata=Data(("{\"frameID\":1,\"capturedAtUnix\":1000,\"imageFile\":\"frame.png\",\"padding\":\""+String(repeating:"x",count:1900)+"\"}").utf8)
        let command=Data(("{\"action\":\"off\",\"sentAtUnix\":1000,\"expiresAtUnix\":1000.6,\"padding\":\""+String(repeating:"x",count:900)+"\"}").utf8)
        let concurrent=CommandLine.arguments.contains("--readers")
        let stop=DispatchSemaphore(value:0),readerFinished=DispatchSemaphore(value:0)
        if concurrent {DispatchQueue.global(qos:.userInitiated).async {
            var count=0
            while stop.wait(timeout:.now()) != .success {
                autoreleasepool {
                    _=try? Data(contentsOf:manifest);_=try? Data(contentsOf:request)
                    if count%5==0 {_=try? Data(contentsOf:png)}
                }
                count+=1;Thread.sleep(forTimeInterval:0.02)
            }
            readerFinished.signal()
        }}
        defer {if concurrent {stop.signal();_=readerFinished.wait(timeout:.now()+3)}}
        var durations=["foundation_atomic":[Double](),"ephemeral_atomic":[Double]()]
        var pngTimes=durations,manifestTimes=durations,requestTimes=durations
        for iteration in 0..<64 {
            for name in iteration%2==0 ? ["foundation_atomic","ephemeral_atomic"]:["ephemeral_atomic","foundation_atomic"] {
                func put(_ data:Data,_ url:URL)throws {
                    if name=="foundation_atomic" {try data.write(to:url,options:.atomic)}
                    else {try EphemeralAtomicFile.write(data,to:url)}
                }
                let began=ProcessInfo.processInfo.systemUptime
                try put(pixels,png);let imageAt=ProcessInfo.processInfo.systemUptime
                try put(metadata,manifest);let metaAt=ProcessInfo.processInfo.systemUptime
                try put(command,request);let requestAt=ProcessInfo.processInfo.systemUptime
                if iteration>=4 {
                    durations[name]!.append((requestAt-began)*1000)
                    pngTimes[name]!.append((imageAt-began)*1000)
                    manifestTimes[name]!.append((metaAt-imageAt)*1000)
                    requestTimes[name]!.append((requestAt-metaAt)*1000)
                }
                let read_png=try Data(contentsOf:png);precondition(read_png==pixels)
                let read_manifest=try Data(contentsOf:manifest);precondition(read_manifest==metadata)
                let read_request=try Data(contentsOf:request);precondition(read_request==command)
            }
        }
        func stats(_ values:[Double])->[String:Any] {
            let sorted=values.sorted()
            return ["count":sorted.count,"medianMs":(sorted[sorted.count/2-1]+sorted[sorted.count/2])/2,
                    "p95Ms":sorted[Int(Double(sorted.count-1)*0.95)],"maxMs":sorted.last!]
        }
        let results=Dictionary(uniqueKeysWithValues:durations.keys.map {name in
            (name,["total":stats(durations[name]!),"png":stats(pngTimes[name]!),"manifest":stats(manifestTimes[name]!),"request":stats(requestTimes[name]!)])
        })
        let output:[String:Any]=["pngBytes":pixels.count,"concurrentReaders":concurrent,"alternatingOrder":true,"warmupPairs":4,"privateDirectory":root.path,"results":results]
        print(String(data:try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
