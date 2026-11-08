import Foundation

/// Pure, deterministic clock arithmetic. No camera, UI, audio or wall-clock dependency.
struct LocalClockSettings:Codable,Equatable {
    enum Kind:String,Codable,CaseIterable {
        case none,byoyomi,fischer,canadian,simple,absolute
        var label:String {
            switch self {case .none:return "No clock";case .byoyomi:return "Japanese byoyomi";case .fischer:return "Fischer";case .canadian:return "Canadian overtime";case .simple:return "Time per move";case .absolute:return "Absolute time"}
        }
    }
    var kind:Kind = .byoyomi
    var mainSeconds=600
    var periodSeconds=30
    var periods=5
    var incrementSeconds=30
    var maximumSeconds=1200
    var stonesPerPeriod=25
    var validationError:String? {
        guard kind != .none else {return nil}
        guard (0...604800).contains(mainSeconds),(1...86400).contains(periodSeconds),
              (1...100).contains(periods),(0...86400).contains(incrementSeconds),
              (1...604800).contains(maximumSeconds),(1...100).contains(stonesPerPeriod) else {return "Check clock values: durations must be nonnegative and overtime must be positive."}
        if [.absolute,.fischer].contains(kind) && mainSeconds==0 {return "Initial time must be greater than zero."}
        if kind == .fischer && maximumSeconds<mainSeconds {return "Maximum time must be at least the initial time."}
        return nil
    }
    var summary:String {
        switch kind {
        case .none:return "Untimed game"
        case .byoyomi:return "\(LocalClockEngine.display(Double(mainSeconds))) main + \(periods) × \(periodSeconds)s byoyomi"
        case .fischer:return "\(LocalClockEngine.display(Double(mainSeconds))) initial + \(incrementSeconds)s per move · cap \(LocalClockEngine.display(Double(maximumSeconds)))"
        case .canadian:return "\(LocalClockEngine.display(Double(mainSeconds))) main + \(stonesPerPeriod) moves per \(LocalClockEngine.display(Double(periodSeconds)))"
        case .simple:return "\(periodSeconds)s for every move"
        case .absolute:return "\(LocalClockEngine.display(Double(mainSeconds))) per player · no overtime"
        }
    }
    var sgfProperties:[String:[String]] {
        guard kind != .none else {return [:]}
        var result=["TM":[String(kind == .simple ? periodSeconds:mainSeconds)]]
        switch kind {
        case .byoyomi:result["OT"]=["\(periods)x\(periodSeconds) byo-yomi"]
        case .canadian:result["OT"]=["\(stonesPerPeriod)/\(periodSeconds) Canadian"]
        case .fischer:result["OT"]=["Fischer +\(incrementSeconds)s, maximum \(maximumSeconds)s"]
        case .simple:result["OT"]=["\(periodSeconds)s per move"]
        default:break
        }
        return result
    }
}

struct LocalClockEngine:Codable,Equatable {
    struct Side:Codable,Equatable {
        var remaining:Double
        var overtime:Bool
        /// Includes the period currently being used.
        var periods:Int
        var stones:Int
    }
    var settings:LocalClockSettings
    var black:Side
    var white:Side
    var blackToPlay:Bool
    private(set) var anchor:Double?
    private(set) var expiredBlack:Bool?
    var enabled:Bool {settings.kind != .none}
    var running:Bool {anchor != nil && expiredBlack == nil && enabled}
    init(settings:LocalClockSettings = .init(kind:.none),blackToPlay:Bool=true) {
        self.settings=settings;self.blackToPlay=blackToPlay
        let overtime=[LocalClockSettings.Kind.byoyomi,.canadian].contains(settings.kind) && settings.mainSeconds==0
        let seconds=settings.kind == .simple || overtime ? settings.periodSeconds:settings.mainSeconds
        let side=Side(remaining:Double(seconds),overtime:overtime,periods:settings.periods,stones:settings.stonesPerPeriod)
        black=side;white=side
    }
    mutating func resume(at now:Double) {if enabled,expiredBlack == nil,anchor == nil,now.isFinite {anchor=now}}
    mutating func pause(at now:Double) {advance(to:now);anchor=nil}
    mutating func advance(to now:Double) {
        guard let start=anchor,now.isFinite,now>=start,running else {return}
        var elapsed=now-start
        anchor=now
        var side=blackToPlay ? black:white
        if [.byoyomi,.canadian].contains(settings.kind),!side.overtime,elapsed+1e-9>=side.remaining {
            elapsed=max(0,elapsed-side.remaining);side.remaining=Double(settings.periodSeconds);side.overtime=true
        }
        if side.overtime && settings.kind == .byoyomi {
            // At most 100 periods; no dependence on callback frequency.
            while elapsed+1e-9>=side.remaining && side.periods>1 {
                elapsed=max(0,elapsed-side.remaining);side.periods -= 1;side.remaining=Double(settings.periodSeconds)
            }
        }
        side.remaining=max(0,side.remaining-elapsed)
        if side.remaining<1e-9 {side.remaining=0}
        if side.remaining<=0 {expiredBlack=blackToPlay;anchor=nil}
        if blackToPlay {black=side} else {white=side}
    }
    @discardableResult mutating func move(black color:Bool,at now:Double)->Bool {
        guard color==blackToPlay,expiredBlack == nil,enabled else {return false}
        advance(to:now)
        guard expiredBlack == nil else {return false}
        var side=color ? black:white
        switch settings.kind {
        case .fischer:side.remaining=min(Double(settings.maximumSeconds),side.remaining+Double(settings.incrementSeconds))
        case .simple:side.remaining=Double(settings.periodSeconds)
        case .byoyomi:if side.overtime {side.remaining=Double(settings.periodSeconds)}
        case .canadian:
            if side.overtime {side.stones -= 1;if side.stones==0 {side.stones=settings.stonesPerPeriod;side.remaining=Double(settings.periodSeconds)}}
        default:break
        }
        if color {black=side} else {white=side}
        blackToPlay.toggle()
        return true
    }
    mutating func restoredPaused() {anchor=nil}
    mutating func correct(black:Side,white:Side,blackToPlay:Bool) {
        self.black=black;self.white=white;self.blackToPlay=blackToPlay;anchor=nil;expiredBlack=nil
    }
    static func display(_ seconds:Double)->String {
        guard seconds.isFinite else {return "—"}
        let value=Int(ceil(max(0,min(seconds,604800))))
        if value>=3600 {return String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60)}
        return String(format:"%d:%02d",value/60,value%60)
    }
}
