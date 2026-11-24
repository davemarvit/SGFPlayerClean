import Foundation

@main struct LatestFileExchangeTests {
    static func main() throws {
        struct Request {let sequence:Int;let action:String;let expires:Double}
        let readEntered=DispatchSemaphore(value:0),readRelease=DispatchSemaphore(value:0)
        let writeEntered=DispatchSemaphore(value:0),writeRelease=DispatchSemaphore(value:0)
        let offWritten=DispatchSemaphore(value:0),failure=DispatchSemaphore(value:0)
        let lock=NSLock()
        var written=[Request](),reads=0,failRead=false
        let exchange=LatestFileExchange<Request>(read:{
            lock.lock();reads+=1;let fail=failRead;lock.unlock()
            if fail {return nil}
            readEntered.signal();readRelease.wait()
            return Data("old timestamp".utf8)
        },write:{value in
            if value.sequence==1 {writeEntered.signal();writeRelease.wait()}
            if value.sequence==4 {throw CocoaError(.fileWriteUnknown)}
            lock.lock();written.append(value);lock.unlock()
        },completed:{value,error in
            if value.sequence==3 {offWritten.signal()}
            if value.sequence==4,error != nil {failure.signal()}
        })
        precondition(exchange.latest()==nil)
        precondition(readEntered.wait(timeout:.now()+2) == .success)
        exchange.submit(.init(sequence:1,action:"point",expires:1))
        precondition(writeEntered.wait(timeout:.now()+2) == .success,"read must not block writer")
        // Both file operations are deliberately stalled. Calls must return and
        // coalesce pending motion to OFF instead of enqueueing an unbounded backlog.
        for _ in 0..<1000 {precondition(exchange.latest()==nil)}
        exchange.submit(.init(sequence:2,action:"point",expires:2))
        exchange.submit(.init(sequence:3,action:"off",expires:3))
        lock.lock();precondition(reads==1);lock.unlock()
        writeRelease.signal()
        precondition(offWritten.wait(timeout:.now()+2) == .success)
        lock.lock();let result=written;lock.unlock()
        precondition(result.map(\.sequence)==[1,3],"superseded pending point must never publish after OFF")
        precondition(result.map(\.expires)==[1,3],"background delivery must not renew original deadlines")
        readRelease.signal()
        var data:Data?
        for _ in 0..<1000 {
            data=exchange.latest()
            if data != nil {break}
            Thread.sleep(forTimeInterval:0.001)
        }
        precondition(data==Data("old timestamp".utf8),"cached status is returned unmodified")
        lock.lock();failRead=true;lock.unlock();readRelease.signal()
        for _ in 0..<1000 {
            if exchange.latest()==nil {break}
            Thread.sleep(forTimeInterval:0.001)
        }
        precondition(exchange.latest()==nil,"failed read clears the cached snapshot")
        exchange.submit(.init(sequence:4,action:"off",expires:4))
        precondition(failure.wait(timeout:.now()+2) == .success,"write failure delivered")
        print("Latest file exchange: blocked IO, bounded coalescing, OFF ordering, unchanged expiry and failure checks passed")
    }
}
