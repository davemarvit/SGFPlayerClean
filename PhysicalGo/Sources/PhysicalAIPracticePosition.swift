import Foundation
import CryptoKit

/// Synthetic positions; subsequent moves are accepted through ordinary play.
enum PhysicalAIPracticePosition:String,Codable,CaseIterable,Identifiable {
    case emptyHumanBlack,emptyHumanWhite,singleCapture,twoStoneCapture
    var id:String {rawValue}
    var title:String {
        switch self {
        case .emptyHumanBlack:return "Empty board — you play Black"
        case .emptyHumanWhite:return "Empty board — you play White"
        case .singleCapture:return "Single capture"
        case .twoStoneCapture:return "Two-stone capture"
        }
    }
    var humanBlack:Bool {self != .emptyHumanWhite}
    var black:[Int] {self == .singleCapture ? [19,360]:self == .twoStoneCapture ? [1,20]:[]}
    var white:[Int] {self == .singleCapture ? [0,2]:self == .twoStoneCapture ? [0,19]:[]}
    var moves:[Int] {self == .singleCapture ? [19,0,360,2]:self == .twoStoneCapture ? [1,0,20,19]:[]}
    var nextMove:Int? {self == .singleCapture ? 1:self == .twoStoneCapture ? 38:nil}
    var prisoners:[Int] {self == .singleCapture ? [0]:self == .twoStoneCapture ? [0,19]:[]}
    var syntheticDetail:String {moves.isEmpty ? "Synthetic empty-board test; not a continuation of the preserved game.":"Synthetic test position: first four moves are a constructed legal fixture, not recorded play."}
    var clockDetail:String {
        switch self {
        case .singleCapture:return "Single capture: the next player's elapsed clock keeps running during removal."
        case .twoStoneCapture:return "Two-stone capture: elapsed clocks stay paused until both prisoners are removed."
        case .emptyHumanBlack:return "Clear the board. After Resume and camera verification, you play Black first."
        case .emptyHumanWhite:return "Clear the board. The AI plays Black only after Resume and camera verification."
        }
    }
}

struct PhysicalAIPracticeContext:Codable,Equatable {
    let position:PhysicalAIPracticePosition
    let testID:UUID
    let previousGameID:UUID?
    let backupSHA256:String
}

/// All fallible preparation precedes the atomic authoritative current.json write.
/// Backup records remain immutable; test exports never share the prior game's ID.
final class PhysicalAIPracticeStore {
    struct Backup:Codable {
        var schemaVersion=1
        let testID:UUID
        let position:PhysicalAIPracticePosition
        let previousGameID:UUID?
        let previousCurrent:Data?
        let previousDraft:PhysicalAISettings
    }
    struct Prepared {
        let record:Backup
        let data:Data
        var context:PhysicalAIPracticeContext {
            .init(position:record.position,testID:record.testID,previousGameID:record.previousGameID,
                  backupSHA256:PhysicalAIPracticeStore.digest(data))
        }
    }
    struct Failure:LocalizedError {
        let message:String
        var errorDescription:String? {message}
    }
    let directory:URL
    private let write:(Data,URL)throws->Void
    private var currentURL:URL {directory.appendingPathComponent("current.json")}
    init(directory:URL,write:@escaping (Data,URL)throws->Void = {try $0.write(to:$1,options:.atomic)}) {
        self.directory=directory;self.write=write
    }
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    private func folder(_ id:UUID)->URL {directory.appendingPathComponent("PracticeTests").appendingPathComponent(id.uuidString)}
    func backupURL(_ context:PhysicalAIPracticeContext)->URL {folder(context.testID).appendingPathComponent("previous-game.json")}
    private func requireCurrent(_ expected:Data?)throws {
        let actual=FileManager.default.fileExists(atPath:currentURL.path) ? try Data(contentsOf:currentURL):nil
        guard actual==expected else {throw Failure(message:"The saved game changed outside this window. Reopen it before changing test positions.")}
    }
    func prepare(position:PhysicalAIPracticePosition,testID:UUID,previousGameID:UUID?,previousCurrent:Data?,draft:PhysicalAISettings)throws->Prepared {
        guard (previousGameID==nil)==(previousCurrent==nil) else {throw Failure(message:"Saved game backup is incomplete.")}
        let record=Backup(testID:testID,position:position,previousGameID:previousGameID,previousCurrent:previousCurrent,previousDraft:draft)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return .init(record:record,data:try encoder.encode(record))
    }
    func activate(_ prepared:Prepared,current:Data,sgf:Data)throws {
        try requireCurrent(prepared.record.previousCurrent)
        let backup=backupURL(prepared.context),export=directory.appendingPathComponent(prepared.record.testID.uuidString+".sgf")
        guard !FileManager.default.fileExists(atPath:backup.path),!FileManager.default.fileExists(atPath:export.path) else {
            throw Failure(message:"This test identifier already has saved files. Try a new test position.")
        }
        try FileManager.default.createDirectory(at:backup.deletingLastPathComponent(),withIntermediateDirectories:true)
        try write(prepared.data,backup)
        guard try Data(contentsOf:backup)==prepared.data else {throw Failure(message:"The saved-game backup could not be verified.")}
        let handle=try FileHandle(forWritingTo:backup)
        defer {try? handle.close()}
        try handle.synchronize()
        try write(sgf,export)
        try requireCurrent(prepared.record.previousCurrent)
        // Commit point: no fallible derived export or backup operation follows.
        try write(current,currentURL)
    }
    func readBackup(_ context:PhysicalAIPracticeContext)throws->Backup {
        let data=try Data(contentsOf:backupURL(context))
        guard Self.digest(data)==context.backupSHA256 else {throw Failure(message:"Saved-game backup verification failed. The test position is unchanged.")}
        let record=try JSONDecoder().decode(Backup.self,from:data)
        guard record.schemaVersion==1,record.testID==context.testID,record.position==context.position,
              record.previousGameID==context.previousGameID,(record.previousGameID==nil)==(record.previousCurrent==nil) else {
            throw Failure(message:"The backup belongs to another test. The current game is unchanged.")
        }
        return record
    }
    func restore(_ context:PhysicalAIPracticeContext,expectedCurrent:Data,replacement:Data?)throws {
        try requireCurrent(expectedCurrent)
        _=try readBackup(context)
        try write(expectedCurrent,folder(context.testID).appendingPathComponent("last-test.json"))
        try requireCurrent(expectedCurrent)
        if let replacement {try write(replacement,currentURL)}
        else {try FileManager.default.removeItem(at:currentURL)}
    }
}
