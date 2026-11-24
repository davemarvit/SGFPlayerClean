import Foundation
import Combine

/// Stores named physical sets only. The caller may inject an isolated destination;
/// no selection or edit changes active vision, game, grid or laser state.
@MainActor final class StoneSetProfileStore:ObservableObject {
    @Published private(set) var library=StoneSetLibrary()
    @Published private(set) var error:String?
    nonisolated static func libraryURL(applicationSupport:URL)->URL {
        applicationSupport.appendingPathComponent("Physical Go/Stone Sets",isDirectory:true)
            .appendingPathComponent("library.json")
    }
    nonisolated static var defaultLibraryURL:URL {
        libraryURL(applicationSupport:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0])
    }
    private static let maximumBytes=2_000_000
    private let fileURL:URL
    private var loadFailed=false
    var selected:StoneSetProfile? {library.profiles.first{$0.id == library.selectedStoneSetID}}
    init(fileURL:URL) {
        self.fileURL=fileURL
        guard FileManager.default.fileExists(atPath:fileURL.path) else {return}
        do {
            let handle=try FileHandle(forReadingFrom:fileURL)
            defer {try? handle.close()}
            let data=try handle.read(upToCount:Self.maximumBytes+1) ?? Data()
            guard data.count<=Self.maximumBytes else {throw StoneSetProfileError.invalid("Stone-set library is too large.")}
            let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
            let saved=try decoder.decode(StoneSetLibrary.self,from:data)
            try saved.validate();library=saved
        } catch {self.error="Could not read saved stone sets. \(error.localizedDescription)";loadFailed=true}
    }
    func select(_ id:UUID?) {
        var next=library;next.selectedStoneSetID=id
        commit(next)
    }
    @discardableResult func save(_ profile:StoneSetProfile)->Bool {
        var next=library
        var edited=profile;edited.name=edited.name.trimmingCharacters(in:.whitespacesAndNewlines)
        edited.updatedAt=Date()
        if let index=next.profiles.firstIndex(where:{$0.id == edited.id}) {next.profiles[index]=edited}
        else {next.profiles.append(edited)}
        next.selectedStoneSetID=edited.id
        return commit(next)
    }
    @discardableResult private func commit(_ next:StoneSetLibrary)->Bool {
        guard !loadFailed else {return false} // Never overwrite an unreadable library.
        do {
            try next.validate()
            let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601;encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            let bytes=try encoder.encode(next)
            guard bytes.count<=Self.maximumBytes else {throw StoneSetProfileError.invalid("Stone-set library is too large to save.")}
            try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try bytes.write(to:fileURL,options:.atomic)
            library=next;error=nil;return true
        } catch {self.error=error.localizedDescription;return false}
    }
}
