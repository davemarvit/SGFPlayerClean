import Foundation

/// Appearance measurements relative to local wood, not occupancy probabilities.
/// No game state or detector guesses enter these features or training labels.
struct StoneAppearanceFeatures: Codable, Equatable {
    let values: [Double]
    let woodLevel: Double
    static let names = ["Brightness relative to wood", "Body brightness variation", "Color difference from wood", "Visible grid contrast", "Body-to-edge contrast"]
    static let floors = [0.045, 0.035, 0.025, 0.025, 0.045]

    static func extract(frame: GrayFrame, reference: GrayFrame, calibration: BoardCalibration,
                        referenceCalibration: BoardCalibration, point: Int) -> Self? {
        let n=calibration.size
        guard n==referenceCalibration.size,(0..<n*n).contains(point),
              frame.width==reference.width,frame.height==reference.height else {return nil}
        let row=Double(point/n),col=Double(point%n)
        func median(_ a:[Double])->Double {quantile(a,0.5)}
        var woodChanges=[Double](), woodColors=[Double]()
        // Cell centers lie outside centered stone bodies, including touching pairs.
        for dy in [-0.5,0.5] {for dx in [-0.5,0.5] {
            guard (0...Double(n-1)).contains(row+dy),(0...Double(n-1)).contains(col+dx) else {continue}
            let p=calibration.point(col:col+dx,row:row+dy)
            let q=referenceCalibration.point(col:col+dx,row:row+dy)
            if let a=frame.patchMean(p),let b=reference.patchMean(q) {woodChanges.append(a-b)}
            if let color=frame.patchColor(p) {woodColors.append(color.magnitude)}
        }}
        guard !woodChanges.isEmpty else {return nil}
        let correction=median(woodChanges)
        var body=[Double](), base=[Double](), colors=[Double](), ring=[Double]()
        for dy in [-0.22,-0.11,0.11,0.22] {for dx in [-0.22,-0.11,0.11,0.22] {
            let p=calibration.point(col:col+dx,row:row+dy)
            let q=referenceCalibration.point(col:col+dx,row:row+dy)
            if let a=frame.patchMean(p),let b=reference.patchMean(q) {body.append(a);base.append(b)}
            if let c=frame.patchColor(p) {colors.append(c.magnitude)}
        }}
        for i in 0..<16 {
            let angle=Double(i)*Double.pi/8
            if let a=frame.patchMean(calibration.point(col:col+cos(angle)*0.52,row:row+sin(angle)*0.52)) {ring.append(a)}
        }
        guard body.count>=12,ring.count>=8 else {return nil}
        var rails=[Double]()
        for axis in 0..<2 {for offset in [-0.22,0.0,0.22] {
            let x=axis==0 ? offset:0, y=axis==0 ? 0:offset
            let acrossX=axis==0 ? 0:0.09,acrossY=axis==0 ? 0.09:0
            if let center=frame.patchMean(calibration.point(col:col+x,row:row+y)),
               let a=frame.patchMean(calibration.point(col:col+x+acrossX,row:row+y+acrossY)),
               let b=frame.patchMean(calibration.point(col:col+x-acrossX,row:row+y-acrossY)) {
                rails.append((a+b)/2-center)
            }
        }}
        guard rails.count>=4 else {return nil}
        let wood=median(base)+correction
        let values=[median(body)-wood,quantile(body,0.9)-quantile(body,0.1),
                    (colors.isEmpty ? 0:median(colors))-(woodColors.isEmpty ? 0:median(woodColors)),
                    median(rails),median(body)-median(ring)]
        guard values.allSatisfy(\.isFinite),wood.isFinite else {return nil}
        return Self(values:values,woodLevel:wood)
    }
    static func quantile(_ a:[Double],_ fraction:Double)->Double {
        guard !a.isEmpty else {return 0}
        let sorted=a.sorted();return sorted[min(sorted.count-1,Int((Double(sorted.count-1)*fraction).rounded()))]
    }
}

/// Counts describe evidence, including unknown neighbors; missing labels are not empties.
struct StoneNeighborContext: Codable, Equatable {
    let black: Int
    let white: Int
    let unknown: Int
    var group:String {
        if unknown>0 {return "unknown"}
        if black>0 && white>0 {return "mixed"}
        if black>0 {return black==1 ? "one black":"several black"}
        if white>0 {return white==1 ? "one white":"several white"}
        return "open"
    }
    static let unknown = Self(black:0,white:0,unknown:8)
    static func observed(point:Int,observation:BoardObservation,manual:[Int:Occupancy]=[:])->Self {
        var known=manual
        for r in observation.readings where r.confidence>=0.9 && r.occupancy != .uncertain {
            let i=r.row*observation.size+r.col
            guard known[i]==nil else {continue}
            if r.occupancy == .empty || (observation.footprints+observation.placementFits).contains(where:{$0.row==r.row && $0.col==r.col && $0.quality>=0.85}) {known[i]=r.occupancy}
        }
        return measure(point:point,size:observation.size,known:known)
    }
    static func measure(point:Int,size:Int,known:[Int:Occupancy])->Self {
        var black=0,white=0,unknown=0
        for dr in -1...1 {for dc in -1...1 where dr != 0 || dc != 0 {
            let r=point/size+dr,c=point%size+dc
            guard (0..<size).contains(r),(0..<size).contains(c) else {continue}
            switch known[r*size+c] {
            case .black:black += 1
            case .white:white += 1
            case .empty:break
            default:unknown += 1
            }
        }}
        return Self(black:black,white:white,unknown:unknown)
    }
}

