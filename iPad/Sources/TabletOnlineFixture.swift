#if DEBUG
import Foundation

/// In-process server used only by explicitly selected tests. It never opens a real socket.
@MainActor final class TabletOnlineFixture {
    static var current: TabletOnlineFixture?
    var authenticated = false
    var observingFixture = false
    var blackRankData: [String: Any] = ["ranking": 32]
    var whiteRankData: [String: Any] = ["ranking": 30]
    var moves: [[Int]] = []
    var stateVersion = 1
    var phase = "play"
    var echoMoves = true
    var sent: [String] = []
    var requests: [String] = []
    var sockets: [TabletFixtureSocket] = []
    var removed = ""
    var session: URLSession!
    lazy var client: OGSClient = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TabletFixtureHTTP.self]
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        self.session = session
        TabletFixtureHTTP.handler = { [weak self] request in self?.reply(request) }
        return OGSClient(session: session, socketFactory: { [weak self] in
            let socket = TabletFixtureSocket(); socket.server = self
            self?.sockets.append(socket); return socket
        })
    }()
    var snapshot: [String: Any] {
        ["game_id": 7001, "width": 9, "height": 9, "moves": moves, "state_version": stateVersion,
         "rules": "japanese", "komi": 6.5, "phase": phase, "ranked": false,
         "players": ["black": ["id": observingFixture ? 303 : 101, "username": observingFixture ? "Observed black" : "iPad test player"].merging(blackRankData) { _, rank in rank }, "white": ["id": 202, "username": "Test opponent"].merging(whiteRankData) { _, rank in rank }],
         "clock": ["black_time": ["thinking_time": 600], "white_time": ["thinking_time": 600], "current_player": moves.count % 2 == 0 ? (observingFixture ? 303 : 101) : 202],
         "removed": removed]
    }
    func reply(_ request: TabletFixtureHTTP) {
        let path = request.request.url!.path
        requests.append("\(request.request.httpMethod ?? "GET") \(path)")
        if path == "/api/v0/login" { authenticated = true; request.respond([:]) }
        else if path == "/api/v1/ui/config" {
            request.respond(authenticated ? ["user": ["id": 101, "username": "iPad test player"], "user_jwt": "fixture-token"] : [:])
        } else if path == "/api/v1/games/7001" { request.respond(["gamedata": snapshot]) }
        else if path == "/api/v1/challenges" && request.request.httpMethod == "POST" { request.respond(["id":9001,"game_id":7001]) }
        else if path == "/api/v1/challenges/9001/accept" { request.respond(["game_id":7001]) }
        else if path.contains("challenges") { request.respond(["results": [], "next": NSNull()]) }
        else { request.respond([:], status: 404) }
    }
    func received(_ text: String, socket: TabletFixtureSocket) {
        sent.append(text)
        guard text.hasPrefix("42"), let start = text.firstIndex(of: "["),
              let array = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [Any],
              let event = array.first as? String else { return }
        let payload = array.count > 1 ? (array[1] as? [String: Any] ?? [:]) : [:]
        if event == "authenticate" { socket.event("authenticated", [:]); socket.event("active_game", ["game_id": 7001, "phase": "play", "black_id": 101, "white_id": 202]) }
        if event == "gamelist/query" {
            let ack = String(text[text.index(text.startIndex, offsetBy: 2)..<start])
            let rows: [[String: Any]] = [["id": 7001, "width": 9, "height": 9,
                "black": ["username": "Observed black", "ranking": 32],
                "white": ["username": "Test opponent", "ranking": 30],
                "json": ["moves": moves, "time_control": ["system": "absolute", "total_time": 600]]]]
            let data = try! JSONSerialization.data(withJSONObject: [["size": 1, "results": rows]])
            socket.deliver("43" + ack + String(decoding: data, as: UTF8.self))
        }
        if event == "game/connect" { socket.event("game/7001/gamedata", snapshot) }
        if event == "game/move", echoMoves, let move = payload["move"] as? String {
            let point = move == ".." ? (-1,-1) : SGFCoordinates.parse(move)!
            appendMove(x: point.0, y: point.1)
        }
        if event == "game/chat" { socket.event("game/7001/chat", ["line": ["username": "iPad test player", "body": payload["body"] ?? "", "date": Int(Date().timeIntervalSince1970)]]) }
        if event == "game/removed_stones/set" { removed = payload["stones"] as? String ?? ""; socket.event("game/7001/removed_stones", ["stones": removed, "removed": true]) }
        if event == "game/removed_stones/accept" { socket.event("game/7001/removed_stones_accepted", ["player_id": 101, "stones": removed, "strict_seki_mode": false]) }
        if event == "game/removed_stones/reject" { phase = "play"; socket.event("game/7001/phase", "play") }
    }
    func appendMove(x: Int, y: Int) {
        let player = moves.count % 2 == 0 ? (observingFixture ? 303 : 101) : 202
        moves.append([x,y]); stateVersion += 1
        sockets.last?.event("game/7001/move", ["move": [x,y], "move_number": moves.count, "player_id": player, "state_version": stateVersion])
    }
    func close() { client.disconnect(); session?.invalidateAndCancel(); TabletFixtureHTTP.handler = nil }
}

final class TabletFixtureSocket: OGSWebSocket {
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    weak var server: TabletOnlineFixture?
    private var receiver: ((Result<String, Error>) -> Void)?
    private var queued: [String] = []
    private var cancelled = false
    func resume() { DispatchQueue.main.async { [weak self] in guard let self, !self.cancelled else { return }; self.onOpen?(); self.deliver("40") } }
    func receive(_ completion: @escaping (Result<String, Error>) -> Void) { receiver = completion; flush() }
    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        completion(nil)
        DispatchQueue.main.async { [weak self] in guard let self, !self.cancelled else { return }; self.server?.received(text, socket: self) }
    }
    func ping(_ completion: @escaping (Error?) -> Void) { completion(nil) }
    func cancel() { cancelled = true; receiver = nil; queued = []; onOpen = nil; onClose = nil }
    func deliver(_ text: String) { guard !cancelled else { return }; queued.append(text); flush() }
    func event(_ name: String, _ value: Any) { let data = try! JSONSerialization.data(withJSONObject: [name,value]); deliver("42" + String(decoding: data, as: UTF8.self)) }
    private func flush() {
        guard !queued.isEmpty, let receiver, !cancelled else { return }
        self.receiver = nil
        let text = queued.removeFirst()
        DispatchQueue.main.async { receiver(.success(text)) }
    }
}
final class TabletFixtureHTTP: URLProtocol {
    static var handler: ((TabletFixtureHTTP) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { DispatchQueue.main.async { Self.handler?(self) } }
    override func stopLoading() {}
    func respond(_ body: [String: Any], status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
