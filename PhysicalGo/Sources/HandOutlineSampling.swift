import Foundation

enum HandOutlineSampling {
    static func sample(_ frame:GrayFrame,calibration:BoardCalibration,observation:BoardObservation?=nil,boundary:HandBoardBoundary?=nil)->HandOutlineFrame {
        let n=Int((Double(calibration.size-1)+2*HandOutlineFrame.margin)*HandOutlineFrame.scale)+1
        var pixels=[HandOutlineFrame.Pixel]();pixels.reserveCapacity(n*n)
        let polygon=boundary?.vertices.map {vertex -> (Double,Double) in
            let p=calibration.point(col:vertex.x,row:vertex.y)
            return (p.x*Double(frame.width-1),p.y*Double(frame.height-1))
        }
        let edges=polygon.map {points in (0..<4).map {i -> (Double,Double,Double) in
            let a=points[i],b=points[(i+1)%4],dx=b.0-a.0,dy=b.1-a.1,length=hypot(dx,dy)
            return (-dy/length,dx/length,(dy*a.0-dx*a.1)/length)
        }}
        func footprintDepth(_ x:Int,_ y:Int)->Double {
            guard let edges else {return .infinity}
            var depth=Double.infinity
            for edge in edges {depth=min(depth,edge.0*Double(x)+edge.1*Double(y)+edge.2)}
            return depth
        }
        func containsPixel(_ x:Int,_ y:Int)->Bool {
            guard let polygon else {return true}
            for i in 0..<4 {
                let a=polygon[i],b=polygon[(i+1)%4]
                if (b.0-a.0)*(Double(y)-a.1)-(b.1-a.1)*(Double(x)-a.0)<0 {return false}
            }
            return true
        }
        for row in 0..<n {for col in 0..<n {
            let x=Double(col)/HandOutlineFrame.scale-HandOutlineFrame.margin
            let y=Double(row)/HandOutlineFrame.scale-HandOutlineFrame.margin
            let point=calibration.point(col:x,row:y)
            if let boundary {
                let interior=boundary.contains(x:x,y:y)
                // Exterior samples are connectivity context only. Partition
                // each actual patch so exterior pixels cannot contaminate an
                // interior foreground sample (or the reverse).
                let depth=footprintDepth(Int((point.x*Double(frame.width-1)).rounded()),Int((point.y*Double(frame.height-1)).rounded()))
                // Most footprints lie wholly on one side. Their furthest 3x3
                // pixel is sqrt(2) from the rounded center; only the narrow
                // boundary band needs per-pixel clipping.
                let wholePatch=(interior && depth>1.414213563) || (!interior && depth < -1.414213563)
                if wholePatch,let light=frame.patchMean(point),let color=frame.patchColor(point) {
                    pixels.append(.init(red:Float(color.red),green:Float(color.green),light:Float(light)))
                } else if !wholePatch,let patch=frame.boundedHandPatch(point,containsPixel:{containsPixel($0,$1)==interior}) {
                    pixels.append(.init(red:Float(patch.color.red),green:Float(patch.color.green),light:Float(patch.light)))
                } else {pixels.append(.invalid)}
            } else if let light=frame.patchMean(point),let color=frame.patchColor(point) {
                pixels.append(.init(red:Float(color.red),green:Float(color.green),light:Float(light)))
            } else {pixels.append(.invalid)}
        }}
        // Only this frame's independent, confident circular white-stone fits
        // can explain foreground changes. History never supplies these masks.
        let stones=(observation?.footprints ?? []).filter {shape in
            // Outer-line stones can have a less complete fitted outline near
            // the board edge. Require a centered fit and stronger current
            // occupancy evidence there; verifiedWhiteStones still checks the
            // radius and all nine bright, neutral core samples before masking.
            let outer=shape.row==0 || shape.col==0 || shape.row==calibration.size-1 || shape.col==calibration.size-1
            let centered=hypot(shape.center.x-Double(shape.col),shape.center.y-Double(shape.row))<=0.2
            let edgeFit=outer && centered && shape.quality>=0.90 && observation?.readings.contains(where:{
                $0.row==shape.row && $0.col==shape.col && $0.occupancy == .white && $0.confidence>=0.99
            }) == true
            return (shape.quality>=0.95 || edgeFit) && observation?.readings.contains(where:{
                $0.row==shape.row && $0.col==shape.col && $0.occupancy == .white && $0.confidence>=0.95
            }) == true
        }.map {HandOutlineFrame.WhiteStone(x:$0.center.x,y:$0.center.y,radiusX:$0.radiusCol,radiusY:$0.radiusRow)}
        return .init(width:n,cells:calibration.size,pixels:pixels,whiteStones:stones,boundary:boundary)
    }
}
