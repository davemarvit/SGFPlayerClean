import Foundation

enum HandOutlineSampling {
    static func sample(_ frame:GrayFrame,calibration:BoardCalibration)->HandOutlineFrame {
        let n=Int((Double(calibration.size-1)+2*HandOutlineFrame.margin)*HandOutlineFrame.scale)+1
        var pixels=[HandOutlineFrame.Pixel]();pixels.reserveCapacity(n*n)
        for row in 0..<n {for col in 0..<n {
            let point=calibration.point(col:Double(col)/HandOutlineFrame.scale-HandOutlineFrame.margin,
                                        row:Double(row)/HandOutlineFrame.scale-HandOutlineFrame.margin)
            if let light=frame.patchMean(point),let color=frame.patchColor(point) {
                pixels.append(.init(red:Float(color.red),green:Float(color.green),light:Float(light)))
            } else {pixels.append(.invalid)}
        }}
        return .init(width:n,cells:calibration.size,pixels:pixels)
    }
}
