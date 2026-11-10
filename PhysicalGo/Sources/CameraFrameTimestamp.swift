import AVFoundation

struct CameraFrameTimestamp:Codable {
    let capturedAt:Double
    let arrivedAt:Double
    let source:String
    let presentationSeconds:Double?
    static func make(_ sample:CMSampleBuffer,clock:CMClock?,arrival:Double)->Self {
        let pts=CMSampleBufferGetPresentationTimeStamp(sample)
        if let clock,pts.isValid,!pts.isIndefinite {
            let host=CMClockGetHostTimeClock()
            let converted=CMSyncConvertTime(pts,from:clock,to:host)
            let hostNow=CMClockGetTime(host)
            let age=CMTimeGetSeconds(CMTimeSubtract(hostNow,converted))
            let uptime=ProcessInfo.processInfo.systemUptime
            if age.isFinite,age>=0,age<1.5 {
                return .init(capturedAt:uptime-age,arrivedAt:arrival,source:"cameraPresentation",presentationSeconds:CMTimeGetSeconds(pts))
            }
        }
        return .init(capturedAt:arrival,arrivedAt:arrival,source:"callback",presentationSeconds:pts.isValid && !pts.isIndefinite ? CMTimeGetSeconds(pts):nil)
    }
}
