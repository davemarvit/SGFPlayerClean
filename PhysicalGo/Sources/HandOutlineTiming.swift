import Foundation

/// Motion of the visible trailing edge, measured in grid spaces from the rim.
/// A negative depth means the entire tracked outline is outside the playing area.
struct HandOutlineTiming {
    struct View {let time:Double,depth:Double}
    private var views=[View]()
    private var lastInside:Double?
    mutating func reset() {views=[];lastInside=nil}
    mutating func observe(depth:Double?,at time:Double) {
        guard let depth,depth.isFinite else {return}
        if depth>0 {lastInside=time}
        views.append(.init(time:time,depth:depth));views=Array(views.suffix(4))
    }
    func estimate(firstClear:Double,source:String)->ClockPressEstimate? {
        guard let lower=lastInside,lower<firstClear else {return nil}
        let bracket=firstClear-lower
        var fallback=ClockPressEstimate(time:(lower+firstClear)/2,method:.handBracket,observedLower:lower,observedUpper:firstClear,
            estimatedError:bracket/2+0.02,samples:views.count,timestampSource:source,fallbackReason:"Visual exit interval midpoint; insufficient withdrawal motion")
        // Prefer a measured crossing with a visible point on either side.
        let usable=Array(views.filter{$0.time<=firstClear}.suffix(3))
        guard usable.count>=2,let last=usable.last else {return fallback}
        let earlier=usable[usable.count-2],dt=last.time-earlier.time
        guard dt>=0.015,dt<=0.5 else {return fallback}
        let speed=(earlier.depth-last.depth)/dt
        guard speed>0.5 else {return fallback}
        let crossing=last.time+last.depth/speed
        guard crossing>=lower,crossing<=firstClear,crossing-last.time<=0.25 else {return fallback}
        // Position/outline uncertainty, observed acceleration, and a sampling
        // floor are retained. These are engineering estimates, not confidence.
        var error=0.25/speed
        if usable.count==3 {
            let a=usable[0],b=usable[1],prior=(a.depth-b.depth)/(b.time-a.time)
            guard prior>=0 else {fallback.fallbackReason="Hand changed direction";return fallback}
            let acceleration=abs(speed-prior)/max(0.015,(last.time-a.time)/2)
            let horizon=max(dt,abs(crossing-last.time))
            error += 0.5*acceleration*horizon*horizon/speed
        } else {
            // Two positions cannot measure acceleration.
            error += dt/4
        }
        // Image blur and color-edge thresholding add a timing allowance beyond
        // the fitted positional residual. Do not present a regression residual
        // alone as physical hand-clear accuracy.
        error=max(0.04,error+0.02)
        guard error<0.2,error<bracket+0.04 else {fallback.fallbackReason="Withdrawal acceleration makes the motion estimate too uncertain";return fallback}
        return ClockPressEstimate(time:crossing,method:.handMotion,observedLower:lower,observedUpper:firstClear,
            estimatedError:error,samples:usable.count,timestampSource:source)
    }
}
