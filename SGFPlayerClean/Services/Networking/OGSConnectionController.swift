import Foundation

protocol OGSCancellable {
    func cancel()
}

protocol OGSConnectionScheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> OGSCancellable
}

private final class ScheduledConnectionWork: OGSCancellable {
    let item: DispatchWorkItem
    init(_ action: @escaping () -> Void) { item = DispatchWorkItem(block: action) }
    func cancel() { item.cancel() }
}

struct OGSMainQueueScheduler: OGSConnectionScheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> OGSCancellable {
        let work = ScheduledConnectionWork(action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work.item)
        return work
    }
}

/// One socket attempt. Production callbacks can arrive on any queue.
protocol OGSWebSocket: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onClose: ((Error?) -> Void)? { get set }
    func resume()
    func receive(_ completion: @escaping (Result<String, Error>) -> Void)
    func send(_ text: String, completion: @escaping (Error?) -> Void)
    func ping(_ completion: @escaping (Error?) -> Void)
    func cancel()
}

enum OGSConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(delay: TimeInterval)
}

enum OGSConnectionError: LocalizedError {
    case closed, connectionTimeout, heartbeatTimeout, notConnected, invalidMessage

    var errorDescription: String? {
        switch self {
        case .closed: return "OGS connection closed"
        case .connectionTimeout: return "OGS connection timed out"
        case .heartbeatTimeout: return "OGS heartbeat timed out"
        case .notConnected: return "Not connected to OGS"
        case .invalidMessage: return "OGS sent an invalid WebSocket message"
        }
    }
}

/// Owns connection intent, one receive loop, bounded retry delays, and liveness.
/// Public operations and observers run on the main queue. Game commands are never replayed.
final class OGSConnectionController {
    var onStateChange: ((OGSConnectionState) -> Void)?
    var onMessage: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var state: OGSConnectionState = .disconnected

    private let makeSocket: () -> OGSWebSocket
    private let scheduler: OGSConnectionScheduler
    private var socket: OGSWebSocket?
    private var wantsConnection = false
    private var generation = 0
    private var retryCount = 0
    private var retry: OGSCancellable?
    private var deadline: OGSCancellable?
    private var heartbeat: OGSCancellable?
    private var heartbeatDeadline: OGSCancellable?

    init(scheduler: OGSConnectionScheduler = OGSMainQueueScheduler(),
         makeSocket: @escaping () -> OGSWebSocket) {
        self.scheduler = scheduler
        self.makeSocket = makeSocket
    }

    func connect() {
        dispatchPrecondition(condition: .onQueue(.main))
        wantsConnection = true
        guard socket == nil, retry == nil else { return }
        openSocket()
    }

    func disconnect() {
        dispatchPrecondition(condition: .onQueue(.main))
        wantsConnection = false
        retryCount = 0
        invalidateAttempt()
        setState(.disconnected)
    }

    func send(_ text: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .connected, let socket else {
            onError?(OGSConnectionError.notConnected)
            return
        }
        let attempt = generation
        socket.send(text) { [weak self] error in
            self?.onMain { owner in
                guard owner.isCurrent(attempt), let error else { return }
                owner.failed(error)
            }
        }
    }

    private func openSocket() {
        generation += 1
        let attempt = generation
        let socket = makeSocket()
        self.socket = socket
        setState(.connecting)
        guard isCurrent(attempt) else { return }
        socket.onOpen = { [weak self] in
            self?.onMain { owner in
                guard owner.isCurrent(attempt), owner.state == .connecting else { return }
                owner.deadline?.cancel()
                owner.deadline = nil
                owner.setState(.connected)
                if owner.isCurrent(attempt) { owner.scheduleHeartbeat(attempt: attempt) }
            }
        }
        socket.onClose = { [weak self] error in
            self?.onMain { owner in
                guard owner.isCurrent(attempt) else { return }
                owner.failed(error ?? OGSConnectionError.closed)
            }
        }
        deadline = scheduler.schedule(after: 15) { [weak self] in
            guard let self, self.isCurrent(attempt) else { return }
            self.failed(OGSConnectionError.connectionTimeout)
        }
        socket.resume()
        receive(from: socket, attempt: attempt)
    }

    private func receive(from socket: OGSWebSocket, attempt: Int) {
        socket.receive { [weak self, weak socket] result in
            self?.onMain { owner in
                guard owner.isCurrent(attempt), let socket else { return }
                switch result {
                case .success(let text):
                    owner.onMessage?(text)
                    // Observers may deliberately disconnect while handling a message.
                    if owner.isCurrent(attempt) { owner.receive(from: socket, attempt: attempt) }
                case .failure(let error):
                    owner.failed(error)
                }
            }
        }
    }

    private func scheduleHeartbeat(attempt: Int) {
        heartbeat = scheduler.schedule(after: 10) { [weak self] in
            guard let self, self.isCurrent(attempt), let socket = self.socket else { return }
            self.heartbeatDeadline = self.scheduler.schedule(after: 10) { [weak self] in
                guard let self, self.isCurrent(attempt) else { return }
                self.failed(OGSConnectionError.heartbeatTimeout)
            }
            socket.ping { [weak self] error in
                self?.onMain { owner in
                    guard owner.isCurrent(attempt) else { return }
                    owner.heartbeatDeadline?.cancel()
                    owner.heartbeatDeadline = nil
                    if let error {
                        owner.failed(error)
                    } else {
                        // Only a responsive connection resets backoff; opening alone is insufficient.
                        owner.retryCount = 0
                        owner.scheduleHeartbeat(attempt: attempt)
                    }
                }
            }
        }
    }

    private func failed(_ error: Error) {
        invalidateAttempt()
        guard wantsConnection else { return }
        retryCount = min(retryCount + 1, 6)
        let delay = min(pow(2, Double(retryCount - 1)), 30)
        let attempt = generation
        retry = scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.wantsConnection, self.generation == attempt else { return }
            self.retry = nil
            self.openSocket()
        }
        setState(.reconnecting(delay: delay))
        onError?(error)
    }

    private func invalidateAttempt() {
        generation += 1
        retry?.cancel(); retry = nil
        deadline?.cancel(); deadline = nil
        heartbeat?.cancel(); heartbeat = nil
        heartbeatDeadline?.cancel(); heartbeatDeadline = nil
        let oldSocket = socket
        socket = nil
        oldSocket?.onOpen = nil
        oldSocket?.onClose = nil
        oldSocket?.cancel()
    }

    private func isCurrent(_ attempt: Int) -> Bool {
        wantsConnection && generation == attempt && socket != nil
    }

    private func setState(_ state: OGSConnectionState) {
        self.state = state
        onStateChange?(state)
    }

    private func onMain(_ action: @escaping (OGSConnectionController) -> Void) {
        if Thread.isMainThread { action(self) }
        else { DispatchQueue.main.async { [weak self] in if let self { action(self) } } }
    }

    deinit {
        retry?.cancel()
        deadline?.cancel()
        heartbeat?.cancel()
        heartbeatDeadline?.cancel()
        socket?.cancel()
    }
}
