import AppKit
import SceneKit
@testable import SGF_Player_OGS_Review

@main struct CameraArrivalPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let assets = Bundle.main.resourceURL!
        let output = URL(fileURLWithPath: "/private/tmp/sgf-wider-camera-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let images = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }.compactMap { url -> NSImage? in
            guard !url.path.contains("/Bowls2D/"), let image = NSImage(contentsOf: url) else { return nil }
            image.setName(url.path.contains("/Environments/") || url.lastPathComponent == TatamiTexture.assetName ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
            return image
        }
        precondition(SceneManager3D.cameraArrivalTotalDuration == 13)
        precondition(SceneManager3D.cameraArrivalSurveyDuration == 7)
        let manager = SceneManager3D(); manager.updateDebugSettings()
        let player = SGFPlayer()
        player.load(game: SGFGame.from(tree: try SGFParser.parse(text: "(;SZ[19];B[dd];W[pd];B[dp];W[pp];B[cf];W[nc];B[fc];W[qn];B[cn];W[nq];B[qq];W[pq];B[qp];W[po])")))
        player.seek(to: player.maxIndex)
        manager.updateStones(from: player.board.stones.map { RenderStone(id: $0.key, color: $0.value, offset: .zero) }, lastMove: nil, moveIndex: player.maxIndex, settings: AppSettings.shared, animate: false)
        GoEquipment3D.updateSupplies(in: manager, player: player, animate: false)
        manager.updateCapturedStones(black: 3, white: 7)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = manager.scene; renderer.pointOfView = manager.cameraNode
        for kind in PlayingEnvironment.allCases {
            manager.updateEnvironment(kind, flicker: false)
            manager.updateCameraPosition(distance: SceneManager3D.seatedCameraDistance(boardSize: 19),
                rotationX: SceneManager3D.seatedCameraRotationX, rotationY: 0, panX: 0, panY: 0)
            precondition(abs(kind.arrivalSurveyAngle) >= 0.65)
            manager.beginCameraArrival(reduceMotion: false)
            let hold = SceneManager3D.cameraArrivalHoldDuration
            let survey = SceneManager3D.cameraArrivalSurveyDuration
            let total = SceneManager3D.cameraArrivalTotalDuration
            let times = [0.0, hold + survey * 0.5, hold + survey, hold + survey + (total - hold - survey) * 0.5, total]
            for (index, time) in times.enumerated() {
                manager.updateCameraArrival(elapsed: time)
                SCNTransaction.flush()
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1000, height: 750), antialiasingMode: .multisampling4X)
                let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                try data.write(to: output.appendingPathComponent("\(kind.rawValue)-\(index).png"))
            }
        }
        print("PASS: rendered all eleven environments through the extended survey and descent")
        withExtendedLifetime(images) {}
    }
}
