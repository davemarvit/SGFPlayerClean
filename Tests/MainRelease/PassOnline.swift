import SwiftUI
import Vision
@testable import SGF_Player_OGS_Review

private func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
private func require(_ ok: @autoclosure () -> Bool, _ message: String) { if !ok() { fail(message) } }

private final class PlayHTTP: URLProtocol {
    static var pendingChallenge: PlayHTTP?
    func finishChallenge() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"challenge_id":51,"game":52}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body: String
        var status = 200
        if path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/v1/challenges",
           request.httpMethod == "POST" { Self.pendingChallenge = self; return }
        if path == "/api/v1/ui/config" {
            body = #"{"user":{"id":99,"username":"TestingAccount","ranking":25},"user_jwt":"fixture"}"#
        } else if path.hasSuffix("/sgf") {
            status = 503; body = "{}"
        } else if path.contains("/games/") {
            let id = Int(path.split(separator: "/").last!) ?? 9
            body = "{\"id\":\(id),\"width\":9,\"height\":9,\"phase\":\"play\",\"rules\":\"japanese\",\"komi\":6.5,\"initial_player\":\"black\",\"moves\":[],\"players\":{\"black\":{\"id\":99,\"username\":\"TestingAccount\"},\"white\":{\"id\":98,\"username\":\"Opponent\"}}}"
        } else { body = "{\"results\":[],\"next\":null}" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class PlaySocket: OGSWebSocket {
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    var receiver: ((Result<String, Error>) -> Void)?
    var messages: [String] = []
    func resume() {}
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion }
    func send(_ text: String, completion: @escaping (Error?) -> Void) { messages.append(text); completion(nil) }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() {}
}

@main struct PassOnlineCheck {
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        UserDefaults.standard.set("/nonexistent/disabled", forKey: "customKataGoPath")
        AppSettings.shared.folderURL = nil
        AppSettings.shared.isMuted = true
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlayHTTP.self]; config.httpCookieStorage = nil
        let socket = PlaySocket()
        let client = OGSClient(session: URLSession(configuration: config, delegate: nil, delegateQueue: .main), socketFactory: { socket })
        let app = AppModel(ogsClient: client)
        defer { client.disconnect(); KataGoEngine.shared.stop() }
        func settle() async { try? await Task.sleep(nanoseconds: 250_000_000) }
        await settle(); app.mode = .playOnline
        socket.onOpen?(); client.isSocketAuthenticated = true
        app.resumeOnlineGame(id: 9); await settle()
        let vm = app.boardVM!
        require(vm.onlineMoveUnavailableReason == nil, "Fixture accepts online moves")
        vm.passOnline(); await settle()
        require(vm.passAnnouncement?.text == "Black passes", "Own optimistic online pass appears")
        let firstID = vm.passAnnouncement!.id
        NotificationCenter.default.post(client.makeGameNotification(name: Notification.Name("OGSMoveReceived"),
            userInfo: ["game_id": 9, "move_number": 1, "player_id": 99, "move": [-1, -1]]))
        await settle()
        require(vm.passAnnouncement?.id == firstID, "Server echo does not repeat own pass")
        NotificationCenter.default.post(client.makeGameNotification(name: Notification.Name("OGSMoveReceived"),
            userInfo: ["game_id": 9, "move_number": 2, "player_id": 98, "move": [-1, -1]]))
        await settle()
        require(vm.passAnnouncement?.text == "White passes", "Opponent pass appears")
        let secondID = vm.passAnnouncement!.id
        NotificationCenter.default.post(client.makeGameNotification(name: Notification.Name("OGSMoveReceived"),
            userInfo: ["game_id": 9, "move_number": 2, "player_id": 98, "move": [-1, -1]]))
        await settle()
        require(vm.passAnnouncement?.id == secondID, "Duplicate opponent event does not repeat pass")
        require(vm.reviewEndResult == nil, "Two online passes do not fabricate a final score")
        require(socket.messages.filter { $0.contains("game/move") }.count == 1, "Exactly one authorized online pass sent")
        print("PASS: own online pass, server echo, opponent pass, duplicate events and authoritative result gate")
    }
}
