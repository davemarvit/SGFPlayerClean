import Foundation
import CoreGraphics

/// Image content is checked independently of presentation timestamps: a phone
/// can keep sending fresh buffers containing a frozen or blurred placeholder.
struct CameraFeedHealth {
    struct Sample {
        let fingerprint:UInt64
        let edgeFraction:Double
        let detailEnergy:Double
        var severelyBlurred:Bool {edgeFraction<0.001 && detailEnergy<12}
        static func measure(_ image:CGImage)->Sample? {
            let width=320,height=180
            var pixels=[UInt8](repeating:0,count:width*height)
            let drawn=pixels.withUnsafeMutableBytes {bytes -> Bool in
                guard let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,
                    bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else {return false}
                context.interpolationQuality = .high
                context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
            }
            guard drawn,let data=image.dataProvider?.data,let bytes=CFDataGetBytePtr(data) else {return nil}
            // Sample original pixels, retaining sensor noise that distinguishes
            // a stationary live board from an exactly repeated camera buffer.
            var hash:UInt64=14695981039346656037
            for index in stride(from:0,to:CFDataGetLength(data),by:97) {hash=(hash ^ UInt64(bytes[index])) &* 1099511628211}
            hash=(hash ^ UInt64(image.width)) &* 1099511628211
            hash=(hash ^ UInt64(image.height)) &* 1099511628211
            var energy=0.0,edges=0
            for y in 1..<height-1 {for x in 1..<width-1 {
                let p=y*width+x
                let detail=abs(4*Int(pixels[p])-Int(pixels[p-1])-Int(pixels[p+1])-Int(pixels[p-width])-Int(pixels[p+width]))
                energy+=Double(detail*detail);if detail>12 {edges+=1}
            }}
            let count=Double((width-2)*(height-2))
            return .init(fingerprint:hash,edgeFraction:Double(edges)/count,detailEnergy:energy/count)
        }
    }
    struct Result {let usable:Bool;let reconnectReason:String?}
    private var lastFingerprint:UInt64?
    private var repeatedSince:Double?
    private var blurredSince:Double?
    private var lastTime:Double?
    private var repeats=0,blurredFrames=0
    mutating func observe(_ sample:Sample,at now:Double)->Result {
        guard now.isFinite,lastTime.map({now>$0}) ?? true else {return .init(usable:false,reconnectReason:nil)}
        if let lastTime,now-lastTime>2 {self=Self()}
        lastTime=now
        if lastFingerprint==sample.fingerprint {repeats+=1}
        else {lastFingerprint=sample.fingerprint;repeatedSince=now;repeats=1}
        if sample.severelyBlurred {
            if blurredSince==nil {blurredSince=now};blurredFrames+=1
        } else {blurredSince=nil;blurredFrames=0}
        if let blurredSince,blurredFrames>=3,now-blurredSince>=0.8 {
            return .init(usable:false,reconnectReason:"Camera feed is severely blurred")
        }
        if let repeatedSince,repeats>=4,now-repeatedSince>=1.5 {
            return .init(usable:false,reconnectReason:"Camera image is frozen")
        }
        return .init(usable:!sample.severelyBlurred,reconnectReason:nil)
    }
}
