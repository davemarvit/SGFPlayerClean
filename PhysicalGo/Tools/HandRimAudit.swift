import Foundation
import ImageIO

/// Offline only. The supplied backgrounds are explicit counterfactuals unless
/// the original live checkpoint was retained. No camera or controller access.
@main struct HandRimAudit {
    struct Metadata:Decodable { let currentCalibration:BoardCalibration }
    static func json<T:Encodable>(_ value:T)throws->Any {
        try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))
    }
    static func image(_ path:String)throws->CGImage {
        guard let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {
            throw NSError(domain:"HandRimAudit",code:1,userInfo:[NSLocalizedDescriptionKey:"Image unavailable: \(path)"])
        }
        return image
    }
    // Mirror the production unchangedRim predicate for detailed diagnostics.
    // The verdict itself also runs the unmodified production tracker below.
    static func rim(_ points:[HandMotionPose.Point],frame:HandOutlineFrame,background:HandOutlineFrame)->[String:Any] {
        guard !points.isEmpty else { return ["reason":"no confident joints"] }
        let xs=points.map(\.x),ys=points.map(\.y),high=Double(frame.cells-1)
        let minX=xs.min()!,maxX=xs.max()!,minY=ys.min()!,maxY=ys.max()!
        let side=maxY<0 ? 0:minX>high ? 1:minY>high ? 2:maxX<0 ? 3:-1
        guard side>=0 else {return ["reason":"joints not all outside one grid edge"]}
        var count=0,invalid=0,brightness=0,chroma=0
        var first:[String:Any]?
        for i in frame.pixels.indices {
            let (x,y)=frame.grid(i)
            guard x>=(-0.65),y>=(-0.65),x<=high+0.65,y<=high+0.65 else {continue}
            let near:Bool
            switch side {
            case 0:near=y<=0.75 && x>=minX-1 && x<=maxX+1
            case 1:near=x>=high-0.75 && y>=minY-1 && y<=maxY+1
            case 2:near=y>=high-0.75 && x>=minX-1 && x<=maxX+1
            default:near=x<=0.75 && y>=minY-1 && y<=maxY+1
            }
            guard near else {continue}
            count+=1
            let p=frame.pixels[i],b=background.pixels[i]
            let dr=p.red-b.red,dg=p.green-b.green
            let dl=abs(p.light-b.light),dc=sqrt(dr*dr+dg*dg+(dr+dg)*(dr+dg))
            let bad:String?
            if !p.valid || !b.valid {invalid+=1;bad="invalid sampled patch"}
            else if dl>0.06 {brightness+=1;bad="brightness difference exceeds 0.06"}
            else if dc>0.035 {chroma+=1;bad="color difference exceeds 0.035"}
            else {bad=nil}
            if let bad,first==nil {
                first=["reason":bad,"grid":[x,y],"brightnessDelta":dl,"colorDistance":dc,
                       "currentLight":p.light,"backgroundLight":b.light]
            }
        }
        return ["side":side,"sampledPixels":count,"invalidPixels":invalid,
                "brightnessFailures":brightness,"colorFailures":chroma,
                "firstFailure":first ?? [:],"clear":first==nil && count>=50]
    }
    static func main()throws {
        guard CommandLine.arguments.count>=4 else {
            throw NSError(domain:"HandRimAudit",code:2,userInfo:[NSLocalizedDescriptionKey:"Usage: HandRimAudit metadata.json rejected.png background.png [background.png ...]"])
        }
        let a=CommandLine.arguments
        let calibration=try JSONDecoder().decode(Metadata.self,from:Data(contentsOf:URL(fileURLWithPath:a[1]))).currentCalibration
        let rejected=try image(a[2])
        let pose=BoardHandDetector.pose(image:rejected,calibration:calibration)
        let current=HandOutlineSampling.sample(GrayFrame(image:rejected)!,calibration:calibration)
        var results=[[String:Any]]()
        for path in a.dropFirst(3) {
            let background=HandOutlineSampling.sample(GrayFrame(image:try image(path))!,calibration:calibration)
            var tracker=HandOutlineTracker(checkpoint:.init(background:background,active:false,edge:0,
                center:[0,0],direction:nil,appearance:nil))
            let result=tracker.observe(current,pose:pose,at:1,source:"offline-substituted-background")
            let checks=(pose?.obstructingHands(size:calibration.size) ?? []).map {
                rim($0.filter{$0.confidence>=0.25},frame:current,background:background)
            }
            results.append(["background":path,"originalLiveCheckpoint":false,
                            "rimChecks":checks,"tracker":try json(result)])
        }
        print(String(data:try JSONSerialization.data(withJSONObject:["pose":try json(pose),
            "rejectedImage":a[2],"counterfactualResults":results],options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
