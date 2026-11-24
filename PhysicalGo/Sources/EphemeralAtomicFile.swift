import Foundation
import Darwin

/// Atomic visibility for replaceable IPC, without crash-durability work. Never
/// use for saved games, calibration, settings or any persistent user document.
/// A reader sees the complete previous file or the complete replacement. A
/// system crash may lose either version; consumers still validate original ages.
enum EphemeralAtomicFile {
    struct Operations {
        var makeTemporary:(UnsafeMutablePointer<CChar>)->Int32 = {Darwin.mkstemp($0)}
        var write:(Int32,UnsafeRawPointer,Int)->Int = {Darwin.write($0,$1,$2)}
        var close:(Int32)->Int32 = {Darwin.close($0)}
        var rename:(String,String)->Int32 = {Darwin.rename($0,$1)}
        var unlink:(String)->Int32 = {Darwin.unlink($0)}
    }
    static func write(_ data:Data,to destination:URL,operations:Operations = Operations())throws {
        guard destination.isFileURL else {throw CocoaError(.fileWriteUnsupportedScheme)}
        let parent=destination.deletingLastPathComponent()
        var template=Array(parent.appendingPathComponent(".\(destination.lastPathComponent).XXXXXX").path.utf8CString)
        var descriptor=template.withUnsafeMutableBufferPointer {operations.makeTemporary($0.baseAddress!)}
        guard descriptor>=0 else {throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
        let temporary=String(cString:template)
        var renamed=false
        defer {
            if descriptor>=0 {_=operations.close(descriptor)}
            if !renamed {_=operations.unlink(temporary)}
        }
        try data.withUnsafeBytes {buffer in
            var offset=0
            while offset<buffer.count {
                let count=operations.write(descriptor,buffer.baseAddress!.advanced(by:offset),buffer.count-offset)
                if count<0 {
                    let code=errno
                    if code==EINTR {continue}
                    throw POSIXError(POSIXErrorCode(rawValue:code) ?? .EIO)
                }
                guard count>0,count<=buffer.count-offset else {throw POSIXError(.EIO)}
                offset+=count
            }
        }
        // Do not retry close after an error: its descriptor may already have
        // been released/reused. A close failure never publishes the temporary.
        let closing=descriptor;descriptor = -1
        guard operations.close(closing)==0 else {throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
        guard operations.rename(temporary,destination.path)==0 else {throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
        renamed=true
    }
}
