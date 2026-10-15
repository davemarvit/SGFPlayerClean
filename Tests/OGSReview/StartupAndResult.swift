import SwiftUI
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private final class StartupHTTP: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        require(request.httpMethod == "GET", "Startup must not mutate a game")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct StartupAndResultCheck {
    @MainActor static func main() throws {
        require(Bundle.main.bundleIdentifier == "com.davemarvit.SGFPlayerClean.ogs-ui-probe", "Wrong fixture identity")
        NSApplication.shared.setActivationPolicy(.prohibited)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "folderURLBookmark")
        defaults.set("/nonexistent/katago-test-disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.isMuted = true
        func client() -> OGSClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StartupHTTP.self]; config.httpCookieStorage = nil
            return OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main))
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }

        // Separate processes exercise actual preference persistence, not just a
        // retained AppModel. Only the disposable probe domain is ever written.
        let args = CommandLine.arguments
        if args.count == 3, let expected = AppMode(rawValue: args[2]) {
            if args[1] == "write" {
                defaults.removeObject(forKey: "lastAppMode")
                defaults.set(false, forKey: "isOnlineModePersistent")
                let model = AppModel(ogsClient: client())
                model.mode = expected
                require(defaults.string(forKey: "lastAppMode") == expected.rawValue, "Mode not saved")
                defaults.synchronize()
                model.ogsClient.disconnect()
            } else {
                let model = AppModel(ogsClient: client(), defaultMode: .playOnline)
                settle()
                require(model.mode == expected, "Wrong restored tab: \(model.mode), expected \(expected)")
                require(model.isOnlineMode == expected.usesOGS, "Restored connection policy")
                require(model.ogsClient.observationOnly == (expected != .playOnline), "Restored participation policy")
                require(!model.isAIAvailable, "Startup must not enable AI")
                require(model.player.maxIndex == 0 && model.ogsClient.activeGameID == nil, "Startup invented a game")
                model.ogsClient.disconnect()
            }
            return
        }
        for mode in AppMode.allCases {
            for action in ["write", "read"] {
                let process = Process()
                process.executableURL = Bundle.main.executableURL
                process.arguments = [action, mode.rawValue]
                try process.run(); process.waitUntilExit()
                require(process.terminationStatus == 0, "Restart check failed: \(mode) \(action)")
            }
        }
        defaults.removeObject(forKey: "lastAppMode")
        defaults.set(false, forKey: "isOnlineModePersistent")
        let fresh = AppModel(ogsClient: client(), defaultMode: .playOnline)
        require(fresh.mode == .playOnline && !fresh.ogsClient.observationOnly, "Fresh OGS review defaults to Play Online")
        fresh.ogsClient.disconnect()
        defaults.set("obsolete-mode", forKey: "lastAppMode")
        defaults.set(true, forKey: "isOnlineModePersistent")
        let migrated = AppModel(ogsClient: client())
        require(migrated.mode == .playOnline, "Legacy online setting must migrate to Play Online")
        migrated.ogsClient.disconnect()

        // Both board renderers consume these same territory/dead-stone arrays.
        let ogs = client()
        ogs.activeGameID = 91
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text:
            "(;SZ[9]RU[Japanese]AB[ba][ab][cb][bc]AW[hh])")))
        let vm = BoardViewModel(player: player, ogsClient: ogs, isAIAllowed: { false })
        vm.isOnlineContext = true
        ogs.applyScoringSnapshot(["game_id": 91, "phase": "stone removal", "removed": "hh"])
        settle()
        require(!vm.territoryPoints.isEmpty && vm.stonesToRender.contains(where: \.isDead), "Fixture must show estimated scoring before resignation")
        let board = player.board
        ogs.applyScoringSnapshot(["game_id": 91, "phase": "finished", "outcome": "Resignation"])
        settle()
        require(vm.territoryPoints.isEmpty && !vm.territoryIsEstimate, "Resignation retained territory dots")
        require(vm.stonesToRender.allSatisfy { !$0.isDead }, "Resignation retained dead-stone shading")
        require(player.board == board, "Display cleanup changed the game")
        let score: [String: Any] = ["black": ["total": 4, "scoring_positions": "bb"],
                                    "white": ["total": 6.5, "scoring_positions": "ii"]]
        ogs.applyScoringSnapshot(["game_id": 91, "score": score])
        settle()
        require(vm.territoryPoints.isEmpty, "Late cached score revived resignation markers")
        ogs.applyScoringSnapshot(["game_id": 91, "outcome": "2.5 points", "score": score])
        settle()
        require(vm.territoryPoints == [BoardPosition(1, 1): .black, BoardPosition(8, 8): .white], "Scored results must retain server markers")
        require(!vm.territoryIsEstimate, "Server markers labeled as estimates")
        ogs.applyScoringSnapshot(["game_id": 91, "outcome": "Timeout"])
        settle()
        require(vm.territoryPoints.isEmpty && vm.stonesToRender.allSatisfy { !$0.isDead }, "Timeout retained scoring")
        ogs.disconnect()
        print("PASS: All four modes survive separate-process restart; defaults and legacy settings restore safely. Resignation/timeout clear territory and dead shading, late scores stay hidden, and scored results retain server markers.")
    }
}
