import Foundation

/// Untimed practice still measures elapsed time. Only move receipt/acceptance
/// switches sides; optical aiming and physical mirroring never switch a clock.
/// The game pauses elapsed time for physical cleanup of captures of two or more stones.
struct PhysicalAITiming: Codable, Equatable {
    var blackSeconds = 0.0
    var whiteSeconds = 0.0
    var blackToPlay = true
    private(set) var anchor: Double?
    mutating func resume(at now: Double) {if anchor == nil {anchor=now}}
    mutating func pause(at now: Double) {charge(at:now);anchor=nil}
    mutating func move(black: Bool, at now: Double) {
        guard black == blackToPlay else {return}
        charge(at:now);blackToPlay.toggle();anchor=now
    }
    private mutating func charge(at now: Double) {
        guard let anchor,now.isFinite,now>=anchor else {return}
        if blackToPlay {blackSeconds+=now-anchor} else {whiteSeconds+=now-anchor}
        self.anchor=now
    }
    func elapsed(black: Bool, at now: Double)->Double {
        (black ? blackSeconds:whiteSeconds) + (black == blackToPlay ? anchor.map {max(0,now-$0)} ?? 0:0)
    }
    var saved: Self {var copy=self;copy.anchor=nil;return copy}
    func saved(at now: Double)->Self {var copy=self;copy.pause(at:now);return copy}
}
