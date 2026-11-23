import Foundation

struct HandOutlineFrame:Codable {
    struct WhiteStone:Codable {
        let x:Double,y:Double,radiusX:Double,radiusY:Double
        func contains(x:Double,y:Double)->Bool {
            // Mask only the fitted stone itself. Expanding into its shadow
            // can erase a narrow fingertip beside an otherwise visible stone.
            pow((x-self.x)/radiusX,2)+pow((y-self.y)/radiusY,2)<=1
        }
    }
    struct Pixel:Codable {
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
    /// Saved at recording start and on a prolonged pose/outline disagreement.
    /// Captures the frozen background so a stuck track can be replayed offline.
    struct Checkpoint:Codable {
        var background:HandOutlineFrame?
        var active:Bool
        var edge:Int
        var center:[Double]
        var direction:[Double]?
        var appearance:[Double]?
    }
    var checkpoint:Checkpoint {
        .init(background:baseline,active:active,edge:edge,center:[center.x,center.y],
              direction:direction.map{[$0.0,$0.1,$0.2]},appearance:appearance.map{[$0.0,$0.1]})
    }
    init() {}
    init(checkpoint c:Checkpoint) {
        baseline=c.background;active=c.active;edge=c.edge
        if c.center.count==2 {center=(c.center[0],c.center[1])}
        if let d=c.direction,d.count==3 {direction=(d[0],d[1],d[2])}
        if let a=c.appearance,a.count==2 {appearance=(a[0],a[1])}
    }
    struct Result:Codable {
        var obstructed:Bool?
        var depth:Double?
        var edge:Int?
        var poseLost=false
        var estimate:ClockPressEstimate?
        var reason:String
        var clearanceDelayed=false
    }
    /// A suspected stall is a diagnostic condition, never proof of clearance.
    /// Store the exact sampled view and pre-observation state for offline replay.
    struct StallEvidence:Codable {
        let checkpoint:Checkpoint
        let frame:HandOutlineFrame
        let pose:HandMotionPose?
        let result:Result
        let time:Double
        let source:String
        let disagreementSeconds:Double
    }
    private(set) var stallEvidence:StallEvidence?
    private var clearPoseSince:Double?
    private var clearPoseSamples=0
    private var stallReported=false
    private struct Component {var indices:[Int];var x:Double;var y:Double;var minimum:Double;var maximum:Double;var coreInside=false}
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
        stallEvidence=nil
        let before=checkpoint,previousTime=lastTime
        var result=observeFrame(frame,pose:pose,at:time,source:source)
        // Gaps/source changes reset this state inside observeFrame. Duplicates
        // cannot build a duration or provide additional independent evidence.
        guard time.isFinite,previousTime.map({time>$0}) ?? true else {return result}
        guard active,result.obstructed==true,pose?.obstructed(size:frame.cells)==false else {
            clearPoseSince=nil;clearPoseSamples=0;stallReported=false
            return result
        }
        if clearPoseSince==nil {clearPoseSince=time}
        clearPoseSamples+=1
        let elapsed=time-clearPoseSince!
        if elapsed>=5,clearPoseSamples>=10 {
            result.clearanceDelayed=true
            if !stallReported {
                stallReported=true
                stallEvidence = .init(checkpoint:before,frame:frame,pose:pose,result:result,
                    time:time,source:source,disagreementSeconds:elapsed)
            }
        }
        return result
    }
    private mutating func observeFrame(_ frame:HandOutlineFrame,pose:HandMotionPose?,at time:Double,source:String)->Result {
        guard time.isFinite else {return .init(reason:"Invalid frame time")}
        if let lastTime,time<=lastTime {return .init(obstructed:active ? true:nil,reason:"Duplicate frame")}
        if let lastTime,time-lastTime>0.65 || self.source != source {reset()}
        lastTime=time;self.source=source
        guard frame.pixels.filter(\.valid).count>frame.pixels.count*3/5 else {
            reset();return .init(reason:"Insufficient visible image; clearance is unknown")
        }
        var hand=pose?.obstructed(size:frame.cells)
        // Hands beside the board must not seed the active hand's location or
        // prevent visual clearance. Keep the existing rim allowance; filtering
        // pose joints alone is never proof that the visible hand has left.
        var boardHands=pose?.obstructingHands(size:frame.cells) ?? []
        if let baseline,baseline.width != frame.width {self.baseline=nil;references=[];initialization=0;active=false;timing.reset()}
        guard let background=baseline else {
            if hand==false {initialization+=1;if initialization>=3 {baseline=frame}}
            else {initialization=0}
            return .init(obstructed:hand==true ? true:nil,reason:"Establishing a clear visual reference")
        }
        if pose?.reliable==true {
            boardHands.removeAll {points in
                let confident=points.filter{$0.confidence>=0.25}
                return unchangedRim(confident.map{($0.x,$0.y)},frame:frame,background:background)
            }
            hand = !boardHands.isEmpty
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
            let points=boardHands.flatMap{$0}.filter{$0.confidence>=0.5}
            let wrist=points.first{$0.id=="VNHLKWRI"} ?? points.first
            if let wrist {
                let n=Double(frame.cells-1)
                edge=[wrist.y,n-wrist.x,n-wrist.y,wrist.x].enumerated().min{$0.element<$1.element}!.offset
            }
            center=(points.map(\.x).reduce(0,+)/Double(max(1,points.count)),points.map(\.y).reduce(0,+)/Double(max(1,points.count)))
        }
        guard boardHands.count<=1 else {
            clearTimes=[];timing.reset();return .init(obstructed:true,edge:edge,reason:"Multiple hands; waiting for a clear view")
        }
        let points=boardHands.first?.filter{$0.confidence>=0.5} ?? []
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
        let solidComponents=hand==false ? components(mask.core,core:mask.core,frame:frame):[]
        let crossingCore=Set(solidComponents.filter {c in
            guard c.minimum<0 else {return false}
            var inside=0
            for i in c.indices {
                let p=frame.grid(i),high=Double(frame.cells)-0.25
                let depth=min(p.0+0.75,p.1+0.75,high-p.0,high-p.1)
                // Retain a narrow fingertip with a full core pixel inside the
                // guard, or a broad shallow intrusion. A few half-pixel edge
                // samples cannot borrow an off-board object's solid area.
                if depth>=1/HandOutlineFrame.scale {return true}
                if depth>0 {inside+=1;if inside>=9 {return true}}
            }
            return false
        }.flatMap(\.indices))
        let components=components(mask.closed,core:mask.core,frame:frame)
        let candidates=components.filter {c in
            let lateral=edge%2==0 ? abs(c.x-center.x):abs(c.y-center.y)
            guard lateral<3.5 && (c.minimum<0 || points.contains{p in hypot(p.x-c.x,p.y-c.y)<2}) else {return false}
            // Off-board clutter must not lend its solid-core evidence to
            // thin changes on the board after the actual hand has withdrawn.
            if hand==false,c.maximum>0,!c.indices.contains(where:{crossingCore.contains($0)}) {return false}
            // A resting hand can touch the outer safety rim without covering
            // any stone. Require its whole visible component to stay outside
            // a stone-sized guard AND unchanged pixels along the nearby board
            // edge. Never clear a fingertip from pose loss or elapsed time.
            if hand==false,c.maximum>0,c.maximum<=0.1,
               unchangedRim(c.indices.map{frame.grid($0)},frame:frame,background:background) {return false}
            // Moving light/shadow can have the learned hand color even after
            // withdrawal. Reject it only when the underlying texture remains
            // strongly visible throughout the component, with no detected hand.
            return hand != false || !(preservesBackground(c,frame:frame,background:background) ||
                                     preservesEntryRim(c,frame:frame,background:background))
        }
        let component=candidates.min{hypot($0.x-center.x,$0.y-center.y)<hypot($1.x-center.x,$1.y-center.y)}
        // A fast withdrawal can leave the learned color/location before the
        // pose detector reacquires it. Require independent boundary clearance
        // before allowing that lost track to disappear.
        if hand==false,component == nil || component!.maximum<=0 {
            let broad=direction==nil ? mask:foreground(frame,background:background,direction:nil,
                                                       whiteStones:frame.verifiedWhiteStones)
            let high=Double(frame.cells)-0.25
            for c in self.components(broad.core,core:broad.core,frame:frame) where c.coreInside {
                // Only a continuous solid path from outside the rim into the
                // grid, beyond the footprint of a single edge stone, can override
                // a lost color/location track. Thin links
                // to an interior stone or a nearby bowl do not qualify.
                let interior=c.indices.lazy.filter {i in
                    let p=frame.grid(i),last=Double(frame.cells-1)
                    return p.0>0.65 && p.1>0.65 && p.0<last-0.65 && p.1<last-0.65
                }.prefix(9).count
                guard interior>=9 else {continue}
                let entries=(0..<4).filter {side in
                    c.indices.contains {i in
                        let p=frame.grid(i)
                        return [p.1+0.75,high-p.0,high-p.1,p.0+0.75][side]<0
                    }
                }
                guard !entries.isEmpty,!preservesBackground(c,frame:frame,background:background),
                      !entries.allSatisfy({preservesEntryRim(c,frame:frame,background:background,entryEdge:$0)}) else {continue}
                clearTimes=[];center=(c.x,c.y)
                // Cross-edge reacquisition cannot extend the old velocity fit.
                // Retain an observed interval for the clock instead.
                timing.reset();timing.observe(depth:max(0.01,c.maximum),at:time)
                return .init(obstructed:true,depth:c.maximum,edge:edge,poseLost:true,
                             reason:"Changed board edge; waiting for visual clearance")
            }
        }
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
    private func unchangedRim(_ points:[(Double,Double)],frame:HandOutlineFrame,background:HandOutlineFrame)->Bool {
        guard !points.isEmpty,points.allSatisfy({$0.0.isFinite && $0.1.isFinite}) else {return false}
        let minX=points.map{$0.0}.min()!,maxX=points.map{$0.0}.max()!
        let minY=points.map{$0.1}.min()!,maxY=points.map{$0.1}.max()!
        let high=Double(frame.cells-1)
        // Joints must all be beyond one outer line. A pose inside the grid
        // always blocks, even if its color happens to resemble the background.
        let side=maxY<0 ? 0:minX>high ? 1:minY>high ? 2:maxX<0 ? 3:nil
        guard let side else {return false}
        var count=0
        for i in frame.pixels.indices {
            let (x,y)=frame.grid(i)
            // Covers a full edge stone plus fringe; the extra lateral cell
            // includes fingers extending beyond their recognized joints.
            guard x>=(-0.65),y>=(-0.65),x<=high+0.65,y<=high+0.65 else {continue}
            let near:Bool
            switch side {
            case 0:near=y<=0.75 && x>=minX-1 && x<=maxX+1
            case 1:near=x>=high-0.75 && y>=minY-1 && y<=maxY+1
            case 2:near=y>=high-0.75 && x>=minX-1 && x<=maxX+1
            default:near=x<=0.75 && y>=minY-1 && y<=maxY+1
            }
            guard near else {continue}
            let p=frame.pixels[i],b=background.pixels[i]
            guard p.valid,b.valid,abs(p.light-b.light)<=0.06 else {return false}
            let r=p.red-b.red,g=p.green-b.green
            guard r*r+g*g+(r+g)*(r+g)<=0.035*0.035 else {return false}
            count+=1
        }
        return count>=50
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
    private func preservesEntryRim(_ component:Component,frame:HandOutlineFrame,background:HandOutlineFrame,entryEdge:Int?=nil)->Bool {
        // An interior stone can change while a hand's shadow remains connected
        // to the rim in the color mask. Prove clearance on the entire entry
        // strip, independently of interior stone changes. Missing poses alone
        // never qualify, and the existing pixel/texture checks retain fingers.
        let sideIndex=entryEdge ?? edge
        guard entryEdge != nil || component.minimum<0 && component.maximum>0.5 else {return false}
        let lateral=component.indices.map {i -> Double in
            let p=frame.grid(i);return sideIndex%2==0 ? p.0:p.1
        }
        guard let lo=lateral.min(),let hi=lateral.max() else {return false}
        var indices=[Int]()
        for i in frame.pixels.indices {
            let p=frame.grid(i),d=[p.1+0.75,Double(frame.cells)-0.25-p.0,Double(frame.cells)-0.25-p.1,p.0+0.75][sideIndex]
            let side=sideIndex%2==0 ? p.0:p.1
            if (-0.4...0.5).contains(d),side>=lo-0.3,side<=hi+0.3 {
                guard frame.pixels[i].valid,background.pixels[i].valid else {return false}
                indices.append(i)
            }
        }
        let rim=Component(indices:indices,x:component.x,y:component.y,minimum:-0.4,maximum:0.5)
        return preservesBackground(rim,frame:frame,background:background)
    }
    private func foreground(_ frame:HandOutlineFrame,background:HandOutlineFrame,direction:(Double,Double,Double)?,whiteStones:[HandOutlineFrame.WhiteStone])->(closed:[Bool],core:[Bool]) {
        let raw=frame.pixels.indices.map {i->Bool in
            let p=frame.pixels[i],b=background.pixels[i]
            guard p.valid,b.valid else {return false}
            let point=frame.grid(i)
            let neutral=sqrt(p.red*p.red+p.green*p.green+(p.red+p.green)*(p.red+p.green))<=0.12
            if p.light>=0.65,neutral,whiteStones.contains(where:{$0.contains(x:point.0,y:point.1)}) {return false}
            // Chroma is unreliable near black, but a hand covering a black
            // stone (or a dark sleeve over wood) still changes luminance.
            if p.light<=0.08 || b.light<=0.08 {return abs(p.light-b.light)>0.10}
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
            var indices=[start],cursor=0,sx=0.0,sy=0.0,lo=Double.infinity,hi = -Double.infinity,coreInside=false
            seen[start]=true
            while cursor<indices.count {
                let i=indices[cursor];cursor+=1
                let (x,y)=frame.grid(i),d=depth(x:x,y:y,cells:frame.cells)
                // Crossing the tracked edge's infinite line is not enough:
                // a patch beyond either corner is outside the board too.
                let boardDepth=min(x+0.75,y+0.75,Double(frame.cells)-0.25-x,Double(frame.cells)-0.25-y)
                if core[i],boardDepth>0 {coreInside=true}
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
            if indices.count>=10,indices.filter({core[$0]}).count>=9 {result.append(.init(indices:indices,x:sx/Double(indices.count),y:sy/Double(indices.count),minimum:lo,maximum:hi,coreInside:coreInside))}
        }
        return result
    }
}

// Older diagnostic archives predate the delayed-clearance flag.
extension HandOutlineTracker.Result {
    init(from decoder:Decoder)throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        obstructed=try values.decodeIfPresent(Bool.self,forKey:.obstructed)
        depth=try values.decodeIfPresent(Double.self,forKey:.depth)
        edge=try values.decodeIfPresent(Int.self,forKey:.edge)
        poseLost=try values.decodeIfPresent(Bool.self,forKey:.poseLost) ?? false
        estimate=try values.decodeIfPresent(ClockPressEstimate.self,forKey:.estimate)
        reason=try values.decode(String.self,forKey:.reason)
        clearanceDelayed=try values.decodeIfPresent(Bool.self,forKey:.clearanceDelayed) ?? false
    }
}
