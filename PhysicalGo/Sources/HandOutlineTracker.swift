import Foundation

struct HandOutlineFrame {
    struct Pixel {
        var red:Float,green:Float,light:Float
        static let invalid=Pixel(red:0,green:0,light:-1)
        var valid:Bool {light>=0}
    }
    let width:Int
    let cells:Int
    let pixels:[Pixel]
    static let scale=10.0,margin=2.0
    func grid(_ index:Int)->(Double,Double) {
        (Double(index%width)/Self.scale-Self.margin,Double(index/width)/Self.scale-Self.margin)
    }
    func index(x:Double,y:Double)->Int? {
        let col=Int(((x+Self.margin)*Self.scale).rounded()),row=Int(((y+Self.margin)*Self.scale).rounded())
        guard col>=0,row>=0,col<width,row<width else {return nil};return row*width+col
    }
}

/// A pose seeds a foreground appearance and location; subsequent tracking uses
/// image changes against a frozen clear view, not skin-color assumptions.
/// Missing joints never constitute clearance. Two visual clear views confirm
/// an exit while the original first-clear time remains available for the clock.
struct HandOutlineTracker {
    struct Result:Codable {
        var obstructed:Bool?
        var depth:Double?
        var edge:Int?
        var poseLost=false
        var estimate:ClockPressEstimate?
        var reason:String
    }
    private struct Component {var indices:[Int];var x:Double;var y:Double;var minimum:Double;var maximum:Double}
    private var baseline:HandOutlineFrame?
    private var references=[(time:Double,frame:HandOutlineFrame)]()
    private var lastTime:Double?
    private var source:String?
    private var active=false
    private var edge=0 // top, right, bottom, left
    private var center=(x:0.0,y:0.0)
    private var direction:(Double,Double,Double)?
    private var appearance:(Double,Double)?
    private var clearTimes=[Double]()
    private var timing=HandOutlineTiming()
    private var initialization=0
    mutating func reset() {self=Self()}
    mutating func observe(_ frame:HandOutlineFrame,pose:HandMotionPose?,at time:Double,source:String)->Result {
        guard time.isFinite else {return .init(reason:"Invalid frame time")}
        if let lastTime,time<=lastTime {return .init(obstructed:active ? true:nil,reason:"Duplicate frame")}
        if let lastTime,time-lastTime>0.65 || self.source != source {reset()}
        lastTime=time;self.source=source
        guard frame.pixels.filter(\.valid).count>frame.pixels.count*3/5 else {
            reset();return .init(reason:"Insufficient visible image; clearance is unknown")
        }
        let hand=pose?.obstructed(size:frame.cells)
        if let baseline,baseline.width != frame.width {self.baseline=nil;references=[];initialization=0;active=false;timing.reset()}
        guard let background=baseline else {
            if hand==false {initialization+=1;if initialization>=3 {baseline=frame}}
            else {initialization=0}
            return .init(obstructed:hand==true ? true:nil,reason:"Establishing a clear visual reference")
        }
        if !active {
            guard hand==true else {
                if hand==false {
                    // Pose recognition can lag entry too. Never learn the
                    // immediately preceding (possibly already covered) image
                    // as the background for a newly recognized hand.
                    references.append((time,frame))
                    if let safe=references.last(where:{time-$0.time>=0.5}) {baseline=safe.frame}
                    references.removeAll{time-$0.time>0.8}
                    if references.count>90 {references.removeFirst(references.count-90)}
                }
                return .init(obstructed:hand,reason:hand==false ? "Clear visual reference":"Hand detector unavailable")
            }
            active=true;timing.reset();clearTimes=[];direction=nil;appearance=nil
            let points=pose?.hands.flatMap{$0}.filter{$0.confidence>=0.5} ?? []
            let wrist=points.first{$0.id=="VNHLKWRI"} ?? points.first
            if let wrist {
                let n=Double(frame.cells-1)
                edge=[wrist.y,n-wrist.x,n-wrist.y,wrist.x].enumerated().min{$0.element<$1.element}!.offset
            }
            center=(points.map(\.x).reduce(0,+)/Double(max(1,points.count)),points.map(\.y).reduce(0,+)/Double(max(1,points.count)))
        }
        guard (pose?.hands.count ?? 0)<=1 else {
            clearTimes=[];timing.reset();return .init(obstructed:true,edge:edge,reason:"Multiple hands; waiting for a clear view")
        }
        let points=pose?.hands.first?.filter{$0.confidence>=0.5} ?? []
        if points.count>=8,points.contains(where:{depth(x:$0.x,y:$0.y,cells:frame.cells)>1}) {
            var changes=[(Double,Double,Double)](),colors=[(Double,Double)]()
            for p in points where p.x>=0 && p.y>=0 && p.x<Double(frame.cells) && p.y<Double(frame.cells) {
                guard let i=frame.index(x:p.x,y:p.y),frame.pixels[i].valid,background.pixels[i].valid,
                      frame.pixels[i].light>0.12,background.pixels[i].light>0.12 else {continue}
                let r=Double(frame.pixels[i].red-background.pixels[i].red),g=Double(frame.pixels[i].green-background.pixels[i].green)
                changes.append((r,g,-r-g))
                colors.append((Double(frame.pixels[i].red),Double(frame.pixels[i].green)))
            }
            if changes.count>=5 {
                func median(_ values:[Double])->Double {values.sorted()[values.count/2]}
                let r=median(changes.map{$0.0}),g=median(changes.map{$0.1}),b=median(changes.map{$0.2}),norm=sqrt(r*r+g*g+b*b)
                if norm>=0.02 {
                    if let d=direction {direction=(0.8*d.0+0.2*r/norm,0.8*d.1+0.2*g/norm,0.8*d.2+0.2*b/norm)}
                    else {direction=(r/norm,g/norm,b/norm)}
                    let color=(median(colors.map{$0.0}),median(colors.map{$0.1}))
                    if let old=appearance {appearance=(0.8*old.0+0.2*color.0,0.8*old.1+0.2*color.1)} else {appearance=color}
                }
            }
        }
        let mask=foreground(frame,background:background,direction:direction)
        let components=components(mask.closed,core:mask.core,frame:frame)
        let candidates=components.filter {c in
            let lateral=edge%2==0 ? abs(c.x-center.x):abs(c.y-center.y)
            return lateral<3.5 && (c.minimum<0 || points.contains{p in hypot(p.x-c.x,p.y-c.y)<2})
        }
        let component=candidates.min{hypot($0.x-center.x,$0.y-center.y)<hypot($1.x-center.x,$1.y-center.y)}
        if let component {
            center=(component.x,component.y)
            let depth=component.maximum
            timing.observe(depth:depth,at:time)
            if depth>0 || hand==true {
                clearTimes=[]
                return .init(obstructed:true,depth:depth,edge:edge,poseLost:hand != true,reason:"Tracking the visible hand outline")
            }
        } else if hand==true || hand==nil {
            clearTimes=[]
            return .init(obstructed:true,edge:edge,poseLost:hand != true,reason:"Hand outline uncertain; waiting for visual clearance")
        }
        // No pose is insufficient on its own: foreground in the last tracked
        // neighborhood must also have cleared the rim. Detached interior changes
        // are left to the independent legal-board/capture verification.
        clearTimes.append(time)
        guard clearTimes.count>=2,let firstClear=clearTimes.first else {
            return .init(obstructed:true,depth:component?.maximum,edge:edge,poseLost:true,reason:"Confirming visual clearance")
        }
        let estimate=direction==nil ? nil:timing.estimate(firstClear:firstClear,source:source)
        active=false;baseline=frame;references=[];clearTimes=[];timing.reset()
        return .init(obstructed:false,depth:component?.maximum,edge:edge,poseLost:true,estimate:estimate,reason:"Visible hand exit verified")
    }
    private func depth(x:Double,y:Double,cells:Int)->Double {
        let high=Double(cells)-0.25
        return [y+0.75,high-x,high-y,x+0.75][edge]
    }
    private func foreground(_ frame:HandOutlineFrame,background:HandOutlineFrame,direction:(Double,Double,Double)?)->(closed:[Bool],core:[Bool]) {
        let raw=zip(frame.pixels,background.pixels).map {p,b->Bool in
            guard p.valid,b.valid,p.light>0.08,b.light>0.08 else {return false}
            let r=Double(p.red-b.red),g=Double(p.green-b.green)
            if let d=direction {
                if let appearance {
                    let a=Double(p.red)-appearance.0,b=Double(p.green)-appearance.1
                    guard sqrt(a*a+b*b+(a+b)*(a+b))<0.065 else {return false}
                }
                return r*d.0+g*d.1+(-r-g)*d.2>0.018
            }
            // Low chromatic contrast keeps a conservative difference mask.
            return abs(p.light-b.light)>0.10 || sqrt(r*r+g*g+(r+g)*(r+g))>0.035
        }
        // Close one-pixel gaps from grid texture/compression without assuming
        // that disconnected stones belong to the hand.
        let n=frame.width
        var expanded=raw,result=raw,core=Array(repeating:false,count:raw.count)
        for y in 1..<n-1 {for x in 1..<n-1 {
            let i=y*n+x
            expanded[i]=(-1...1).contains{dy in (-1...1).contains{dx in raw[i+dy*n+dx]}}
            core[i]=(-1...1).allSatisfy{dy in (-1...1).allSatisfy{dx in raw[i+dy*n+dx]}}
        }}
        for y in 1..<n-1 {for x in 1..<n-1 {
            let i=y*n+x
            result[i]=(-1...1).allSatisfy{dy in (-1...1).allSatisfy{dx in expanded[i+dy*n+dx]}}
        }}
        return (result,core)
    }
    private func components(_ mask:[Bool],core:[Bool],frame:HandOutlineFrame)->[Component] {
        let n=frame.width
        var seen=Array(repeating:false,count:mask.count),result=[Component]()
        for start in mask.indices where mask[start] && !seen[start] {
            var indices=[start],cursor=0,sx=0.0,sy=0.0,lo=Double.infinity,hi = -Double.infinity
            seen[start]=true
            while cursor<indices.count {
                let i=indices[cursor];cursor+=1
                let (x,y)=frame.grid(i),d=depth(x:x,y:y,cells:frame.cells)
                sx+=x;sy+=y;lo=min(lo,d);hi=max(hi,d)
                for dy in -1...1 {for dx in -1...1 where dy != 0 || dx != 0 {
                    let xx=i%n+dx,yy=i/n+dy
                    if xx>=0,xx<n,yy>=0,yy<n {
                        let j=yy*n+xx
                        if mask[j],!seen[j] {seen[j]=true;indices.append(j)}
                    }
                }}
            }
            // Require a solid core to reject thin grid/shadow remnants, while
            // retaining the original boundary pixels of a real component.
            if indices.count>=10,indices.filter({core[$0]}).count>=9 {result.append(.init(indices:indices,x:sx/Double(indices.count),y:sy/Double(indices.count),minimum:lo,maximum:hi))}
        }
        return result
    }
}
