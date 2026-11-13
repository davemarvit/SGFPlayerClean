import Foundation

enum HandOutlineSampling {
    static func sample(_ frame:GrayFrame,calibration:BoardCalibration,observation:BoardObservation?=nil)->HandOutlineFrame {
        let n=Int((Double(calibration.size-1)+2*HandOutlineFrame.margin)*HandOutlineFrame.scale)+1
        var pixels=[HandOutlineFrame.Pixel]();pixels.reserveCapacity(n*n)
        for row in 0..<n {for col in 0..<n {
            let point=calibration.point(col:Double(col)/HandOutlineFrame.scale-HandOutlineFrame.margin,
                                        row:Double(row)/HandOutlineFrame.scale-HandOutlineFrame.margin)
            if let light=frame.patchMean(point),let color=frame.patchColor(point) {
                pixels.append(.init(red:Float(color.red),green:Float(color.green),light:Float(light)))
            } else {pixels.append(.invalid)}
        }}
        // Only this frame's independent, confident circular white-stone fits
        // can explain foreground changes. History never supplies these masks.
        let stones=(observation?.footprints ?? []).filter {shape in
            shape.quality>=0.95 && observation?.readings.contains(where:{
                $0.row==shape.row && $0.col==shape.col && $0.occupancy == .white && $0.confidence>=0.95
            }) == true
        }.map {HandOutlineFrame.WhiteStone(x:$0.center.x,y:$0.center.y,radiusX:$0.radiusCol,radiusY:$0.radiusRow)}
        return .init(width:n,cells:calibration.size,pixels:pixels,whiteStones:stones)
    }
}
