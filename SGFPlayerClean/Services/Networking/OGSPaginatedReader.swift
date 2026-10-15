import Foundation

/// Fetches one complete snapshot at a time. A failed page never becomes a partial success.
/// Methods and completions use the main queue, like OGSConnectionController.
final class OGSPaginatedReader<Item: Decodable> {
    private let transport: OGSHTTPTransport
    private let scheduler: OGSConnectionScheduler
    private let now: () -> Date
    private let maximumPages: Int
    private var generation = 0
    private var task: OGSCancellable?
    private var nextPage: OGSCancellable?
    private var completion: ((Result<[Item], Error>) -> Void)?
    private var rootRequest: URLRequest?
    private var visited: Set<URL> = []
    private var accumulated: [Item] = []
    private var throttleCount = 0
    private(set) var retryNotBefore: Date = .distantPast
    var isLoading: Bool { completion != nil }

    init(transport: OGSHTTPTransport, scheduler: OGSConnectionScheduler = OGSMainQueueScheduler(),
         now: @escaping () -> Date = Date.init, maximumPages: Int = 100) {
        self.transport = transport
        self.scheduler = scheduler
        self.now = now
        self.maximumPages = maximumPages
    }

    /// Returns false while a snapshot is in flight or a server-directed cooldown is active.
    @discardableResult
    func load(_ request: URLRequest, completion: @escaping (Result<[Item], Error>) -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isLoading, now() >= retryNotBefore else { return false }
        generation += 1
        rootRequest = request
        self.completion = completion
        guard let url = request.url else { finish(.failure(OGSHTTPError.invalidPagination)); return true }
        fetch(url, generation: generation)
        return true
    }

    /// Cancelled snapshots are discarded; observers receive no stale/partial result.
    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation += 1
        task?.cancel(); task = nil
        nextPage?.cancel(); nextPage = nil
        completion = nil
        rootRequest = nil
        visited.removeAll()
        accumulated.removeAll()
        // Preserve Retry-After even across disconnect/reconnect.
    }

    private func fetch(_ url: URL, generation token: Int) {
        guard generation == token, isLoading, var request = rootRequest,
              let root = request.url else { return }
        guard url.scheme == root.scheme, url.host == root.host, url.port == root.port,
              url.user == nil, url.password == nil, visited.count < maximumPages,
              visited.insert(url).inserted else {
            finish(.failure(OGSHTTPError.invalidPagination))
            return
        }
        request.url = url
        task = transport.get(request) { [weak self] result in
            guard let self, self.generation == token, self.isLoading else { return }
            self.task = nil
            do {
                let response = try result.get()
                if [429, 503].contains(response.response.statusCode) {
                    self.throttleCount = min(self.throttleCount + 1, 5)
                    let delay = response.retryDelay(now: self.now()) ?? min(30 * pow(2, Double(self.throttleCount - 1)), 300)
                    self.retryNotBefore = self.now().addingTimeInterval(delay)
                }
                let data = try response.validatedData()
                let page: Page
                if let list = try? JSONDecoder().decode([Item].self, from: data) {
                    page = Page(results: list, next: nil)
                } else {
                    page = try JSONDecoder().decode(Page.self, from: data)
                }
                self.accumulated.append(contentsOf: page.results)
                if let next = page.next {
                    guard !next.isEmpty, let nextURL = URL(string: next, relativeTo: url)?.absoluteURL else {
                        throw OGSHTTPError.invalidPagination
                    }
                    self.nextPage = self.scheduler.schedule(after: 1) { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.nextPage = nil
                        self.fetch(nextURL, generation: token)
                    }
                } else {
                    self.throttleCount = 0
                    self.finish(.success(self.accumulated))
                }
            } catch { self.finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<[Item], Error>) {
        let callback = completion
        cancel()
        callback?(result)
    }

    private struct Page: Decodable {
        let results: [Item]
        let next: String?
    }

    deinit { task?.cancel(); nextPage?.cancel() }
}
