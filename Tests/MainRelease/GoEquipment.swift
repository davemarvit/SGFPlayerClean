import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct GoEquipmentCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let manager = SceneManager3D()
        let names = ["white-stone-bowl", "black-stone-bowl", "white-player-lid", "black-player-lid"]
        func equipment(_ name: String) -> SCNNode {
            manager.scene.rootNode.childNode(withName: name, recursively: true)!
        }
        func checkEquipment() {
            let material = equipment(names[0]).geometry!.firstMaterial!
            let whiteWood = equipment("white-player-lid").geometry!.firstMaterial!
            let blackWood = equipment("black-player-lid").geometry!.firstMaterial!
            require(whiteWood !== blackWood, "Lids use distinct pieces of wood")
            for (whiteMap, blackMap) in [(whiteWood.diffuse, blackWood.diffuse),
                                        (whiteWood.normal, blackWood.normal),
                                        (whiteWood.roughness, blackWood.roughness)] {
                require((whiteMap.contents as? NSImage)?.tiffRepresentation !=
                        (blackMap.contents as? NSImage)?.tiffRepresentation,
                        "Both lids have different grain and corresponding surface maps")
            }
            for name in names {
                let node = equipment(name)
                if name.hasSuffix("-lid") {
                    let lidMaterial = node.geometry!.firstMaterial!
                    require(lidMaterial.normal.contents is NSImage && lidMaterial.roughness.contents is NSImage,
                        "Lid grain retains its surface relief and roughness after rebuild")
                } else {
                    let matchingLid = name.hasPrefix("white") ? whiteWood : blackWood
                    require(node.geometry!.firstMaterial === matchingLid, "Each bowl matches its own lid's wood finish")
                }
                require(material.diffuse.contents is NSImage, "Generated wood grain is available")
                require(node.geometry!.sources(for: .vertex).first!.vectorCount > 1000, "Equipment has real geometry")
            }
            for name in names.prefix(2) {
                let bowl = equipment(name)
                let stones = bowl.childNodes.filter { $0.name == "supply-stone" }
                require(stones.count > 30, "Bowl contains a full pile of individual stones")
                require(stones.allSatisfy { $0.physicsBody == nil }, "Supply stones do not add a live physics workload")
                require(stones.allSatisfy { hypot($0.position.x, $0.position.z) < 3.1 && $0.position.y < 4.8 }, "Settled stones form a contained mound")
                let color = (stones[0].geometry!.firstMaterial!.diffuse.contents as! NSColor).usingColorSpace(.genericGray)!
                require(name.hasPrefix("white") ? color.whiteComponent > 0.9 : color.whiteComponent < 0.1, "Supply colors match their bowl")
            }
        }
        checkEquipment()
        for size in [9, 13, 19] {
            manager.updateBoardSize(size)
            manager.createLids()
            checkEquipment()
            var bowls = 0
            manager.scene.rootNode.enumerateChildNodes { node, _ in
                if names.prefix(2).contains(node.name ?? "") { bowls += 1 }
            }
            require(bowls == 2, "Board resizing and lid rebuilding do not duplicate bowls")
        }
        let exported = SCNScene()
        for name in names { exported.rootNode.addChildNode(equipment(name).clone()) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("equipment-\(UUID()).scn")
        defer { try? FileManager.default.removeItem(at: url) }
        require(exported.write(to: url, options: nil, delegate: nil, progressHandler: nil), "Equipment export succeeds")
        let restored = try SCNScene(url: url)
        require(restored.rootNode.childNodes.count == 4, "All four models reopen")
        require(restored.rootNode.childNode(withName: "white-stone-bowl", recursively: false)!.childNodes.count > 30, "Export retains individual stones")
        let texture = restored.rootNode.childNodes[0].geometry!.firstMaterial!.diffuse.contents
        let embeddedImage = (texture as? NSImage) ?? (texture as? Data).flatMap { NSImage(data: $0) }
        require(embeddedImage != nil, "Export embeds a decodable wood texture")
        print("PASS: solid bowls and textured lids, filled black/white supplies, resize/rebuild lifecycle and self-contained model export")
    }
}
