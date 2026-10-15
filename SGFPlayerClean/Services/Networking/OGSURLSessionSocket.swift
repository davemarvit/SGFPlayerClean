import Foundation

/// Keeps URLSession delegate callbacks tied to the socket that produced them.
final class OGSURLSessionSocket: NSObject, OGSWebSocket, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onClose: ((Error?) -> Void)?
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    init(request: URLRequest, cookieStorage: HTTPCookieStorage? = nil) {
        super.init()
        #if SGF_OGS_REVIEW
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookieStorage
        #else
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        #endif
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        task = session.webSocketTask(with: request)
    }

    func resume() { task?.resume() }

    func receive(_ completion: @escaping (Result<String, Error>) -> Void) {
        guard let task else { completion(.failure(OGSConnectionError.notConnected)); return }
        task.receive { result in
            completion(result.flatMap { message in
                switch message {
                case .string(let text): return .success(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { return .success(text) }
                    return .failure(OGSConnectionError.invalidMessage)
                @unknown default: return .failure(OGSConnectionError.invalidMessage)
                }
            })
        }
    }

    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        guard let task else { completion(OGSConnectionError.notConnected); return }
        task.send(.string(text), completionHandler: completion)
    }

    func ping(_ completion: @escaping (Error?) -> Void) {
        guard let task else { completion(OGSConnectionError.notConnected); return }
        task.sendPing(pongReceiveHandler: completion)
    }

    func cancel() {
        onOpen = nil
        onClose = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task else { return }
        onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        onClose?(OGSConnectionError.closed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task, let error else { return }
        onClose?(error)
    }
}
