import Foundation

/// One prompt per interruption, with a cooldown across brief recover/reject flicker.
struct BoardRecoveryPrompt {
    private var announced=false
    private var lastSpoken:Double?
    private var began:Double?
    private(set) var likelyObstruction=false
    var delay:Double {likelyObstruction ? 8:5}
    func maySearch(now:Double)->Bool {began.map{now-$0>=delay} ?? false}
    mutating func update(recovering:Bool,needsHelp:Bool,enabled:Bool,now:Double,obstructed:Bool=false)->String? {
        guard recovering else {announced=false;began=nil;likelyObstruction=false;return nil}
        guard now.isFinite else {return nil}
        if began==nil {began=now}
        likelyObstruction = likelyObstruction || obstructed
        guard maySearch(now:now) else {return nil}
        guard enabled,needsHelp,!announced else {return nil}
        guard lastSpoken.map({now-$0>=30}) ?? true else {return nil}
        announced=true;lastSpoken=now
        return likelyObstruction
            ? "Part of the board is hidden. Move hands and other obstructions clear, and keep the camera in place."
            : "The camera grid no longer matches the board. Show all four corners and keep the camera steady while alignment is checked."
    }
}
