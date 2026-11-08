import Foundation

/// Display-only quarter turns. Camera pixels, reference images and SGF coordinates
/// stay canonical; both previews and their hit-testing use this same transform.
struct BoardOrientation {
    let turns: Int
    init(_ turns: Int) { self.turns = ((turns % 4)+4)%4 }
    var swapsDimensions: Bool { turns%2 == 1 }
    func display(_ point:ImagePoint)->ImagePoint {
        switch turns {
        case 1: return .init(x:1-point.y,y:point.x)
        case 2: return .init(x:1-point.x,y:1-point.y)
        case 3: return .init(x:point.y,y:1-point.x)
        default: return point
        }
    }
    func source(_ point:ImagePoint)->ImagePoint { BoardOrientation(4-turns).display(point) }
    func canonicalCorners(_ displayedOrder:[ImagePoint])->[ImagePoint] {
        guard displayedOrder.count == 4 else { return displayedOrder }
        return Array(displayedOrder[turns...])+Array(displayedOrder[..<turns])
    }
    func displayedCorners(_ canonical:[ImagePoint])->[ImagePoint] {
        BoardOrientation(4-turns).canonicalCorners(canonical)
    }
}

/// Choose a player-facing rectangle (long grid axis vertical). Image evidence can
/// resolve the axis, but a symmetric empty board cannot resolve the player's end.
enum BoardViewOrientationPolicy {
    static func preferredTurns(current:Int,longAxisRows:Bool)->Int {
        let turns=BoardOrientation(current).turns
        let longIsVertical = longAxisRows != BoardOrientation(turns).swapsDimensions
        return longIsVertical ? turns : (turns+1)%4
    }
    static func canAdjust(automatic:Bool,online:Bool,recording:Bool)->Bool {
        automatic && !online && !recording
    }
}
