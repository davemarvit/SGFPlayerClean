import Foundation
import AppKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private final class CountdownHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ClockCountdownCheck {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppSettings.shared.isMuted = true // No audible test sounds.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountdownHTTP.self]; config.httpCookieStorage = nil
        let client = OGSClient(session: URLSession(configuration: config))
        defer { client.disconnect() }
        // Finish the initial anonymous identity response before seeding game clocks.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        client.blackPlayerID = 1; client.whitePlayerID = 2
        client.connectToGame(gameID: 7) // Starts the real local clock timer; no socket is connected.
        for player in [1, 2] {
            for overtime in [false, true] {
                for (remaining, expected) in [(3.9, 4), (3.0, 3), (1.9, 2), (1.0, 1)] {
                    client.currentPlayerID = player
                    client.blackTimeRemaining = overtime ? 0 : remaining
                    client.whiteTimeRemaining = overtime ? 0 : remaining
                    client.blackClockPeriods = 5; client.whiteClockPeriods = 5
                    client.blackClockPeriodTime = remaining; client.whiteClockPeriodTime = remaining
                    SoundManager.shared.playCountdown(remaining: 60) // Fresh countdown sample.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.16))
                    let spoken = Mirror(reflecting: SoundManager.shared).children
                        .first { $0.label == "lastPlayedCountdown" }!.value as? Int
                    let clock = overtime
                        ? (player == 1 ? client.blackClockPeriodTime : client.whiteClockPeriodTime)!
                        : (player == 1 ? client.blackTimeRemaining : client.whiteTimeRemaining)!
                    require(clock < remaining && clock > remaining - 0.5, "Real timer advanced within expected interval: \(remaining) -> \(clock)")
                    require(spoken == expected, "Player \(player), overtime \(overtime), \(clock)s should announce \(expected), got \(String(describing: spoken))")
                }
            }
        }
        print("PASS: Real timer announces 4 near 3.9s, 3 near 3.0s, 2 near 1.9s, and 1 near 1.0s for both players in main time and byo-yomi. Network denied; audio muted.")
    }
}
