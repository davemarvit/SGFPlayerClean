import Foundation

/// Fits a smooth exposure field to exposed wood, never to expected stone labels.
/// The original photo and empty reference are immutable; only comparison pixels change.
enum LightingCompensation {
    struct Sample {let point:ImagePoint;let current:Double;let reference:Double}
    struct Field:Codable {
        let constant:Double, x:Double, y:Double
        let residual:Double
        func gain(at point:ImagePoint)->Double {constant+x*point.x+y*point.y}
    }
    private static func percentile(_ values:[Double],_ fraction:Double)->Double {
        let sorted=values.sorted()
        return sorted.isEmpty ? 0:sorted[min(sorted.count-1,Int(Double(sorted.count-1)*fraction))]
    }
    static func fit(_ samples:[Sample],calibration:BoardCalibration)->Field? {
        let usable=samples.filter {$0.current>0.08 && $0.current<0.94 && $0.reference>0.08 && $0.reference<0.94}
        guard usable.count>=max(24,samples.count*3/4) else {return nil}
        func solve(_ points:[Sample])->Field? {
            var matrix=Array(repeating:Array(repeating:0.0,count:4),count:3)
            for p in points {
                let a=[1.0,p.point.x,p.point.y],gain=p.reference/p.current
                for r in 0..<3 {for c in 0..<3 {matrix[r][c] += a[r]*a[c]};matrix[r][3] += a[r]*gain}
            }
            for c in 0..<3 {
                let pivot=(c..<3).max {abs(matrix[$0][c])<abs(matrix[$1][c])}!
                guard abs(matrix[pivot][c])>1e-8 else {return nil}
                matrix.swapAt(pivot,c)
                let scale=matrix[c][c]
                for j in c...3 {matrix[c][j] /= scale}
                for r in 0..<3 where r != c {
                    let factor=matrix[r][c]
                    for j in c...3 {matrix[r][j] -= factor*matrix[c][j]}
                }
            }
            return Field(constant:matrix[0][3],x:matrix[1][3],y:matrix[2][3],residual:0)
        }
        guard var field=solve(usable) else {return nil}
        for _ in 0..<3 {
            let residuals=usable.map {abs(field.gain(at:$0.point)*$0.current-$0.reference)}
            let cutoff=max(0.018,2.5*percentile(residuals,0.5))
            let inliers=zip(usable,residuals).filter {$0.1<=cutoff}.map {$0.0}
            guard inliers.count>=usable.count*3/4,let refined=solve(inliers) else {return nil}
            field=refined
        }
        let residual=percentile(usable.map {abs(field.gain(at:$0.point)*$0.current-$0.reference)},0.8)
        guard residual<0.035,calibration.corners.allSatisfy({(0.45...2.8).contains(field.gain(at:$0))}) else {return nil}
        // Require agreement throughout the board, not just its well-lit half.
        var good=[Int](repeating:0,count:4),total=good
        for s in usable {
            guard let p=calibration.gridPoint(for:s.point) else {continue}
            let q=(p.x<Double(calibration.size-1)/2 ? 0:1)+(p.y<Double(calibration.size-1)/2 ? 0:2)
            total[q] += 1
            if abs(field.gain(at:s.point)*s.current-s.reference)<0.04 {good[q] += 1}
        }
        guard total.indices.allSatisfy({total[$0]>=4 && good[$0]*4>=total[$0]*3}) else {return nil}
        return Field(constant:field.constant,x:field.x,y:field.y,residual:residual)
    }
    /// Gross darkness/clipping cannot be repaired by increasing contrast. Also
    /// catches lights-out before the geometry tracker calls it a camera nudge.
    static func exposureFailure(frame:GrayFrame,calibration:BoardCalibration)->Bool {
        var values=[Double]()
        for r in 0..<(calibration.size-1) {for c in 0..<(calibration.size-1) {
            if let value=frame.patchMean(calibration.point(col:Double(c)+0.5,row:Double(r)+0.5)) {values.append(value)}
        }}
        guard values.count>=24 else {return false}
        return values.filter {$0<0.08}.count*5>values.count*4 || values.filter {$0>0.97}.count*5>values.count*4
    }
}

/// Hysteresis around an unreadable frame. Only fresh camera frames can finish
/// recovery; UI redraws and repeated photos cannot shorten the waiting period.
struct LightingRecovery {
    private(set) var active=false
    private(set) var needsHelp=false
    private var began:Double?
    private var clearSince:Double?
    private var clearFrames=0
    private var lastFrame:Double?
    private var spoken=false
    private var lastSpoken:Double?
    mutating func update(blocked:Bool,fresh:Bool,now:Double,speech:Bool)->String? {
        if blocked {active=true}
        guard fresh,lastFrame.map({now>$0}) ?? true else {return nil}
        if let lastFrame,now-lastFrame>1 {clearSince=nil;clearFrames=0}
        lastFrame=now
        if blocked {
            if began==nil {began=now}
            clearSince=nil;clearFrames=0
        } else if active {
            if clearSince==nil {clearSince=now}
            clearFrames += 1
            if clearFrames>=3,now-clearSince!>=0.6 {active=false;needsHelp=false;began=nil;spoken=false}
        }
        if active,let began,now-began>=3 {needsHelp=true}
        guard active,needsHelp,speech,!spoken,lastSpoken.map({now-$0>=30}) ?? true else {return nil}
        spoken=true;lastSpoken=now
        return "Please pause play. Improve the lighting on the whole board and reduce glare. Keep the stones in place while I check the view."
    }
}
