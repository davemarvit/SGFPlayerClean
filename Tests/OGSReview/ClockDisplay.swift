import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct ClockDisplayCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        // Snapshot-like fractions from the reported main-time display, minute/second
        // boundaries, overtime, and the web client's 1 ms tolerance. No time is added.
        let cases: [(Double, String)] = [
            (756.4, "12:37"), (453.4, "7:34"), (756, "12:36"),
            (60.01, "1:01"), (60.0005, "1:00"), (60, "1:00"),
            (59.9, "1:00"), (30, "0:30"), (29.2, "0:30"),
            (1.01, "0:02"), (1, "0:01"), (0.2, "0:01"), (0, "0:00"),
            (-1, "0:00"), (.nan, "--:--"), (.infinity, "--:--")
        ]
        for (seconds, expected) in cases {
            check(GameClockView.formattedTime(seconds) == expected, "\(seconds) should display \(expected)")
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let host = NSHostingView(rootView: HStack(spacing: 30) {
            GameClockView(mainTime: 756.4, periods: 5, periodTime: 30, side: .left, isDark: false)
            GameClockView(mainTime: 453.4, periods: 5, periodTime: 30, side: .right, isDark: false)
            GameClockView(mainTime: 0, periods: 5, periodTime: 29.2, side: .right, isDark: false)
        }.padding().background(Color.white))
        window.contentView = host; window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        check(text.contains("12:37") && text.contains("7:34") && text.contains("0:30"), text)
        print("PASS: 16 fractional/boundary clock cases and rendered main-time/byoyomi clocks match OGS display rounding. No network or clock state changes.")
    }
}
