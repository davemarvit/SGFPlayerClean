import Foundation

/// An explicit session pointer, never a guess based on the newest SGF or log.
struct LastLocalGame {
    let settings:UserDefaults
    private let key="PhysicalGo.lastLocalGame"
    var url:URL? {
        guard let path=settings.string(forKey:key),!path.isEmpty else {return nil}
        return URL(fileURLWithPath:path)
    }
    func remember(_ url:URL?) {
        guard let url else {return}
        settings.set(url.standardizedFileURL.path,forKey:key)
    }
}
