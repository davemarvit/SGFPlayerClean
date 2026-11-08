import AppKit
import SceneKit
import simd
@testable import SGFPlayerNetworking

/// Development-only physics bake. The application loads poses, never this simulation.
@main struct BakeBowlLayout {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let black = bake(isWhite: false)
        let white = bake(isWhite: true)
        let object: [String: Any] = ["version": 2, "capacity": 181,
            "radius": GoEquipment3D.supplyStoneRadius(isWhite: false),
            "whiteRadius": GoEquipment3D.supplyStoneRadius(isWhite: true),
            "scaleY": GoEquipment3D.supplyStoneScaleY, "states": black, "whiteStates": white]
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Saved both colours' settled fill states; playback needs no physics.")
    }

    @MainActor static func bake(isWhite: Bool) -> [[[Double]]] {
        let scene = SCNScene()
        scene.physicsWorld.gravity = SCNVector3(0, -19.62, 0)
        scene.physicsWorld.timeStep = 1.0 / 120
        let bowl = GoEquipment3D.makeBowl(isWhite: false, stoneMaterial: SCNMaterial(), includeStones: false)
        bowl.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: bowl.geometry!,
            options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron, .collisionMargin: 0.002]))
        bowl.physicsBody!.friction = 0.35
        bowl.physicsBody!.restitution = 0
        scene.rootNode.addChildNode(bowl)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        var vertices: [SCNVector3] = [], indices: [Int32] = []
        let rings = 14, segments = 24
        let stoneRadius = Double(GoEquipment3D.supplyStoneRadius(isWhite: isWhite))
        for ring in 0...rings {
            let latitude = Double(ring) * .pi / Double(rings)
            for segment in 0..<segments {
                let longitude = Double(segment) * 2 * .pi / Double(segments)
                vertices.append(SCNVector3(stoneRadius * sin(latitude) * cos(longitude),
                    stoneRadius * Double(GoEquipment3D.supplyStoneScaleY) * cos(latitude), stoneRadius * sin(latitude) * sin(longitude)))
                if ring < rings {
                    let a = Int32(ring * segments + segment), b = Int32(ring * segments + (segment + 1) % segments)
                    let c = a + Int32(segments), d = b + Int32(segments)
                    indices += [a, c, b, b, c, d]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        // A small explicit skin avoids separating the visible stone surfaces.
        let shape = SCNPhysicsShape(geometry: geometry, options: [.type: SCNPhysicsShape.ShapeType.convexHull, .collisionMargin: 0.002])
        var seed: UInt64 = 3981
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / 9007199254740992
        }
        var nodes: [SCNNode] = []
        var states: [[[Double]]] = [[]]
        var time = 0.0
        renderer.update(atTime: time)
        let maximum = isWhite ? 180 : 181
        for count in 1...maximum {
            let stone = SCNNode(geometry: geometry)
            let radius = sqrt(random()) * 1.85, angle = random() * 2 * .pi
            let top = nodes.map { Double($0.presentation.position.y) }.max() ?? 3.7
            stone.position = SCNVector3(radius * cos(angle), max(5.2, top + 1.2), radius * sin(angle))
            stone.eulerAngles = SCNVector3((random() - 0.5) * 1.4, random() * 2 * .pi, (random() - 0.5) * 1.4)
            let body = SCNPhysicsBody(type: .dynamic, shape: shape)
            // Let stones slide and roll into gaps before the solver puts them to sleep.
            body.mass = 0.5; body.friction = 0.3; body.rollingFriction = 0.015
            body.restitution = 0; body.damping = 0.35; body.angularDamping = 0.25
            body.linearRestingThreshold = 0.005; body.angularRestingThreshold = 0.005
            stone.physicsBody = body
            scene.rootNode.addChildNode(stone); nodes.append(stone)
            SCNTransaction.flush()
            var quietFrames = 0
            for step in 0..<1200 {
                time += 1.0 / 60
                renderer.update(atTime: time)
                let quiet = nodes.allSatisfy {
                    let body = $0.physicsBody!, v = body.velocity
                    return hypot(hypot(v.x, v.y), v.z) < 0.025 && abs(body.angularVelocity.w) < 0.04
                }
                quietFrames = quiet && step > 90 ? quietFrames + 1 : 0
                if quietFrames >= 60 { break }
            }
            guard quietFrames >= 60 else { fatalError("Pile did not settle at \(count)") }
            let poses: [[Double]] = nodes.map {
                let p = $0.presentation.simdPosition, q = $0.presentation.simdOrientation.vector
                return [p.x, p.y, p.z, q.x, q.y, q.z, q.w].map { (Double($0) * 100000).rounded() / 100000 }
            }
            guard poses.allSatisfy({ $0[1] > 0 && hypot($0[0], $0[2]) < 3.1 }) else {
                fatalError("A stone spilled at count \(count)")
            }
            states.append(poses)
            if count % 20 == 0 || count == maximum {
                print("Settled \(count) stones; top center \(poses.map { $0[1] }.max()!)")
                fflush(stdout)
            }
        }
        return states
    }
}
