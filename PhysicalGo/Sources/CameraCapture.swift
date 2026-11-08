import AVFoundation
import CoreImage
import OSLog

/// Public callbacks and start/stop are main-thread only; session state stays on queue.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private var currentOutput: AVCaptureVideoDataOutput?
    private let queue = DispatchQueue(label: "PhysicalGo.camera")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let logger = Logger(subsystem: "com.davemarvit.PhysicalGo", category: "Camera")
    private var lastFrame = 0.0
    private var lastPTS: CMTime?
    private var health = CameraHealth()
    private var timer: DispatchSourceTimer?
    private var deviceID = ""
    private var deviceName = "Camera"
    private var waitingForFirstFrame = true
    private var retryPending = false
    private var stream = 0
    private var request = 0 // main thread: rejects deliveries queued before Stop or a new Start.
    private var queueRequest = 0
    var onFrame: ((CGImage, Double) -> Void)?
    var onStatus: ((String, CameraState) -> Void)?
    private var observers = [NSObjectProtocol]()

    override init() {
        super.init()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                guard let source = note.object as? AVCaptureSession else { return }
                let error = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                self?.queue.async { [weak self] in
                    guard let self, source === self.session, self.health.active, !self.retryPending else { return }
                    let reason = error ?? (name == AVCaptureSession.interruptionEndedNotification ? "Camera interruption ended" : "Camera stream interrupted")
                    self.recover(reason: reason, force: true)
                }
            })
        }
    }
    deinit { timer?.cancel(); observers.forEach(NotificationCenter.default.removeObserver) }
    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
    }
    private func status(_ message: String, state: CameraState) {
        let token = queueRequest
        logger.notice("\(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.request == token else { return }
            self.onStatus?(message, state)
        }
    }
    func start(deviceID: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        request += 1
        let token = request
        queue.async { [weak self] in
            guard let self else { return }
            self.queueRequest = token; self.endSession(); self.health.stop()
            self.timer?.cancel(); self.timer = nil
            self.deviceID = deviceID
            let authorized: (Bool) -> Void = { [weak self] granted in
                guard let self else { return }
                self.queue.async {
                    guard token == self.queueRequest else { return }
                    guard granted else {
                        self.status("Camera access is off. Enable Physical Go in System Settings → Privacy & Security → Camera.", state: .failed)
                        return
                    }
                    self.health.start(now: ProcessInfo.processInfo.systemUptime)
                    self.installWatchdog()
                    self.configure()
                }
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: authorized)
            default: authorized(false)
            }
        }
    }
    private func installWatchdog() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now()+1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.recover(reason: "No fresh camera frames", force: false) }
        self.timer = timer; timer.resume()
    }
    private func endSession() {
        stream += 1
        retryPending = false
        currentOutput?.setSampleBufferDelegate(nil, queue: nil)
        currentOutput = nil
        let old = session; session = nil // Ignore notifications from the intentional teardown.
        old?.stopRunning()
    }
    private func configure() {
        guard health.active else { return }
        guard let device = Self.devices().first(where: { $0.uniqueID == deviceID }) else {
            status("Camera unavailable. Waiting to reconnect…", state: .recovering)
            return // Watchdog provides a bounded retry if a USB camera temporarily disappears.
        }
        deviceName = device.localizedName
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let captureSession = AVCaptureSession()
            session = captureSession
            captureSession.beginConfiguration()
            guard captureSession.canAddInput(input) else {
                captureSession.commitConfiguration(); fail("This camera input is unavailable."); return
            }
            captureSession.addInput(input)
            if captureSession.canSetSessionPreset(.hd1920x1080) { captureSession.sessionPreset = .hd1920x1080 }
            else { captureSession.sessionPreset = .high }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            guard captureSession.canAddOutput(output) else {
                captureSession.commitConfiguration(); fail("This camera format is unavailable."); return
            }
            captureSession.addOutput(output); currentOutput = output
            output.setSampleBufferDelegate(self, queue: queue)
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
            }
            captureSession.commitConfiguration()
            lastFrame = 0; lastPTS = nil; waitingForFirstFrame = true
            status("Waiting for frames · \(deviceName)", state: .starting)
            captureSession.startRunning()
            // Live is reported only from a successfully converted, advancing camera frame.
        } catch {
            logger.error("Camera configuration failed: \(error.localizedDescription, privacy: .public)")
            status("Could not open camera; retrying…", state: .recovering)
        }
    }
    private func recover(reason: String, force: Bool) {
        guard !retryPending else { return }
        switch health.check(now: ProcessInfo.processInfo.systemUptime, force: force) {
        case .none: return
        case .failed:
            fail("Camera stopped delivering frames. Close other camera apps, then choose Restart camera.")
        case .restart(let attempt):
            endSession(); retryPending = true
            status("\(reason). Reconnecting (\(attempt)/2)…", state: .recovering)
            let token = queueRequest, expectedStream = stream
            queue.asyncAfter(deadline: .now()+0.75) { [weak self] in
                guard let self, self.queueRequest == token, self.stream == expectedStream, self.health.active else { return }
                self.retryPending = false; self.configure()
            }
        }
    }
    private func fail(_ message: String) {
        health.stop(); timer?.cancel(); timer = nil; endSession()
        status(message, state: .failed)
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        request += 1
        let token = request
        queue.async { [weak self] in
            guard let self else { return }
            self.queueRequest = token; self.health.stop(); self.timer?.cancel(); self.timer = nil; self.endSession()
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === currentOutput, health.active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastFrame >= 0.2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if pts.isValid && !pts.isIndefinite, let previous = lastPTS, CMTimeCompare(pts, previous) <= 0 { return }
        let ci = CIImage(cvPixelBuffer: buffer)
        // Detach CGImage storage from the camera's buffer pool before retaining it in the UI.
        guard let image = context.createCGImage(ci, from: ci.extent, format: .BGRA8,
            colorSpace: CGColorSpaceCreateDeviceRGB(), deferred: false) else { return }
        lastFrame = now
        if pts.isValid && !pts.isIndefinite { lastPTS = pts }
        health.receivedFrame(now: now)
        if waitingForFirstFrame { waitingForFirstFrame = false; status("Live · \(deviceName)", state: .live) }
        let token = queueRequest
        DispatchQueue.main.async { [weak self] in
            guard let self, self.request == token else { return }
            self.onFrame?(image, now)
        }
    }
}
