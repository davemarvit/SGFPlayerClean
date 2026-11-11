import Foundation

/// Diagnostic collection is opt-in and independent of panel visibility.
struct DiagnosticSettings:Codable,Equatable {
    static let key="PhysicalGo.diagnosticSettings"
    var enabled=false
    var unusualMoves=true
    var byoyomiLosses=true
    var beforeSeconds=4
    var afterSeconds=5
    var framesPerSecond=5
    var valid:Bool {[2,4,6].contains(beforeSeconds) && [3,5,8].contains(afterSeconds) && [2,5,10].contains(framesPerSecond)}
    static func load(_ defaults:UserDefaults)->Self {
        if let data=defaults.data(forKey:key),let value=try? JSONDecoder().decode(Self.self,from:data),value.valid {return value}
        var value=Self()
        // Preserve an explicitly enabled legacy camera-collection choice.
        value.enabled=defaults.object(forKey:"PhysicalGo.captureUnusualMoves") != nil && defaults.bool(forKey:"PhysicalGo.captureUnusualMoves")
        return value
    }
}

/// Actual clock transitions, independent of speech, camera recognition and settings UI.
struct ByoyomiPeriodChange:Codable {
    let black:Bool
    let before:Int
    let after:Int
    let observedAt:Double
    let boundary:Double?
    let cause:String
    let previous:LocalClockEngine
    let current:LocalClockEngine
    let press:ClockPressEstimate?
    var lost:Bool {after<before}
    static func changes(from previous:LocalClockEngine,to current:LocalClockEngine,at now:Double,cause:String,press:ClockPressEstimate?)->[Self] {
        guard previous.settings.kind == .byoyomi,current.settings==previous.settings,now.isFinite else {return []}
        return [true,false].compactMap {black in
            let old=black ? previous.black:previous.white,new=black ? current.black:current.white
            let before=previous.expiredBlack==black ? 0:old.periods,after=current.expiredBlack==black ? 0:new.periods
            guard before != after else {return nil}
            let boundary:Double?
            if after<before,previous.blackToPlay==black,let anchor=previous.anchor {
                boundary=anchor+old.remaining+(old.overtime ? 0:Double(previous.settings.periodSeconds))
            } else {boundary=nil}
            return Self(black:black,before:before,after:after,observedAt:now,boundary:boundary,cause:cause,previous:previous,current:current,press:press)
        }
    }
}
