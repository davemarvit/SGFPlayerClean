import Foundation
import Darwin
import IOKit.ps

/// Resource readings are injectable so power/thermal/load behavior can be tested without
/// stressing the user's Mac. All controller state belongs to the main thread.
struct AnalysisResources {
    var onBattery = false
    var lowPower = false
    var thermal: ProcessInfo.ThermalState = .nominal
    var cpuBusy = 0.0
    var memoryPressure = false

    func pauseReason(pauseOnBattery: Bool) -> String? {
        if lowPower { return "Paused for Low Power Mode" }
        if pauseOnBattery && onBattery { return "Paused to save battery" }
        if thermal != .nominal { return "Paused while your Mac cools down" }
        if memoryPressure || cpuBusy > 0.65 { return "Paused while your Mac is busy" }
        return nil
    }
}

final class AnalysisResourceMonitor {
    private var previousCPU: [UInt32]?
    private var pressured = false
    private let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
    init() {
        pressure.setEventHandler { [weak self] in
            guard let self else { return }
            self.pressured = !self.pressure.data.contains(.normal)
        }
        pressure.resume()
    }
    deinit { pressure.cancel() }
    func sample() -> AnalysisResources {
        var busy = 1.0 // Fail closed if the OS cannot provide a load reading.
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let previousCPU {
                let deltas = zip(ticks, previousCPU).map { Double($0 &- $1) }
                let total = deltas.reduce(0, +)
                busy = total > 0 ? 1 - deltas[Int(CPU_STATE_IDLE)] / total : 0
            }
            previousCPU = ticks
        }
        var battery = false
        if let sources = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(sources)?.takeUnretainedValue() {
            battery = (type as String) == kIOPSBatteryPowerValue
        }
        return AnalysisResources(onBattery: battery, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermal: ProcessInfo.processInfo.thermalState, cpuBusy: busy, memoryPressure: pressured)
    }
}

/// One bounded search at a time. Cover every position before spending spare time
/// deepening it. The cursor survives new moves, so the opening cannot starve the endgame.
final class BackgroundGameAnalysis {
    private let engine: KataGoEngine
    private var gameID: String?
    private var history: [String] = []
    private var context = ""
    private var attempted: [Int: Int] = [:]
    private var cursor = 0
    private var started: TimeInterval?
    private var readyAt: TimeInterval = 0
    private(set) var status = "Preparing review"
    private(set) var isActive = false

    init(engine: KataGoEngine) { self.engine = engine }

    func stop() {
        if isActive { engine.pauseAnalysis() }
        isActive = false
        started = nil
    }

    func tick(player: SGFPlayer, resources: AnalysisResources, pauseOnBattery: Bool,
              now: TimeInterval = ProcessInfo.processInfo.systemUptime, interfaceDelayed: Bool = false) {
        isActive = true
        let payload = player.getAIPayload(at: player.maxIndex)
        let moves = payload.moves.map { "\($0.color):\($0.x),\($0.y)" }
        let settings = player.analysisSettings
        let newContext = "\(player.board.size)|\(settings)|\(payload.initial)"
        if gameID != engine.currentGameId {
            gameID = engine.currentGameId; history = moves; context = newContext
            attempted.removeAll(); cursor = 0; started = nil; readyAt = now + 1
        } else if newContext != context {
            engine.pauseAnalysis(); engine.discardAnalysis(from: 0)
            context = newContext; history = moves; attempted.removeAll(); cursor = 0; started = nil
        } else if moves != history {
            let common = zip(moves, history).prefix { $0 == $1 }.count
            if common < history.count {
                engine.discardAnalysis(from: common + 1)
                attempted = attempted.filter { $0.key <= common }
            }
            history = moves
        }
        guard !moves.isEmpty else { status = "Waiting for moves"; return }
        if let reason = resources.pauseReason(pauseOnBattery: pauseOnBattery) ?? (interfaceDelayed ? "Paused while your Mac is busy" : nil) {
            // Terminate actual engine work, not just delivery of its results.
            if engine.hasPendingAnalysis { engine.pauseAnalysis() }
            started = nil; readyAt = now + 3; status = reason
            return
        }
        if !engine.isEngineRunning && engine.engineStartupError == nil { engine.start() }
        guard engine.isEngineRunning else { status = "AI engine unavailable"; return }
        if let began = started, !engine.hasPendingAnalysis {
            // At most 50% search duty on an idle Mac, 25% under moderate load.
            readyAt = now + max(0.5, (now - began) * (resources.cpuBusy > 0.35 ? 3 : 1))
            started = nil
        }
        guard !engine.hasPendingAnalysis, now >= readyAt else { return }
        let turns = Array(0...moves.count)
        let eligible = turns.filter { !engine.hasFailedAnalysis(at: $0) }
        guard !eligible.isEmpty else { status = "Analysis needs a retry"; return }
        // New positions get their first pass ahead of upgrades. Thereafter choose
        // the least-attempted search depth, rotating ties to avoid starvation.
        let turn = eligible.min {
            func rank(_ i: Int) -> (Int, Int) {
                let visits = engine.currentAnalysisData[i]?.rootInfo?.visits ?? 0
                return (max(visits, attempted[i] ?? 0), (i - cursor + turns.count) % turns.count)
            }
            return rank($0) < rank($1)
        }!
        let visits = engine.currentAnalysisData[turn]?.rootInfo?.visits ?? 0
        let previous = max(visits, attempted[turn] ?? 0)
        // Time, rather than a fixed 500-visit ceiling, bounds automatic work.
        let target = previous == 0 ? 50 : min(1_000_000, max(200, previous * 4))
        let seconds = min(12.0, max(0.5, Double(target) / 800))
        attempted[turn] = target; cursor = (turn + 1) % turns.count
        let position = player.getAIPayload(at: turn)
        engine.analyzeGame(id: engine.currentGameId, initialStones: position.initial,
            moves: position.moves, size: player.board.size, maxVisits: target,
            settings: settings, backgroundTimeLimit: seconds)
        if engine.hasPendingAnalysis { started = now }
        else { readyAt = now + 1 }
        let covered = turns.filter { engine.currentAnalysisData[$0] != nil }.count
        status = covered < turns.count ? "Preparing review · \(covered) of \(turns.count) positions" : "Deepening review"
    }
}
