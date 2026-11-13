import Foundation

struct HandOutlineFrame {
    struct WhiteStone:Codable {
        let x:Double,y:Double,radiusX:Double,radiusY:Double
        func contains(x:Double,y:Double)->Bool {
            // Include the fitted outline's antialiasing/shadow fringe, not a
            // whole intersection where an adjacent fingertip could remain.
            pow((x-self.x)/(radiusX+0.15),2)+pow((y-self.y)/(radiusY+0.15),2)<=1
        }
    }
    struct Pixel {
        var red:Float,green:Float,light:Float
        static let invalid=Pixel(red:0,green:0,light:-1)
        var valid:Bool {light>=0}
    }
    let width:Int
    let cells:Int
    let pixels:[Pixel]
    var whiteStones:[WhiteStone]=[]
    static let scale=10.0,margin=2.0
    func grid(_ index:Int)->(Double,Double) {
        (Double(index%width)/Self.scale-Self.margin,Double(index/width)/Self.scale-Self.margin)
    }
    func index(x:Double,y:Double)->Int? {
        let col=Int(((x+Self.margin)*Self.scale).rounded()),row=Int(((y+Self.margin)*Self.scale).rounded())
        guard col>=0,row>=0,col<width,row<width else {return nil};return row*width+col
    }
    var verifiedWhiteStones:[WhiteStone] {
        whiteStones.filter {stone in
            guard (0.32...0.60).contains(stone.radiusX),(0.32...0.65).contains(stone.radiusY) else {return false}
            // Current round-shape evidence also needs a bright, neutral core.
            // A saved stone or a skin-colored fingertip is not clearance.
            return (0...8).allSatisfy {step in
                let angle=Double(step)*Double.pi/4,r=step==8 ? 0.0:0.5
                guard let i=index(x:stone.x+cos(angle)*stone.radiusX*r,y:stone.y+sin(angle)*stone.radiusY*r) else {return false}
                let p=pixels[i],red=Double(p.red),green=Double(p.green)
                return p.valid && p.light>=0.65 && sqrt(red*red+green*green+(red+green)*(red+green))<=0.12
            }
        }
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
        let mask=foreground(frame,background:background,direction:direction,
                            whiteStones:hand==false ? frame.verifiedWhiteStones:[])
        let components=components(mask.closed,core:mask.core,frame:frame)
        let candidates=components.filter {c in
            let lateral=edge%2==0 ? abs(c.x-center.x):abs(c.y-center.y)
            guard lateral<3.5 && (c.minimum<0 || points.contains{p in hypot(p.x-c.x,p.y-c.y)<2}) else {return false}
            // Moving light/shadow can have the learned hand color even after
            // withdrawal. Reject it only when the underlying texture remains
            // strongly visible throughout the component, with no detected hand.
            return hand != false || !preservesBackground(c,frame:frame,background:background)
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
    private func preservesBackground(_ component:Component,frame:HandOutlineFrame,background:HandOutlineFrame)->Bool {
        guard component.indices.count>=100 else {return false}
        let n=Double(component.indices.count)
        var sx=0.0,sy=0.0,sxx=0.0,syy=0.0,sxy=0.0
        for i in component.indices {
            let x=Double(background.pixels[i].light),y=Double(frame.pixels[i].light)
            sx+=x;sy+=y;sxx+=x*x;syy+=y*y;sxy+=x*y
        }
        let vx=sxx-sx*sx/n,vy=syy-sy*sy/n,cov=sxy-sx*sy/n
        // Flat wood cannot prove clearance. Texture must survive a modest
        // brightness/contrast change; a skin-colored region alone never does.
        var slope:Double,offset:Double,residualLimit=0.08,tileLimit=0.0016
        if vx/n>0.0016,vy/n>0.0016,cov/sqrt(vx*vy)>0.98 {
            slope=cov/vx;offset=(sy-slope*sx)/n
        } else {
            // Low-contrast rim grain is easily buried in camera noise. Compare
            // small spatial averages, but still test EVERY original pixel below
            // with tighter residual limits so a fingertip cannot be averaged away.
            guard component.maximum<=0.5 else {return false}
            let members=Set(component.indices),width=frame.width
            var pairs=[(Double,Double)]()
            for i in component.indices {
                var x=0.0,y=0.0,count=0
                for dy in -2...2 {for dx in -2...2 {
                    let col=i%width+dx,row=i/width+dy
                    guard col>=0,col<width,row>=0,row<width else {continue}
                    let j=row*width+col
                    if members.contains(j),background.pixels[j].valid,frame.pixels[j].valid {
                        x+=Double(background.pixels[j].light);y+=Double(frame.pixels[j].light);count+=1
                    }
                }}
                if count>=15 {pairs.append((x/Double(count),y/Double(count)))}
            }
            guard pairs.count>=100 else {return false}
            let count=Double(pairs.count),mx=pairs.map{$0.0}.reduce(0,+)/count,my=pairs.map{$0.1}.reduce(0,+)/count
            let xx=pairs.map{pow($0.0-mx,2)}.reduce(0,+),yy=pairs.map{pow($0.1-my,2)}.reduce(0,+)
            let xy=pairs.map{($0.0-mx)*($0.1-my)}.reduce(0,+)
            guard xx/count>0.0001,yy/count>0.0001,xy/sqrt(xx*yy)>0.985 else {return false}
            slope=xy/xx;offset=my-slope*mx;residualLimit=0.04;tileLimit=0.0004
        }
        guard (0.6...1.4).contains(slope) else {return false}
        var tiles=[Int:(squared:Double,count:Int)]()
        let tileWidth=(frame.width+9)/10
        for i in component.indices {
            let error=Double(frame.pixels[i].light)-slope*Double(background.pixels[i].light)-offset
            // A small remaining fingertip must not disappear into a good
            // whole-component average. Check individual residuals and cells.
            guard background.pixels[i].valid,frame.pixels[i].valid,abs(error)<=residualLimit else {return false}
            let key=(i/frame.width/10)*tileWidth+(i%frame.width/10)
            let previous=tiles[key] ?? (0,0)
            tiles[key]=(previous.squared+error*error,previous.count+1)
        }
        return tiles.values.allSatisfy{$0.count<12 || $0.squared/Double($0.count)<=tileLimit}
    }
    private func foreground(_ frame:HandOutlineFrame,background:HandOutlineFrame,direction:(Double,Double,Double)?,whiteStones:[HandOutlineFrame.WhiteStone])->(closed:[Bool],core:[Bool]) {
        let raw=frame.pixels.indices.map {i->Bool in
            let p=frame.pixels[i],b=background.pixels[i]
            guard p.valid,b.valid,p.light>0.08,b.light>0.08 else {return false}
            let point=frame.grid(i)
            if whiteStones.contains(where:{$0.contains(x:point.0,y:point.1)}) {return false}
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
                // Crossing the tracked edge's infinite line is not enough:
                // a patch beyond either corner is outside the board too.
                let lateral=edge%2==0 ? x:y
                let boardDepth=min(d,lateral+0.75,Double(frame.cells)-0.25-lateral)
                sx+=x;sy+=y;lo=min(lo,d);hi=max(hi,boardDepth)
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
