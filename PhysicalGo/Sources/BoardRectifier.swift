import Foundation
import CoreGraphics
import CoreImage

/// Geometry shared by the perspective-corrected picture, overlays and hit testing.
/// Standard Go grid spacing is approximately 22 mm × 23.6 mm (British Go Association).
struct BoardRectifiedGeometry {
    static let longToShort = 23.6/22.0
    let calibration: BoardCalibration
    let longAxisRows: Bool
    let margin = 0.75 // Grid spaces; preserves the rim and stones on outer intersections.
    var span: Double { Double(calibration.size-1)+2*margin }
    var outputSize: CGSize {
        let short=960.0,long=(short*Self.longToShort).rounded()
        return CGSize(width:longAxisRows ? short : long,height:longAxisRows ? long : short)
    }
    var sourceCorners: [ImagePoint] {
        let last=Double(calibration.size-1)+margin
        return [calibration.point(col:-margin,row:-margin),calibration.point(col:last,row:-margin),
                calibration.point(col:last,row:last),calibration.point(col:-margin,row:last)]
    }
    func normalizedPoint(from source:ImagePoint)->ImagePoint? {
        guard let grid=calibration.gridPoint(for:source) else { return nil }
        return ImagePoint(x:(grid.x+margin)/span,y:(grid.y+margin)/span)
    }
    func sourcePoint(from normalized:ImagePoint)->ImagePoint {
        calibration.point(col:normalized.x*span-margin,row:normalized.y*span-margin)
    }
}

enum BoardRectifier {
    private static let context=CIContext(options:[.cacheIntermediates:false])
    static func render(_ image:CGImage,geometry:BoardRectifiedGeometry)->CGImage? {
        func vector(_ p:ImagePoint)->CIVector {
            CIVector(x:p.x*Double(image.width-1),y:(1-p.y)*Double(image.height-1))
        }
        let corners=geometry.sourceCorners
        let input=CIImage(cgImage:image)
        guard let filter=CIFilter(name:"CIPerspectiveCorrection",parameters:[
            kCIInputImageKey:input,"inputTopLeft":vector(corners[0]),"inputTopRight":vector(corners[1]),
            "inputBottomRight":vector(corners[2]),"inputBottomLeft":vector(corners[3]),"inputCrop":true]),
              let corrected=filter.outputImage else { return nil }
        let extent=corrected.extent
        guard extent.width.isFinite,extent.height.isFinite,extent.width>0,extent.height>0 else { return nil }
        let size=geometry.outputSize
        let aligned=corrected.transformed(by:CGAffineTransform(translationX:-extent.minX,y:-extent.minY))
        let scaled=aligned.transformed(by:CGAffineTransform(scaleX:size.width/extent.width,y:size.height/extent.height))
        return context.createCGImage(scaled,from:CGRect(origin:.zero,size:size))
    }
}

/// Fits both possible standard-board orientations to a centered, square-pixel
/// pinhole camera with unknown focal length. A single planar view does not always
/// determine intrinsics: axial tilts can fit BOTH orientations exactly.
struct BoardAspectEstimate {
    let longAxisRows: Bool
    let confident: Bool
    var gridLineSamples: Int = 0
    static func estimate(_ calibration:BoardCalibration,width:Int,height:Int,frame:GrayFrame? = nil)->Self {
        let axes=calibration.projectiveAxes
        func scores(cx:Double,cy:Double)->[Double] {
            let a=axes[0],b=axes[1]
            let ax=a.0*Double(width-1)-cx*a.2, ay=a.1*Double(height-1)-cy*a.2
            let bx=b.0*Double(width-1)-cx*b.2, by=b.1*Double(height-1)-cy*b.2
            return [false,true].map { rows in
                let ratio=rows ? BoardRectifiedGeometry.longToShort : 1/BoardRectifiedGeometry.longToShort
                var best=Double.infinity
                // Broad camera range; not a claim about this webcam's actual lens.
                for i in 0...400 {
                    let f=Double(width)*0.25*pow(24,Double(i)/400)
                    let aa=ax*ax+ay*ay+f*f*a.2*a.2
                    let bb=bx*bx+by*by+f*f*b.2*b.2
                    let dot=ax*bx+ay*by+f*f*a.2*b.2
                    let orthogonal=dot/sqrt(aa*bb)
                    let aspect=log(sqrt(bb/aa)/ratio)
                    best=min(best,hypot(orthogonal,aspect))
                }
                return best
            }
        }
        let cx=Double(width-1)/2,cy=Double(height-1)/2
        let center=scores(cx:cx,cy:cy),winner=center[1]<center[0] ? 1 : 0
        // Don't declare confidence if a small principal-point error reverses the
        // decision, or if both orientations fit nearly equally well.
        var confident=center[winner]<0.025 && center[1-winner]-center[winner]>0.025
        for (dx,dy) in [(0.02,0.0),(-0.02,0.0),(0.0,0.02),(0.0,-0.02)] {
            let shifted=scores(cx:cx+dx*Double(width),cy:cy+dy*Double(height))
            confident = confident && shifted[1-winner]-shifted[winner]>0.015 && shifted[winner]<0.04
        }
        if !confident,let frame,let lines=GridLineAspectEstimator.estimate(frame:frame,calibration:calibration) {
            return Self(longAxisRows:lines.longAxisRows,confident:true,gridLineSamples:lines.sampleCount)
        }
        return Self(longAxisRows:winner==1,confident:confident)
    }
}
