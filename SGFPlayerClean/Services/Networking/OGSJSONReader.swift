import Foundation

/// Latest-request-wins JSON reads for identity and game snapshots.
/// Cancellation completes the old caller once, and ignores any late network callback.
final class OGSJSONReader {
    private let transport: OGSHTTPTransport
    private var generation = 0
    private var task: OGSCancellable?
    private var completion: ((Result<[String: Any], Error>) -> Void)?

    init(transport: OGSHTTPTransport) { self.transport = transport }

    func load(_ request: URLRequest, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let token = generation + 1
        cancel()
        // A cancellation observer can itself start a newer request.
        guard generation == token else { completion(.failure(URLError(.cancelled))); return }
        self.completion = completion
        task = transport.get(request) { [weak self] result in
            guard let self, self.generation == token else { return }
            let parsed = result.flatMap { response -> Result<[String: Any], Error> in
                do {
                    let data = try response.validatedData()
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw OGSHTTPError.invalidJSON
                    }
                    return .success(json)
                } catch { return .failure(error) }
            }
            let callback = self.completion
            self.completion = nil
            self.task = nil
            self.generation += 1
            callback?(parsed)
        }
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation += 1
        let callback = completion
        completion = nil
        let oldTask = task
        task = nil
        oldTask?.cancel()
        callback?(.failure(URLError(.cancelled)))
    }

    deinit { task?.cancel() }
}
