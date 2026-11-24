import Foundation
import Darwin

@main struct EphemeralAtomicFileTests {
    static func main()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PhysicalGoAtomicIPC-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let target=root.appendingPathComponent("latest.json")
        let old=Data("previous immutable snapshot".utf8),new=Data(repeating:0xA7,count:131_077)
        var checks=0
        func check(_ condition:Bool,_ message:String) {checks+=1;precondition(condition,message)}
        func contents()throws->Data {try Data(contentsOf:target)}
        func noTemporary()throws->Bool {try FileManager.default.contentsOfDirectory(atPath:root.path).allSatisfy{$0=="latest.json"}}
        try EphemeralAtomicFile.write(old,to:target)
        var partial=EphemeralAtomicFile.Operations(),calls=0
        partial.write={fd,pointer,count in
            calls+=1
            if calls==1 {errno=EINTR;return -1}
            return Darwin.write(fd,pointer,min(count,997))
        }
        try EphemeralAtomicFile.write(new,to:target,operations:partial)
        check(try contents()==new && calls>100,"short writes/EINTR lost bytes")
        check(try noTemporary(),"successful replacement leaked temporary")
        try EphemeralAtomicFile.write(Data(),to:target)
        check(try contents().isEmpty,"zero-length payload not atomically published")
        for failure in ["create","write","zero_write","close","rename"] {
            try EphemeralAtomicFile.write(old,to:target)
            var io=EphemeralAtomicFile.Operations()
            switch failure {
            case "create":io.makeTemporary={_ in errno=EACCES;return -1}
            case "write":io.write={_,_,_ in errno=ENOSPC;return -1}
            case "zero_write":io.write={_,_,_ in 0}
            case "close":io.close={fd in _=Darwin.close(fd);errno=EIO;return -1}
            default:io.rename={_,_ in errno=EACCES;return -1}
            }
            var failed=false
            do {try EphemeralAtomicFile.write(new,to:target,operations:io)} catch {failed=true}
            check(failed,"injected \(failure) did not fail")
            check(try contents()==old,"\(failure) replaced the valid destination")
            check(try noTemporary(),"\(failure) leaked temporary")
        }
        // Reader visibility while the writer is stopped halfway through a real
        // temporary file, followed by the complete replacement.
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),finished=DispatchSemaphore(value:0)
        let errors=NSLock();var writeError:Error?
        var gated=EphemeralAtomicFile.Operations(),first=true
        gated.write={fd,pointer,count in
            if first {first=false;let n=Darwin.write(fd,pointer,min(7,count));entered.signal();release.wait();return n}
            return Darwin.write(fd,pointer,count)
        }
        DispatchQueue.global().async {
            do {try EphemeralAtomicFile.write(new,to:target,operations:gated)}
            catch {errors.lock();writeError=error;errors.unlock()}
            finished.signal()
        }
        check(entered.wait(timeout:.now()+3) == .success,"partial writer never reached barrier")
        for _ in 0..<20 {check(try contents()==old,"reader saw partial replacement")}
        release.signal();check(finished.wait(timeout:.now()+3) == .success,"writer never finished")
        errors.lock();let error=writeError;errors.unlock()
        let complete=try contents();check(error==nil && complete==new,"completed writer failed")
        check(try noTemporary(),"gated replacement leaked temporary")
        let request=Data("{\"sentAtUnix\":1000,\"expiresAtUnix\":1000.6}".utf8)
        try EphemeralAtomicFile.write(request,to:target)
        check(try contents()==request,"writer changed original timestamp bytes")
        print("PASS",checks,"ephemeral atomic IPC checks (short writes, EINTR, errors, cleanup, atomic visibility and original bytes)")
    }
}
