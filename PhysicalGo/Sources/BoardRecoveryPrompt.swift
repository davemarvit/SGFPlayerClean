import Foundation

/// One prompt per interruption, with a cooldown across brief recover/reject flicker.
struct BoardRecoveryPrompt {
    private var announced=false
    private var lastSpoken:Double?
    mutating func update(recovering:Bool,needsHelp:Bool,enabled:Bool,now:Double)->String? {
        guard recovering else {announced=false;return nil}
        guard enabled,needsHelp,!announced else {return nil}
        guard lastSpoken.map({now-$0>=30}) ?? true else {return nil}
        announced=true;lastSpoken=now
        return "Please pause play. Adjust the camera or board so the whole board is visible, then hold it steady."
    }
}
