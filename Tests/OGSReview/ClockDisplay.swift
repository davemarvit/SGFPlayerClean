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
        // boundaries, overtime, and tenths below a minute. No clock state is changed.
        let cases: [(Double, String)] = [
            (756.4, "12:37"), (453.4, "7:34"), (756, "12:36"),
            (60.01, "1:01"), (60.0005, "1:00"), (60, "1:00"),
            (59.99, "1:00.0"), (59.9, "0:59.9"), (30, "0:30.0"), (29.2, "0:29.2"),
            (29.21, "0:29.3"), (1.01, "0:01.1"), (1, "0:01.0"), (0.2, "0:00.2"),
            (0.01, "0:00.1"), (0, "0:00.0"),
            (-1, "0:00.0"), (.nan, "--:--"), (.infinity, "--:--")
        ]
        for (seconds, expected) in cases {
            check(GameClockView.formattedTime(seconds) == expected, "\(seconds) should display \(expected)")
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        let host = NSHostingView(rootView: HStack(spacing: 30) {
            GameClockView(mainTime: 756.4, periods: 5, periodTime: 30, side: .left, isDark: false)
            GameClockView(mainTime: 43.4, periods: 5, periodTime: 30, side: .right, isDark: false)
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
        check(text.contains("12:37") && text.contains("0:43.4") && text.contains("0:29.2") && text.contains("0:30.0"), text)
        print("PASS: \(cases.count) fractional/boundary cases and rendered clocks show tenths below a minute in main time and byo-yomi, including the secondary period display. No network or clock state changes.")
    }
}
