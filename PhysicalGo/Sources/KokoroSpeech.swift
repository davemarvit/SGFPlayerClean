import Foundation

enum KokoroResourceBundle {
    static var bundle:Bundle {
        let url=Bundle.main.url(forResource:"KokoroResources",withExtension:"bundle")
            ?? Bundle.main.bundleURL.appendingPathComponent("KokoroResources.bundle")
        return Bundle(url:url) ?? Bundle.main
    }
    static var modelDirectory:URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Kokoro")
    }
}

/// Shared offline synthesis. The serial worker never runs on the camera or clock
/// thread. Common calls have bundled audio; uncommon calls are cached in memory.
final class KokoroSpeech: @unchecked Sendable {
    static let shared=KokoroSpeech()
    static let voiceID="kokoro:af_heart"
    static let systemVoiceID="system"
    static func selected(_ id:String)->Bool {id.isEmpty || id==voiceID}
    private let queue=DispatchQueue(label:"PhysicalGo.speech",qos:.utility)
    private let cache=NSCache<NSString,NSData>()
    private let directory:URL
    private let manifest:[String:String]
    private var engine:KokoroEngine?
    private var release:DispatchWorkItem?
    init(directory:URL=KokoroResourceBundle.modelDirectory) {
        self.directory=directory
        let data=try? Data(contentsOf:directory.appendingPathComponent("audio/manifest.json"))
        manifest=data.flatMap{try? JSONDecoder().decode([String:String].self,from:$0)} ?? [:]
        cache.totalCostLimit=32*1024*1024;cache.countLimit=160
    }
    var available:Bool {KokoroEngine.isDownloaded(at:directory)}
    func cached(_ text:String)->Data? {
        if let data=cache.object(forKey:text as NSString) {return data as Data}
        guard let file=manifest[text],let data=try? Data(contentsOf:directory.appendingPathComponent("audio/"+file)) else {return nil}
        cache.setObject(data as NSData,forKey:text as NSString,cost:data.count)
        return data
    }
    func synthesize(_ text:String,completion:@escaping @Sendable (Data?)->Void) {
        if let data=cached(text) {completion(data);return}
        queue.async { [self] in
            release?.cancel()
            do {
                if engine==nil {engine=try KokoroEngine(modelDirectory:directory)}
                let result=try engine!.synthesize(text:text,voice:"af_heart",speed:1.12)
                let data=try Self.wav(result.samples)
                cache.setObject(data as NSData,forKey:text as NSString,cost:data.count)
                completion(data)
            } catch {completion(nil)}
            let unload=DispatchWorkItem{[weak self] in self?.engine=nil}
            release=unload;queue.asyncAfter(deadline:.now()+60,execute:unload)
        }
    }
    static func wav(_ samples:[Float]) throws ->Data {
        guard !samples.isEmpty,samples.allSatisfy(\.isFinite) else {throw CocoaError(.fileReadCorruptFile)}
        var data=Data()
        func u16(_ value:UInt16) {data.append(UInt8(value&255));data.append(UInt8(value>>8))}
        func u32(_ value:UInt32) {for shift in stride(from:0,to:32,by:8) {data.append(UInt8((value>>shift)&255))}}
        data.append(contentsOf:"RIFF".utf8);u32(UInt32(36+samples.count*2))
        data.append(contentsOf:"WAVEfmt ".utf8);u32(16);u16(1);u16(1);u32(24000);u32(48000);u16(2);u16(16)
        data.append(contentsOf:"data".utf8);u32(UInt32(samples.count*2))
        for sample in samples {u16(UInt16(bitPattern:Int16(max(-1,min(1,sample))*32767)))}
        return data
    }
}

/// Every request, stop, move or timeout invalidates older asynchronous speech.
struct SpeechRequestGate {
    private(set) var generation=0
    mutating func advance()->Int {generation &+= 1;return generation}
    func accepts(_ token:Int)->Bool {token==generation}
}
