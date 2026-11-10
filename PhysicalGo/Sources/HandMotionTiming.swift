import Foundation

/// An estimate in camera/uptime coordinates. Model bounds are engineering error
/// estimates, not calibrated confidence intervals or guarantees about exposure.
struct ClockPressEstimate:Codable,Equatable {
    enum Method:String,Codable {case handMotion,handBracket,clearFrame,candidate}
    let time:Double
    let method:Method
    var observedLower:Double?=nil
    var observedUpper:Double?=nil
    var estimatedError:Double?=nil
    var samples=1
    var timestampSource="callback"
    var fallbackReason:String?=nil
    var valid:Bool {
        time.isFinite && (estimatedError.map{$0.isFinite && $0>=0} ?? true) &&
        (observedLower.map{$0.isFinite && $0<=time} ?? true) &&
        (observedUpper.map{$0.isFinite && $0>=time} ?? true)
    }
    var summary:String {
        switch method {
        case .handMotion:return String(format:"Hand motion · estimated ±%.2f s",estimatedError ?? 0)
        case .handBracket:return String(format:"Hand-clear interval %.2f s · used first clear frame",(observedUpper ?? time)-(observedLower ?? time))
        case .clearFrame:return "First verified clear frame · hand-exit uncertainty unavailable"
        case .candidate:return "Candidate observation · hand-exit uncertainty unavailable"
        }
    }
}

struct HandMotionPose:Codable {
    struct Point:Codable {let id:String;let x:Double,y:Double,confidence:Double}
    var hands:[[Point]]
    var reliable:Bool=true
    func obstructed(size:Int)->Bool? {
        guard reliable else {return nil}
        return hands.flatMap{$0}.contains{$0.confidence>=0.25 && (-0.75...Double(size)-0.25).contains($0.x) && (-0.75...Double(size)-0.25).contains($0.y)}
    }
}

/// Fits common joints, not a changing "most inward" joint or hand centroid.
/// Multiple hands, sparse/erratic tracks and unsupported extrapolation retain
/// the observed bracket. Estimates remain provisional until a legal board fits.
struct HandMotionTiming {
    private struct View {let time:Double;let points:[HandMotionPose.Point];let source:String}
    private var views=[View]()
    private var lastTime:Double?
    private var lastObstructed:Double?
    private var fallback="No stable hand trajectory"
    mutating func reset() {views=[];lastTime=nil;lastObstructed=nil;fallback="No stable hand trajectory"}
    mutating func observe(_ pose:HandMotionPose?,at time:Double,size:Int,source:String="callback")->ClockPressEstimate? {
        guard time.isFinite,lastTime.map({time>$0}) ?? true else {return nil}
        if let lastTime,time-lastTime>0.65 {reset()}
        lastTime=time
        guard let pose,let obstructed=pose.obstructed(size:size) else {reset();return nil}
        if obstructed {
            lastObstructed=time
            guard pose.hands.count==1 else {views=[];fallback="Multiple hands";return nil}
            let points=pose.hands[0].filter{$0.confidence>=0.5 && $0.x.isFinite && $0.y.isFinite}
            guard points.count>=8 else {views=[];fallback="Too few reliable joints";return nil}
            if views.last?.source != source {views=[]}
            views.append(.init(time:time,points:points,source:source));views=Array(views.suffix(3))
            return nil
        }
        guard let lower=lastObstructed else {return nil}
        defer {views=[];lastObstructed=nil}
        var estimate=ClockPressEstimate(time:time,method:.handBracket,observedLower:lower,observedUpper:time,samples:views.count,timestampSource:source,fallbackReason:fallback)
        guard views.count>=2,time-lower<=0.6,views.allSatisfy({$0.source==source}),let last=views.last else {return estimate}
        let common=last.points.filter{p in views.allSatisfy{v in v.points.contains{$0.id==p.id}}}
        guard common.count>=8,common.count>=last.points.count-2 else {estimate.fallbackReason="Joint identities changed";return estimate}
        let span=last.time-views[0].time
        guard span>=0.025,span<=1.0 else {return estimate}
        let meanT=views.map{$0.time-last.time}.reduce(0,+)/Double(views.count)
        let denominator=views.map{pow(($0.time-last.time)-meanT,2)}.reduce(0,+)
        var exits=[(time:Double,error:Double)]()
        for joint in common {
            let coordinates=views.map{v in v.points.first{$0.id==joint.id}!}
            func fit(_ values:[Double])->(Double,Double,Double) {
                let mean=values.reduce(0,+)/Double(values.count)
                let velocity=zip(views,values).map{($0.0.time-last.time-meanT)*($0.1-mean)}.reduce(0,+)/denominator
                let intercept=mean-velocity*meanT
                let residual=zip(views,values).map{abs($0.1-(intercept+velocity*($0.0.time-last.time)))}.max() ?? 0
                return (intercept,velocity,residual)
            }
            let x=fit(coordinates.map(\.x)),y=fit(coordinates.map(\.y))
            guard max(x.2,y.2)<0.35 else {estimate.fallbackReason="Nonlinear or noisy hand motion";return estimate}
            let low = -0.75,high=Double(size)-0.25
            guard (low...high).contains(joint.x),(low...high).contains(joint.y) else {continue}
            var crossings=[(Double,Double)]()
            for (axis,fitResult) in [x,y].enumerated() where abs(fitResult.1)>0.5 {
                let (position,velocity,residual)=fitResult
                let dt=((velocity>0 ? high:low)-position)/velocity
                if dt>=0 {
                    // Quarter-grid outline allowance covers joint/hand-boundary
                    // mismatch; acceleration grows uncertainty with look-ahead.
                    var acceleration=0.0
                    if views.count==3 {
                        let values=axis==0 ? coordinates.map(\.x):coordinates.map(\.y)
                        let a=(values[1]-values[0])/(views[1].time-views[0].time)
                        let b=(values[2]-values[1])/(views[2].time-views[1].time)
                        acceleration=abs(b-a)*2/span
                    }
                    let error=(0.25+residual+0.5*acceleration*dt*dt)/abs(velocity)
                    crossings.append((dt,error))
                }
            }
            guard let crossing=crossings.min(by:{$0.0<$1.0}) else {estimate.fallbackReason="Hand is not withdrawing consistently";return estimate}
            exits.append((last.time+crossing.0,crossing.1))
        }
        guard let crossing=exits.max(by:{$0.time<$1.time}),crossing.time>=lower,crossing.time<=time,
              crossing.time-last.time<=0.4 else {estimate.fallbackReason="Predicted crossing is outside the observed interval";return estimate}
        let error=max(0.02,exits.map(\.error).max() ?? 0)
        guard error<(time-lower)/2 else {estimate.fallbackReason="Motion fit does not improve the observed bracket";return estimate}
        estimate=ClockPressEstimate(time:crossing.time,method:.handMotion,observedLower:lower,observedUpper:time,estimatedError:error,samples:views.count,timestampSource:source)
        return estimate
    }
}
