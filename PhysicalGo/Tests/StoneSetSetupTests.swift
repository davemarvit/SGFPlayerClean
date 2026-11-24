import Foundation
import Combine
import SwiftUI

@main struct StoneSetSetupTests {
    @MainActor static func main() throws {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("stone-set-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let url=StoneSetProfileStore.libraryURL(applicationSupport:root)
        check(url.path == root.appendingPathComponent("Physical Go/Stone Sets/library.json").path,"Dedicated Stone Sets path is deterministic under injected application support")
        check(StoneSetProfileStore.defaultLibraryURL.path.hasSuffix("/Physical Go/Stone Sets/library.json"),"Production destination is a dedicated library")
        let protected:[String:Data]=["AI Games/current.json":Data("saved game and clocks".utf8),
            "LaserBridge/request.json":Data("off request".utf8),"camera-grid.json":Data("current camera grid".utf8)]
        for (name,bytes) in protected {
            let path=root.appendingPathComponent("Physical Go").appendingPathComponent(name)
            try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
            try bytes.write(to:path)
        }
        let store=StoneSetProfileStore(fileURL:url)
        check(!FileManager.default.fileExists(atPath:url.path),"Opening setup does not create or auto-import a profile")
        var observed=[StoneSetLibrary]()
        let subscription=store.$library.sink {observed.append($0)}
        let picker=StoneSetProfilePicker(store:store)
        _=picker // Compile the actual hosted control against the same observable store.
        var club=StoneSetProfile(name:"Club glass")
        check(store.save(club),"New set action persists a name with unknown thickness")
        check(store.selected?.black.physicalThicknessMm == nil && store.selected?.white.physicalThicknessMm == nil,"Unknown is valid for both colors")
        check(store.selected?.black.opticalHeightCandidates.isEmpty == true && store.selected?.white.opticalHeightCandidates.isEmpty == true,"No optical studies imported or activated")
        let travel=StoneSetProfile(name:"Travel stones")
        check(store.save(travel),"Second named set saves and selects")
        store.select(club.id)
        check(store.selected?.id == club.id,"Picker selection returns to existing named set")
        club.name="Club glass — thick"
        club.black.physicalThicknessMm = .init(value:9.1)
        club.white.physicalThicknessMm = .init(value:8.8)
        check(store.save(club),"Edit action renames and saves independent color measurements")
        check(observed.last?.selectedStoneSetID == club.id && observed.last?.profiles.first(where:{$0.id == club.id})?.name == club.name,"Observed picker receives saved rename and selection")
        let reload=StoneSetProfileStore(fileURL:url)
        check(reload.selected?.name == club.name && reload.library.profiles.count == 2,"Relaunch reloads named sets and selected ID")
        check(reload.selected?.black.physicalThicknessMm?.value == 9.1 && reload.selected?.white.physicalThicknessMm?.value == 8.8,"Per-color manual values survive reload")
        var unknown=reload.selected!;unknown.white.physicalThicknessMm=nil
        check(reload.save(unknown),"Unknown action clears only the chosen physical measurement")
        check(reload.selected?.white.physicalThicknessMm == nil && reload.selected?.black.physicalThicknessMm?.value == 9.1,"Unknown White does not change Black")
        for (name,bytes) in protected {
            let actual=try Data(contentsOf:root.appendingPathComponent("Physical Go").appendingPathComponent(name))
            check(actual == bytes,"Profile selection/edit leaves \(name) unchanged")
        }
        check(observed.count>=5,"Observable library publishes actual UI changes")
        withExtendedLifetime(subscription) {}
        print("PASS: \(checks) stone-set setup hosting, persistence and isolation checks")
    }
}
