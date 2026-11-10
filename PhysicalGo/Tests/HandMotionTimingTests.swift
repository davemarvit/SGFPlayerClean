import Foundation
@main struct HandMotionTimingTests {
    static func main() {
        var checks=0
        func check(_ value:Bool,_ message:String) {checks+=1;precondition(value,message)}
        func hand(_ x:Double,_ y:Double=4)->HandMotionPose {.init(hands:[(0..<12).map{.init(id:"p\($0)",x:x+Double($0)*0.02,y:y,confidence:0.95)}])}
        let clear=HandMotionPose(hands:[])
        var timing=HandMotionTiming()
        for (t,x) in [(0.0,5.75),(0.1,6.75),(0.2,7.75)] {check(timing.observe(hand(x),at:t,size:9)==nil,"Obstructed view emitted a press")}
        let fitted=timing.observe(clear,at:0.4,size:9)!
        check(fitted.method == .handMotion && abs(fitted.time-0.3)<1e-8,"Linear withdrawal did not recover sub-frame crossing")
        check(fitted.observedLower==0.2 && fitted.observedUpper==0.4 && fitted.estimatedError!<0.1 && fitted.samples==3,"Fit omitted its observed bracket or model error")
        check(timing.observe(clear,at:0.5,size:9)==nil,"One withdrawal emitted multiple presses")
        timing.reset();_=timing.observe(hand(6.75),at:1,size:9);_=timing.observe(hand(7.75),at:1.1,size:9)
        check(timing.observe(clear,at:1.3,size:9)?.method == .handMotion,"Two reliable withdrawing frames could not estimate crossing")
        timing.reset();_=timing.observe(hand(6),at:2,size:9);_=timing.observe(hand(6.01),at:2.2,size:9)
        check(timing.observe(clear,at:2.4,size:9)?.method == .handBracket,"Stationary/disappearing pose invented an exit velocity")
        timing.reset();_=timing.observe(hand(2),at:3,size:9);_=timing.observe(hand(2.1),at:3.1,size:9);_=timing.observe(hand(7),at:3.2,size:9)
        check(timing.observe(clear,at:3.4,size:9)?.method == .handBracket,"Accelerating/noisy trajectory claimed a precise time")
        timing.reset();var two=hand(7);two.hands += hand(4).hands
        _=timing.observe(two,at:4,size:9)
        check(timing.observe(clear,at:4.2,size:9)?.method == .handBracket,"Multiple hands were treated as one trajectory")
        timing.reset();_=timing.observe(hand(7),at:5,size:9)
        check(timing.observe(clear,at:6,size:9)==nil,"A camera gap retained stale hand timing")
        timing.reset();_=timing.observe(hand(7),at:7,size:9);_=timing.observe(nil,at:7.1,size:9)
        check(timing.observe(clear,at:7.2,size:9)==nil,"Failed pose detection was treated as hand clearance")
        timing.reset();_=timing.observe(hand(6.75),at:8,size:9,source:"cameraPresentation");_=timing.observe(hand(7.75),at:8.1,size:9,source:"callback")
        check(timing.observe(clear,at:8.3,size:9,source:"callback")?.method == .handBracket,"Mixed timestamp origins produced an interpolated press")
        check(!ClockPressEstimate(time:.nan,method:.clearFrame).valid,"Nonfinite timing accepted")
        print("PASS: \(checks) hand-motion timing checks: sub-frame crossing, two/three frames, estimated error and observed bracket, stationary/accelerating/multiple hands, gaps, detector failures and timestamp changes")
    }
}
