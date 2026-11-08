import Foundation
import Combine
import CryptoKit

/// An in-process CPU engine. Requests run serially off the UI thread, retain
/// complete move history for ko, and are cancelled when the app leaves the foreground.
@MainActor final class TabletAnalysis: ObservableObject {
    @Published private(set) var running=false
    @Published private(set) var result: AIAnalysis?
    @Published private(set) var message: String?
    @Published private(set) var sweeping = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    private var sweepID = UUID()
    private var sweepTask: Task<Void, Never>?
    private var cache: [String: AIAnalysis] = [:]
    private var cacheURL: URL { URL.applicationSupportDirectory.appendingPathComponent("TabletAnalysis-v1.json") }
    init() {
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([String: AIAnalysis].self, from: data) { cache = saved }
    }
    func key(_ player: SGFPlayer) -> String {
        // Include complete history, setup, rules and model/search identity.
        let payload = player.getCurrentAIPayload()
        let history = (payload.initial + payload.moves).map { "\($0.color):\($0.x),\($0.y)" }.joined(separator: ";")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let identity = "b18-v1-16|\(player.board.size)|\(String(data: (try? encoder.encode(player.analysisSettings)) ?? Data(), encoding: .utf8) ?? "")|\(player.turn)|\(payload.initial.count)|\(history)"
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func evaluations(_ tree: ReviewTree) -> [(id: Int, score: Double, winrate: Double)] {
        tree.activePath.compactMap { id in
            var branch = tree; branch.select(id)
            guard let playback = try? branch.playbackGame() else { return nil }
            let probe = SGFPlayer(); probe.load(game: playback); probe.seek(to: branch.nodes[id].moveNumber)
            guard let root = cache[key(probe)]?.rootInfo else { return nil }
            return (id, root.scoreLead, root.winrate)
        }
    }
    func restore(_ player: SGFPlayer) { result = cache[key(player)] }
    func analyzeGame(_ game: TabletGame) {
        cancel()
        guard game.canAnalyze else { return }
        let tree = game.tree
        let ids = tree.activePath
        let sweep = UUID(); sweepID = sweep
        total = ids.count; completed = 0; sweeping = true
        sweepTask = Task { [weak self, weak game] in
            guard let self, let game else { return }
            defer { if self.sweepID == sweep { self.sweeping = false; if game.canAnalyze { self.restore(game.player) } } }
            for id in ids {
                guard !Task.isCancelled, game.canAnalyze else { return }
                while self.running {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if Task.isCancelled { return }
                }
                var branch = tree; branch.select(id)
                guard let playback = try? branch.playbackGame() else { continue }
                let probe = SGFPlayer(); probe.load(game: playback); probe.seek(to: branch.nodes[id].moveNumber)
                self.analyze(probe, publishResult: false)
                while self.running {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if Task.isCancelled { return }
                }
                if self.cache[self.key(probe)] != nil { self.completed += 1 }
            }
        }
    }
    private var generation=UUID()
    private let queue=DispatchQueue(label:"QuietGo.KataGo",qos:.userInitiated)
    func cancel() {
        sweepID = UUID()
        sweepTask?.cancel(); sweepTask=nil; sweeping=false
        generation=UUID(); if running { QKGCancel() }; result=nil
        if running { message="Stopping analysis…" }
    }
    func suspend() {
        cancel()
        queue.async { QKGUnload() }
    }
    func analyze(_ player:SGFPlayer, publishResult: Bool = true, visits: Int = 16) {
        guard AppSettings.shared.analysisEnabled, !running else {return}
        let cacheKey = key(player)
        if let saved = cache[cacheKey], (saved.rootInfo?.visits ?? 0) >= visits { if publishResult { result = saved }; message = nil; return }
        if publishResult { result=nil }; message=nil
        guard player.board.size <= 19 else {message="On-device analysis supports boards up to 19 × 19.";return}
        let settings=player.analysisSettings
        guard settings.analysisRulesSupported, let rules=settings.kataRules, let komi=settings.komi, komi.isFinite else {message="Choose supported rules and komi before analysis.";return}
        guard settings.whiteHandicapBonus == nil, settings.ruleOverrides == nil else {message="This game's custom rules need the desktop analysis engine.";return}
        guard let path=Bundle.main.path(forResource:"kata1-b18.bin",ofType:"gz") else {message="The analysis model is missing.";return}
        let payload=player.getCurrentAIPayload()
        func encode(_ moves:[(color:String,x:Int,y:Int)]) -> [[String:Any]] {moves.map{["color":$0.color,"x":$0.x,"y":$0.y]}}
        let input:[String:Any] = ["boardSize":player.board.size,"rules":rules,"komi":komi,
            "initial":encode(payload.initial),"moves":encode(payload.moves),
            "initialPlayer":player.playerToMove(at:0) == .black ? "B" : "W",
            "nextPlayer":player.turn == .black ? "B" : "W","visits":min(128, max(16, visits))]
        guard let data=try? JSONSerialization.data(withJSONObject:input), let request=String(data:data,encoding:.utf8) else {return}
        let token=UUID();generation=token;running=true;QKGPrepare()
        let turn=player.currentIndex
        queue.async { [weak self] in
            let pointer=QKGAnalyze(path,request)
            let output=pointer.map{String(cString:$0)} ?? "{\"error\":\"No engine response\"}"
            QKGFree(pointer)
            DispatchQueue.main.async {
                guard let self else{return}
                self.running=false
                guard self.generation == token else {self.message=nil;return}
                do {
                    let data=Data(output.utf8)
                    var json=(try JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
                    if let error=json["error"] as? String {self.message=error;return}
                    json["id"]=token.uuidString;json["turnNumber"]=turn
                    let decoded = try JSONDecoder().decode(AIAnalysis.self,from:JSONSerialization.data(withJSONObject:json))
                    if publishResult { self.result = decoded }
                    self.cache[cacheKey] = decoded
                    if let data = try? JSONEncoder().encode(self.cache) {
                        try? FileManager.default.createDirectory(at: self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? data.write(to: self.cacheURL, options: .atomic)
                    }
                } catch {self.message="Could not read analysis: \(error.localizedDescription)"}
            }
        }
    }
}
