import Foundation

/// Immutable recording context is serialized once, not after every writer gap.
/// The resulting file remains an ordinary schema-1 session.json with every
/// original context/checkpoint field inline. No reader or old archive migration.
struct DiagnosticManifest {
    private let prefix:Data
    private let initialReason:Any?
    var cachedBytes:Int {prefix.count}
    init(context:[String:Any])throws {
        var immutable=context
        initialReason=immutable.removeValue(forKey:"reason")
        for key in ["status","framesSaved","bytesWritten","omittedImages","updatedAt"] {
            immutable.removeValue(forKey:key)
        }
        // Compact JSON preserves field values while avoiding a second enlarged
        // pretty-print buffer for pixel-rich hand-tracker checkpoints.
        var data=try JSONSerialization.data(withJSONObject:immutable,options:.sortedKeys)
        precondition(data.first==123 && data.last==125)
        data.removeLast()
        prefix=data
    }
    func data(status:String,frames:Int,bytes:Int64,omittedImages:Int,updatedAt:Double,reason:String?)throws->Data {
        var dynamic:[String:Any]=["status":status,"framesSaved":frames,"bytesWritten":bytes,
            "omittedImages":omittedImages,"updatedAt":updatedAt]
        // Match the previous dictionary-overlay behavior, including a caller's
        // context reason when no lifecycle reason overrides it.
        if let reason {dynamic["reason"]=reason}
        else if let initialReason {dynamic["reason"]=initialReason}
        let tail=try JSONSerialization.data(withJSONObject:dynamic,options:.sortedKeys)
        var result=prefix
        if prefix.count>1 {result.append(44)}
        result.append(contentsOf:tail.dropFirst())
        return result
    }
}
