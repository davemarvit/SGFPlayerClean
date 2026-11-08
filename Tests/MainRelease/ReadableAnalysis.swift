import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct ReadableAnalysisCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: "/private/tmp/sgf-readable-analysis-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let summary = AIPositionSummary(root: AIRootInfo(winrate: 0.873, scoreLead: 12.5, visits: 500), playerToMove: .white)!
        for (name, width, scale) in [("standard", 368.0, 1.0), ("large-window", 650.0, 1.4), ("narrow-largest", 300.0, 2.24)] {
            let view = AIPositionReadout(summary: summary)
                .environment(\.interfaceTextScale, scale)
                .padding(16).frame(width: width, height: 420, alignment: .topLeading)
                .background(Color(white: 0.10)).preferredColorScheme(.dark)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host; window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            let results = request.results ?? []
            let strings = results.compactMap { $0.topCandidates(1).first?.string }
            require(strings.contains { $0.contains("White leads") }, "Leader visible: \(name): \(strings)")
            require(strings.contains { $0.contains("12.5") } && strings.contains { $0.contains("87.3%") }, "Both values visible: \(name): \(strings)")
            require(strings.contains { $0.contains("Point lead") } && strings.contains { $0.contains("Win probability") }, "Labels visible: \(name): \(strings)")
            let number = results.first { $0.topCandidates(1).first?.string.contains("12.5") == true }!
            let label = results.first { $0.topCandidates(1).first?.string.contains("Point lead") == true }!
            require(number.boundingBox.height > label.boundingBox.height * 1.5, "Values visibly dominate labels: \(name)")
            print("PASS \(name): \(strings)")
            window.orderOut(nil)
        }
        AppSettings.shared.interfaceTextScale = 1.5
        require(UserDefaults.standard.double(forKey: "interfaceTextScale") == 1.5, "Text size is saved")
        print("PASS readable analysis layouts and saved text size; previews: \(output.path)")
    }
}
