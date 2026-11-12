import Foundation

/// One ordered writer for a recording's SGF, pending history, reviews and clocks.
/// Snapshots are captured by the owner; encoding and filesystem work run here.
/// The first failure stops subsequent writes until an explicit retry, so a failed
/// SGF write cannot be followed by sidecars describing a different game revision.
final class RecordingStorage: @unchecked Sendable {
    enum Component { case game, pending, reviews, clock }
    struct Failure: LocalizedError {
        let id = UUID()
        let message: String
        var component: Component = .game
        var errorDescription: String? { message }
    }
    private let queue = DispatchQueue(label: "PhysicalGo.recording-storage", qos: .utility)
    private let lock = NSLock()
    // Mutable work is read and replaced only under the enclosing writer lock.
    private final class Job: @unchecked Sendable {
        let key:String?
        var work:() throws -> Void
        init(key:String?,work:@escaping () throws -> Void) {self.key=key;self.work=work}
    }
    private var lastQueued:Job?
    private var pending = 0
    private var failure: Failure?
    private let capacity: Int
    @MainActor var onFailure: ((Failure) -> Void)?
    init(capacity: Int = 256) { self.capacity = capacity }

    var currentFailure: Failure? { lock.lock(); defer { lock.unlock() }; return failure }
    var error: String? { currentFailure?.message }

    @MainActor func submit(_ label: String, component: Component = .game, coalescingKey:String? = nil, work: @escaping () throws -> Void) throws {
        lock.lock()
        if let failure { lock.unlock(); throw failure }
        // Replace only the tail job, before it starts. An intervening game or
        // clock write is an ordering barrier and can never be skipped over.
        if let key=coalescingKey,let lastQueued,lastQueued.key==key {
            lastQueued.work=work;lock.unlock();return
        }
        guard pending < capacity else {
            lock.unlock()
            let problem = Failure(message: "Recording storage is falling behind. Pause and retry saving.")
            fail(problem, notify: onFailure)
            throw problem
        }
        let job=Job(key:coalescingKey,work:work)
        lastQueued=job;pending += 1
        lock.unlock()
        let notify = onFailure
        queue.async { [self] in
            lock.lock()
            let work=job.work
            if lastQueued === job {lastQueued=nil}
            lock.unlock()
            defer { lock.lock(); pending -= 1; lock.unlock() }
            guard error == nil else { return }
            do { try work() }
            catch { fail(Failure(message: "Could not save \(label): \(error.localizedDescription)", component: component), notify: notify) }
        }
    }
    private func fail(_ problem: Failure, notify: ((Failure) -> Void)?) {
        lock.lock()
        let first = failure == nil
        if first { failure = problem }
        lock.unlock()
        if first { DispatchQueue.main.async { [weak self] in
            guard self?.currentFailure?.id == problem.id else {return}
            notify?(problem)
        } }
    }
    /// Explicit durability boundary only: shutdown, session replacement, or a
    /// paused edit that must be saved before it is published. Never called by
    /// camera observations, turn recognition, or the clock timer.
    func flush() throws {
        queue.sync {}
        if let failure = currentFailure { throw failure }
    }
    func retry() { queue.sync { lock.lock(); failure = nil; lock.unlock() } }
    /// Reads and paused file operations share ordering with previously queued saves.
    func perform<T>(_ work: () throws -> T) rethrows -> T { try queue.sync(execute: work) }
}

/// Optional observation diagnostics never delay the durable game writer. When
/// storage is slow, omit diagnostic rows rather than accumulate unlimited images
/// or dictionaries. All handle operations, JSON encoding and deletion are serial.
final class RecordingJournal: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PhysicalGo.observation-journal", qos: .utility)
    private let lock = NSLock()
    private var pending = 0
    private var handle: FileHandle?
    private var failed = false
    let url: URL
    init(url: URL, append: Bool, createIfMissing: Bool, onError: @escaping (String) -> Void) {
        self.url = url
        queue.async { [self] in
            do {
                let exists = FileManager.default.fileExists(atPath: url.path)
                if append && !createIfMissing && !exists { return }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !append || !exists { try Data().write(to: url, options: .atomic) }
                handle = try FileHandle(forWritingTo: url)
                if append { try handle?.seekToEnd() }
            } catch { failed = true; DispatchQueue.main.async { onError(error.localizedDescription) } }
        }
    }
    func ensureOpen(onError: @escaping (String) -> Void) {
        queue.async { [self] in
            guard handle == nil, !failed else {return}
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath:url.path) {try Data().write(to:url,options:.atomic)}
                handle = try FileHandle(forWritingTo:url);try handle?.seekToEnd()
            } catch {failed=true;DispatchQueue.main.async {onError(error.localizedDescription)}}
        }
    }
    func append(_ entry: [String: Any], onError: @escaping (String) -> Void) {
        lock.lock()
        guard pending < 32 else { lock.unlock(); return }
        pending += 1; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            guard !failed, let handle else { return }
            do {
                var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]); data.append(10)
                try handle.write(contentsOf: data)
            } catch { failed = true; DispatchQueue.main.async { onError(error.localizedDescription) } }
        }
    }
    func close() { queue.async { [self] in try? handle?.close(); handle = nil } }
    func discard() throws {
        try queue.sync {
            try handle?.close(); handle = nil
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    func flush() { queue.sync {} }
}
