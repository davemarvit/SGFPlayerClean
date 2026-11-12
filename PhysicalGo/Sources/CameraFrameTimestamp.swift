import AVFoundation

struct CameraFrameTimestamp:Codable {
    let capturedAt:Double
    let arrivedAt:Double
    let source:String
    let presentationSeconds:Double?
    static func make(_ sample:CMSampleBuffer,clock:CMClock?,arrival:Double)->Self {
        let pts=CMSampleBufferGetPresentationTimeStamp(sample)
        if let clock,pts.isNumeric {
            let host=CMClockGetHostTimeClock()
            let converted=CMSyncConvertTime(pts,from:clock,to:host)
            let hostNow=CMClockGetTime(host)
            let age=CMTimeGetSeconds(CMTimeSubtract(hostNow,converted))
            let uptime=ProcessInfo.processInfo.systemUptime
            // A delayed frame remains old. Replacing a valid stale capture
            // time with callback arrival would defeat downstream freshness gates.
            if age.isFinite,age>=0 {
                return .init(capturedAt:uptime-age,arrivedAt:arrival,source:"cameraPresentation",presentationSeconds:CMTimeGetSeconds(pts))
            }
        }
        return .init(capturedAt:arrival,arrivedAt:arrival,source:"callback",presentationSeconds:pts.isNumeric ? CMTimeGetSeconds(pts):nil)
    }
}