struct StoneAppearanceModel: Codable {
    struct Example: Codable {
        let point: Int
        let label: Occupancy
        let features: StoneAppearanceFeatures
        var context: StoneNeighborContext = .unknown
    }
    struct Distribution: Codable {
        let label: Occupancy
        let count: Int
        let center: [Double]
        let radius: [Double]
    }
    struct Match {
        let label: Occupancy
        let distance: Double
        let compatibility: Double // Relative appearance fit; NOT probability.
    }
    struct Prediction {
        let matches: [Match]
        let label: Occupancy
    }
    struct Component:Codable {
        let group:String
        let distribution:Distribution
    }
    let distributions: [Distribution]
    let components: [Component]
    private static func fit(_ rows:[Example],label:Occupancy)->Distribution? {
        guard rows.count>=3 else {return nil}
        var center=[Double](),radius=[Double]()
        for feature in 0..<5 {
            let a=rows.map{$0.features.values[feature]}
            let median=StoneAppearanceFeatures.quantile(a,0.5)
            let span=max(abs(StoneAppearanceFeatures.quantile(a,0.1)-median),abs(StoneAppearanceFeatures.quantile(a,0.9)-median))
            center.append(median);radius.append(max(StoneAppearanceFeatures.floors[feature],span*1.25))
        }
        return Distribution(label:label,count:rows.count,center:center,radius:radius)
    }
    init?(examples: [Example]) {
        var fitted=[Distribution]()
        for label in [Occupancy.empty,.black,.white] {
            let rows=examples.filter{$0.label==label && $0.features.values.count==5 && $0.features.values.allSatisfy(\.isFinite)}
            guard let d=Self.fit(rows,label:label) else {return nil}
            fitted.append(d)
        }
        distributions=fitted
        var components=[Component]()
        for group in Set(examples.map{$0.context.group}).sorted() where group != "unknown" {
            for label in [Occupancy.empty] {
                let rows=examples.filter{$0.context.group==group && $0.label==label && $0.features.values.count==5 && $0.features.values.allSatisfy(\.isFinite)}
                if let d=Self.fit(rows,label:label) {components.append(Component(group:group,distribution:d))}
            }
        }
        self.components=components
    }
    func distribution(for label:Occupancy,context:StoneNeighborContext)->Distribution? {
        components.first{$0.group==context.group && $0.distribution.label==label}?.distribution ?? distributions.first{$0.label==label}
    }
    func predict(_ features: StoneAppearanceFeatures,context:StoneNeighborContext = .unknown) -> Prediction {
        guard features.values.count==5,features.values.allSatisfy(\.isFinite) else {return Prediction(matches:[],label:.uncertain)}
        let matches=distributions.compactMap { base -> Match? in
            let d=distribution(for:base.label,context:context) ?? base
            guard d.center.count==5,d.radius.count==5,d.radius.allSatisfy({$0.isFinite && $0>0}),d.center.allSatisfy(\.isFinite) else {return nil}
            let z=(0..<5).map{abs(features.values[$0]-d.center[$0])/d.radius[$0]}
            let distance=sqrt(z.map{$0*$0}.reduce(0,+)/5)
            return Match(label:d.label,distance:distance,compatibility:exp(-0.5*distance*distance))
        }.sorted{$0.distance<$1.distance}
        guard matches.count==3,let first=matches.first,first.distance<=1.25,
              matches[1].distance-first.distance>=0.65 else {return Prediction(matches:matches,label:.uncertain)}
        return Prediction(matches:matches,label:first.label)
    }
}

/// Raw camera-grid locations. Rotation is a presentation concern only.
enum StoneCalibrationPattern {
    static func stones(size:Int,round:Int)->[Int:Occupancy] {
        guard [9,13,19].contains(size),(0...1).contains(round) else {return [:]}
        let near=size==9 ? 2:3,far=size-1-near,mid=size/2
        let points=[near*size+near,near*size+far,far*size+near,far*size+far,mid*size+mid,mid*size+mid+1]
        // The touching pair is Black in round one, White in round two. This
        // supplies empty samples beside one and two stones of each color.
        let colors:[Occupancy]=[.black,.white,.white,.white,.black,.black]
        return Dictionary(uniqueKeysWithValues:points.enumerated().map {index,point in
            (point,round==0 ? colors[index] : colors[index] == .black ? .white:.black)
        })
    }
    static func labels(size:Int,round:Int)->[Int:Occupancy] {
        var labels=stones(size:size,round:round)
        for point in Array(labels.keys) {
            for dr in -1...1 {for dc in -1...1 where dr != 0 || dc != 0 {
                let row=point/size+dr,col=point%size+dc
                guard (0..<size).contains(row),(0..<size).contains(col) else {continue}
                let neighbor=row*size+col
                if labels[neighbor]==nil {labels[neighbor] = .empty}
            }}
        }
        return labels
    }
}
