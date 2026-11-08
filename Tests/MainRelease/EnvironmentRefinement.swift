import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

private func require(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main struct EnvironmentRefinementCheck {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let manager = SceneManager3D()
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        func render() {
            SCNTransaction.flush()
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 800, height: 600), antialiasingMode: .multisampling4X)
        }
        manager.updateEnvironment(.gardenRoom, flicker: false); render()
        let wall = manager.scene.rootNode.childNode(withName: "shoji-back", recursively: true)!
        require(wall.boundingBox.max.x - wall.boundingBox.min.x > 96, "Retextured wall retains full width")
        require(wall.boundingBox.max.y - wall.boundingBox.min.y > 79, "Retextured paper and lattice retain full height")
        let materials = wall.geometry!.materials
        require(materials.filter { $0.name?.hasPrefix("shoji-cedar-") == true }.count == 4, "Batched wood has four patina tones")
        require(materials.first { $0.name == "shoji-washi" }?.shaderModifiers?[.surface] != nil, "Paper has spatial daylight shading")
        manager.updateEnvironment(.yugenRoom, flicker: false); render()
        for side in ["player", "opponent"] {
            let seat = manager.scene.rootNode.childNode(withName: "yugen-furniture-\(side)", recursively: true)!
            require(abs(seat.worldPosition.y - KayaFloorBoard.floorY) < 0.001, "Chair is grounded")
            require(abs(seat.position.z) - max(abs(seat.boundingBox.min.z), abs(seat.boundingBox.max.z)) > 14, "Chair and armrest clear board and bowls")
            require(seat.boundingBox.max.y > 14, "Upholstered back is present")
        }
        manager.updateEnvironment(.moon, flicker: false); render()
        let material = manager.scene.rootNode.childNode(withName: "photographic-ground", recursively: true)!.geometry!.firstMaterial!
        require(material.normal.intensity < 0.1, "Moon relief no longer exaggerates fine grain")
        print("PASS: full-size varied shoji, grounded floor chairs and armrests, gentler Moon relief")
    }
}
