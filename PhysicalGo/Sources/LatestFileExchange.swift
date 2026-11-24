import Foundation

/// A bounded file exchange: one read and one write may be in flight, with only
/// the newest pending write retained. Neither queue can block the caller or the
/// other queue. Values keep their original timestamps; this never renews a lease.
final class LatestFileExchange<Value>: @unchecked Sendable {
    private let lock=NSLock()
    private let reads=DispatchQueue(label:"PhysicalGo.bridgeRead",qos:.userInitiated)
    private let writes=DispatchQueue(label:"PhysicalGo.bridgeWrite",qos:.userInitiated)
    private let read:()->Data?
    private let write:(Value)throws->Void
    private let completed:(Value,Error?)->Void
    private var reading=false,writing=false
    private var snapshot:Data?
    private var pending:Value?
    init(read:@escaping ()->Data?,write:@escaping (Value)throws->Void,
         completed:@escaping (Value,Error?)->Void) {
        self.read=read;self.write=write;self.completed=completed
    }
    /// The consumer must check the timestamp INSIDE this snapshot every time.
    /// A slow/failed read cannot make cached evidence fresh.
    func latest()->Data? {
        lock.lock()
        let result=snapshot,start = !reading
        reading=true;lock.unlock()
        if start {reads.async { [self] in
            let value=read()
            lock.lock();snapshot=value;reading=false;lock.unlock()
        }}
        return result
    }
    func submit(_ value:Value) {
        lock.lock();pending=value
        let start = !writing;writing=true;lock.unlock()
        if start {writes.async { [self] in drain()}}
    }
    private func drain() {
        while true {
            lock.lock()
            guard let value=pending else {writing=false;lock.unlock();return}
            pending=nil;lock.unlock()
            do {try write(value);completed(value,nil)}
            catch {completed(value,error)}
        }
    }
}
