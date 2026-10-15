import SwiftUI
import Vision
@testable import SGF_Player_Offline_Review

/// Render the compiled scoring UI and read the resulting pixels, catching clipped winner
/// text and inconsistent decimal formatting as well as checking the fixture values.
@main struct ScoringDisplayCheck {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.offline-ui-probe")
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: "/private/tmp/sgf-scoring-display", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failures: [String] = []
        func check(_ success: Bool, _ message: String) {
            if !success { failures.append(message) }
        }
        func compact(_ value: String) -> String {
            value.filter { !$0.isWhitespace }.lowercased()
        }
        func recognize(_ image: CGImage) throws -> String {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            return compact((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " "))
        }
        @MainActor func render<V: View>(_ view: V, _ name: String) throws -> CGImage {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ScoringDisplay", code: 1)
            }
            try data.write(to: output.appendingPathComponent(name + ".png"))
            return image
        }
        let cases: [(OfflineScoringExample, String?)] = [
            (.whiteWin, "Alice [White] wins by 6.5 points"),
            (.blackWin, "Dave [Black] wins by 1 point"),
            (.draw, "Draw"),
            (.fractional, "Alice [White] wins by 6.25 points"),
            (.missingScore, nil)
        ]
        for (index, fixture) in cases.enumerated() {
            let (example, expected) = fixture
            let score = example.summary
            let winner = score?.winnerDescription(blackName: "Dave", whiteName: "Alice")
            check(winner == expected, "Incorrect winner for \(example)")
            let panel = OGSScoringPanel(finished: true, connected: false, participant: false,
                atLivePosition: true, canEdit: false, acceptance: .none, strictSeki: false,
                summary: score, winnerDescription: winner, error: nil, accept: {}, resume: {})
                .frame(width: 330).padding(16).background(Color(nsColor: .windowBackgroundColor))
            let text = try recognize(render(panel, "panel-\(index)"))
            check(text.contains("finalscore"), "Missing Final Score heading for \(example)")
            if let expected { check(text.contains(compact(expected)), "Winner text is missing or clipped for \(example): \(text)") }
            else { check(text.contains("nonumericscore"), "Missing explanation for absent scores") }
            if example == .fractional {
                check(text.contains("35.25"), "Score table must retain two decimals, consistent with the winner margin")
            }
        }
        let longName = "Alexandra Montgomery"
        // Exercise rendered rows at the actual sidebar width, including explicit
        // server overrides and unknown rules. Inapplicable fields are deliberately
        // nonzero to ensure visibility follows rules rather than numeric guesses.
        let ruleScore = OGSScoreSummary.parse([
            "black": ["total": 20, "territory": 10, "stones": 8, "prisoners": 2, "komi": 0, "handicap": 0],
            "white": ["total": 26.5, "territory": 10, "stones": 8, "prisoners": 2, "komi": 6.5, "handicap": 3]
        ])!
        let ruleCases: [(GameAnalysisSettings, Bool, Bool, Bool, Bool)] = [
            (.init(rules: "japanese"), true, false, true, false),
            (.init(rules: "korean"), true, false, true, false),
            (.init(rules: "chinese", online: true), true, true, false, true),
            (.init(rules: "aga"), true, true, false, true),
            (.init(rules: "nz"), true, true, false, false),
            (.init(rules: "tromp-taylor"), true, true, false, false),
            (.init(rules: "custom"), true, true, true, true),
            (.init(), true, true, true, true),
            (.init(rules: "japanese", whiteHandicapBonus: "N", ruleOverrides:
                GoRuleOverrides(scoreTerritory: false, scoreStones: true, scorePrisoners: false)), false, true, false, true),
            (.init(rules: "chinese", whiteHandicapBonus: "0"), true, true, false, false)
        ]
        for (index, entry) in ruleCases.enumerated() {
            let (settings, territory, stones, prisoners, handicap) = entry
            let panel = OGSScoringPanel(finished: true, connected: false, participant: false,
                atLivePosition: true, canEdit: false, acceptance: .none, strictSeki: false,
                summary: ruleScore, scoringSettings: settings, error: nil, accept: {}, resume: {})
                .frame(width: 320).padding(16).background(Color(nsColor: .windowBackgroundColor))
            let text = try recognize(render(panel, "rules-\(index)"))
            check(text.contains("territory") == territory, "Territory row mismatch: \(settings)")
            check(text.contains("stones") == stones, "Stones row mismatch: \(settings)")
            check(text.contains("prisoners") == prisoners, "Prisoners row mismatch: \(settings)")
            check(text.contains("handicapcompensation") == handicap, "Handicap row missing, clipped or inapplicable: \(settings): \(text)")
            check(text.contains("26.5"), "Server total changed for \(settings)")
        }
        let noHandicapScore = OGSScoreSummary.parse([
            "black": ["total": 20, "handicap": 0], "white": ["total": 26.5, "handicap": 0]
        ])!
        let noHandicapPanel = OGSScoringPanel(finished: true, connected: false, participant: false,
            atLivePosition: true, canEdit: false, acceptance: .none, strictSeki: false,
            summary: noHandicapScore, scoringSettings: .init(rules: "chinese"), error: nil, accept: {}, resume: {})
            .frame(width: 320).padding(16).background(Color(nsColor: .windowBackgroundColor))
        check(try !recognize(render(noHandicapPanel, "no-handicap")).contains("handicap"), "Zero handicap row should be hidden")
        let score = OfflineScoringExample.whiteWin.summary!
        let longPanel = OGSScoringPanel(finished: true, connected: false, participant: false,
            atLivePosition: false, canEdit: false, acceptance: .none, strictSeki: false,
            summary: score, winnerDescription: score.winnerDescription(blackName: "Dave", whiteName: longName),
            error: nil, accept: {}, resume: {})
            .frame(width: 330).padding(16).background(Color(nsColor: .windowBackgroundColor))
        let longText = try recognize(render(longPanel, "long-name-earlier-position"))
        check(longText.contains(compact(longName + " [White] wins by 6.5 points")), "Long winner name is clipped")
        check(longText.contains("earlierposition"), "Earlier-position notice is missing")
        // ImageRenderer cannot draw native macOS controls or ScrollView contents. Host the
        // complete sheet in a real window to verify the user can actually see the panel.
        let host = NSHostingView(rootView: OfflineScoringReview()
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 560, height: 610),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Offline scoring check"
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("review-window.png"))
        let windowText = try recognize(bitmap.cgImage!)
        check(windowText.contains("finalscore"), "Score panel is not visible in the review window")
        check(windowText.contains("alice[white]winsby6.5points"), "Winner is not visible in the review window")
        check(windowText.contains("done") && windowText.contains("example"), "Review controls are not visible")
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: Scoring pixels show rule-specific rows, server overrides, unknown-rule fallback, hidden zero handicap, full compensation label, unchanged totals, both winners, singular/plural points, draw, missing-score explanation, fractional totals, long names, and earlier-position notice. Images: \(output.path)")
    }
}
