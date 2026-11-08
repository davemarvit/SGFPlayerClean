#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit

/// Assets are local and cached. Selecting or orbiting never downloads a texture.
enum EnvironmentMaterials {
    private static var images: [String:NSImage] = [:]
    static func assetURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Environments") { return url }
        #if SWIFT_PACKAGE
        // Offline preview/test tools use the same assets as the app bundle.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/Environments").appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        #endif
        return nil
    }
    static func image(_ name: String) -> NSImage? {
        if let image=images[name] { return image }
        let image = NSImage(named:name) ?? Bundle.main.url(forResource:name,withExtension:nil,subdirectory:"Environments").flatMap { NSImage(contentsOf:$0) }
        if let image { images[name]=image }
        return image
    }
    static func scanned(_ name: String, repeatCount: CGFloat = 1) -> SCNMaterial {
        let m=SCNMaterial(); m.name=name; m.lightingModel = .physicallyBased
        m.diffuse.contents=image(name+"-color.jpg") ?? NSColor.gray
        m.normal.contents=image(name+"-normal.jpg")
        m.roughness.contents=image(name+"-rough.jpg") ?? 0.85
        m.ambientOcclusion.contents=image(name+"-ao.jpg")
        m.metalness.contents=0
        for channel in [m.diffuse,m.normal,m.roughness,m.ambientOcclusion] {
            channel.wrapS = .repeat; channel.wrapT = .repeat
            channel.contentsTransform=SCNMatrix4MakeScale(.init(repeatCount),.init(repeatCount),1)
            channel.mipFilter = .linear; channel.minificationFilter = .linear; channel.maxAnisotropy=8
        }
        return m
    }
    static func panorama(_ kind: PlayingEnvironment) -> NSImage? {
        switch kind {
        case .gardenRoom: return image("garden-room-ninomaru-8k.jpg")
        case .japaneseGarden: return image("garden-late-autumn-panorama.png")
        case .mountainSummit: return image("mountain-summit-panorama.png")
        case .tree: return image("tree-intimate-panorama.png")
        case .moon: return image("moon-panorama-v3.png")
        case .cave: return image("cave-mineral-panorama.png")
        case .monastery: return image("monastery-intimate-panorama.png")
        case .yugenRoom: return image("yugen-room-panorama.png")
        case .coffeeShop: return image("coffee-shop-panorama.png")
        case .retroFuture: return image("retro-future-panorama.png")
        case .laboratory: return image("laboratory-panorama.png")
        case .spaceStation: return image("space-station-panorama.png")
        }
    }

    /// Nearby surfaces have planar, physically scaled scans; only the distant
    /// ground retains the panorama. This avoids magnifying its blurred nadir.
    static func addGroundDetail(to material: SCNMaterial, kind: PlayingEnvironment) {
        switch kind {
        case .cave: addCaveBedrock(to: material)
        case .tree: addWoodlandGround(to: material)
        case .mountainSummit: addSummitGround(to: material)
        case .japaneseGarden, .moon: addOutdoorGround(to: material, lunar: kind == .moon)
        default: break // Interior floors and tables have their own geometry.
        }
    }

    private static func addSummitGround(to material: SCNMaterial) {
        guard let color = image("summit-rock-color.jpg") else { return }
        material.name = "summit-scanned-rock"
        material.lightingModel = .physicallyBased
        material.multiply.contents = color
        material.normal.contents = image("summit-rock-normal.jpg")
        material.roughness.contents = image("summit-rock-rough.jpg")
        material.normal.intensity = 0.65
        material.metalness.contents = 0
        // The photographed patch spans 1.8 metres, about four board widths.
        for property in [material.multiply, material.normal, material.roughness] {
            property.mappingChannel = 1
            property.wrapS = .repeat; property.wrapT = .repeat
            property.contentsTransform = SCNMatrix4MakeScale(150 / 78, 150 / 78, 1)
            property.minificationFilter = .linear; property.magnificationFilter = .linear
            property.mipFilter = .linear; property.maxAnisotropy = 16
        }
        material.shaderModifiers = [.surface: """
        #pragma body
        float radius = length((_surface.transparentTexcoord - float2(0.5)) * 150.0);
        float nearby = 1.0 - smoothstep(35.0, 65.0, radius);
        float3 scan = _surface.multiply.rgb;
        float grey = dot(scan, float3(0.2126, 0.7152, 0.0722));
        float3 rock = mix(scan, float3(grey), 0.3) * 0.8;
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, rock, nearby);
        _surface.emission.rgb = mix(_surface.emission.rgb, rock * 0.025, nearby);
        _surface.multiply = float4(1.0);
        _surface.roughness = max(_surface.roughness, 0.82);
        _surface.normal = normalize(mix(_surface.geometryNormal, _surface.normal, nearby));
        """]
    }

    private static func addOutdoorGround(to material: SCNMaterial, lunar: Bool) {
        let asset = lunar ? "moon-regolith" : "zen-loose-gravel"
        guard let color = image(asset + "-color.jpg") else { return }
        material.name = asset
        material.multiply.contents = color
        material.normal.contents = image(asset + "-normal.jpg")
        material.normal.intensity = lunar ? 0.24 : 0.85
        let tileSide: CGFloat = lunar ? 30 : 20
        for property in [material.multiply, material.normal] {
            property.mappingChannel = 1
            property.wrapS = .repeat; property.wrapT = .repeat
            property.contentsTransform = SCNMatrix4MakeScale(.init(300 / tileSide), .init(300 / tileSide), 1)
            property.minificationFilter = .linear; property.magnificationFilter = .linear
            property.mipFilter = .linear; property.maxAnisotropy = 16
        }
        material.setValue(lunar ? Float(1) : Float(0), forKey: "lunarGround")
        material.shaderModifiers = [.surface: """
        #pragma arguments
        float lunarGround;
        #pragma body
        float radius = length((_surface.transparentTexcoord - float2(0.5)) * 300.0);
        float nearby = 1.0 - smoothstep(55.0, 125.0, radius);
        float3 scan = _surface.multiply.rgb;
        float grey = dot(scan, float3(0.2126, 0.7152, 0.0722));
        // Loose gravel has stone boundaries throughout, unlike the old
        // compacted road scan. Keep those dark interstices instead of lifting
        // every pixel by a constant, which made the surface read as sand.
        float3 granite = mix(scan, float3(grey), 0.85) * float3(2.0,2.02,2.04);
        float3 ground = mix(granite, float3(grey * 2.2), lunarGround);
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, ground, nearby);
        _surface.emission.rgb = mix(_surface.emission.rgb, ground * 0.025, nearby);
        _surface.multiply = float4(1.0);
        _surface.normal = normalize(mix(_surface.geometryNormal, _surface.normal, nearby));
        """]
    }

    /// The seated foreground uses the scan's actual leaf and moss colors.
    /// Multiplying the low-resolution panorama by grit still left enlarged,
    /// blurry leaves underneath it. The panorama is only retained at distance.
    private static func addWoodlandGround(to material: SCNMaterial) {
        guard let color = image("woodland-ground-color.jpg") else { return }
        material.name = "woodland-scanned-leaf-litter"
        // Match the panoramic floor's diffuse lighting at the distant blend.
        material.lightingModel = .lambert
        material.multiply.contents = color
        material.normal.contents = image("woodland-ground-normal.jpg")
        material.normal.intensity = 0.45
        for property in [material.multiply, material.normal] {
            property.mappingChannel = 1
            property.wrapS = .repeat; property.wrapT = .repeat
            property.contentsTransform = SCNMatrix4MakeScale(300 / 105, 300 / 105, 1)
            property.minificationFilter = .linear; property.magnificationFilter = .linear
            property.mipFilter = .linear; property.maxAnisotropy = 16
        }
        material.shaderModifiers = [.surface: """
        #pragma body
        float radius = length((_surface.transparentTexcoord - float2(0.5)) * 300.0);
        float nearby = 1.0 - smoothstep(55.0, 125.0, radius);
        float3 woodland = _surface.multiply.rgb * float3(0.85, 0.80, 0.72);
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb, woodland, nearby);
        _surface.emission.rgb = mix(_surface.emission.rgb, woodland * 0.025, nearby);
        _surface.multiply = float4(1.0);
        _surface.normal = normalize(mix(_surface.geometryNormal, _surface.normal, nearby));
        """]
    }

    private static var fernMeshes: [SCNGeometry] = []
    static var woodlandFerns: [SCNGeometry] {
        if !fernMeshes.isEmpty { return fernMeshes }
        guard let color = image("woodland-fern-color.jpg"), let opacity = image("woodland-fern-opacity.png"),
              let url = assetURL("woodland-ferns.scn"), let scene = try? SCNScene(url: url) else { return [] }
        let material = SCNMaterial(); material.name = "woodland-scanned-fern"
        material.lightingModel = .physicallyBased; material.isDoubleSided = true
        material.diffuse.contents = color
        material.normal.contents = image("woodland-fern-normal.jpg"); material.normal.intensity = 0.5
        material.roughness.contents = image("woodland-fern-rough.jpg")
        material.transparent.contents = opacity
        material.transparencyMode = .aOne
        material.emission.contents = material.diffuse.contents; material.emission.intensity = 0.08
        material.writesToDepthBuffer = true
        for property in [material.diffuse, material.normal, material.roughness, material.transparent, material.emission] {
            property.mipFilter = .linear; property.minificationFilter = .linear
            property.magnificationFilter = .linear; property.maxAnisotropy = 16
        }
        material.shaderModifiers = [.fragment: """
        #pragma body
        if (_output.color.a < 0.5) { discard_fragment(); }
        _output.color.a = 1.0;
        """]
        fernMeshes = scene.rootNode.childNodes.compactMap { node in
            guard let geometry = node.geometry else { return nil }
            geometry.materials = [material]
            return geometry
        }
        return fernMeshes
    }

    /// Solid river-worn stone retains its mineral color, rather than using a
    /// soil photograph as a grayscale multiplier of the panorama.
    private static func addCaveBedrock(to material: SCNMaterial) {
        material.name = "cave-waterworn-bedrock"
        material.lightingModel = .physicallyBased
        material.multiply.contents = image("cave-riverbed-color.jpg")
        material.normal.contents = image("cave-riverbed-normal.jpg")
        material.normal.intensity = 0.32
        material.roughness.contents = image("cave-riverbed-rough.jpg")
        material.metalness.contents = 0
        for property in [material.multiply, material.normal, material.roughness] {
            property.mappingChannel = 1
            property.wrapS = .repeat; property.wrapT = .repeat
            property.contentsTransform = SCNMatrix4MakeScale(300 / 58, 300 / 58, 1)
            property.minificationFilter = .linear; property.magnificationFilter = .linear
            property.mipFilter = .linear; property.maxAnisotropy = 16
        }
        material.shaderModifiers = [.surface: """
        #pragma body
        float radius = length((_surface.transparentTexcoord - float2(0.5)) * 300.0);
        float nearby = 1.0 - smoothstep(45.0, 110.0, radius);
        // Cool granite matrix with the scan's rose feldspar and dark inclusions.
        float3 stone = _surface.multiply.rgb * float3(0.82, 0.98, 1.16);
        float side = sin((_surface.diffuseTexcoord.x - 0.5) * 6.2831853);
        float darkness = mix(0.045,0.012,smoothstep(-0.1,0.8,side));
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb * darkness, stone, nearby);
        _surface.emission.rgb = mix(_surface.emission.rgb * darkness, stone * 0.006, nearby);
        _surface.roughness = mix(0.92, clamp(_surface.roughness * 0.65, 0.38, 0.78), nearby);
        _surface.multiply = float4(1.0);
        _surface.normal = normalize(mix(_surface.geometryNormal, _surface.normal, nearby));
        """]
    }

    /// Object-space triplanar mapping avoids stretched seams and a pinched cap
    /// on the lamp's stalagmite. The mesh supplies its flowstone ribs.
    static func caveStalagmite(groundOrigin: SCNVector3) -> SCNMaterial {
        let material = SCNMaterial(); material.name = "cave-layered-calcite"
        material.setValue(NSValue(scnVector3: groundOrigin), forKey: "rockGroundOrigin")
        material.diffuse.contents = NSColor.gray
        material.roughness.contents = 0.75
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0
        for (key, suffix) in [("rockColor", "color"), ("rockNormal", "normal"), ("rockRough", "rough")] {
            let property = SCNMaterialProperty(contents: image("cave-riverbed-" + suffix + ".jpg") ?? NSColor.gray)
            property.wrapS = .repeat; property.wrapT = .repeat
            property.mipFilter = .linear; property.minificationFilter = .linear; property.maxAnisotropy = 16
            material.setValue(property, forKey: key)
        }
        material.shaderModifiers = [
            .geometry: """
            #pragma varyings
            float3 rockPosition;
            float3 rockAxisNormal;
            #pragma body
            out.rockPosition = _geometry.position.xyz;
            out.rockAxisNormal = _geometry.normal;
            """,
            .surface: """
            #pragma arguments
            texture2d<float> rockColor;
            texture2d<float> rockNormal;
            texture2d<float> rockRough;
            float3 rockGroundOrigin;
            #pragma body
            constexpr sampler rockSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
            float3 p = in.rockPosition / 5.0;
            float3 n = normalize(in.rockAxisNormal);
            float3 w = pow(abs(n), float3(4.0)); w /= max(dot(w,float3(1.0)),0.001);
            float3 color = rockColor.sample(rockSampler,p.zy).rgb*w.x
                + rockColor.sample(rockSampler,p.xz).rgb*w.y + rockColor.sample(rockSampler,p.xy).rgb*w.z;
            float rough = rockRough.sample(rockSampler,p.zy).r*w.x
                + rockRough.sample(rockSampler,p.xz).r*w.y + rockRough.sample(rockSampler,p.xy).r*w.z;
            float3 nx = rockNormal.sample(rockSampler,p.zy).xyz*2.0-1.0;
            float3 ny = rockNormal.sample(rockSampler,p.xz).xyz*2.0-1.0;
            float3 nz = rockNormal.sample(rockSampler,p.xy).xyz*2.0-1.0;
            float3 bump = float3(0,nx.y,nx.x)*w.x + float3(ny.x,0,ny.y)*w.y + float3(nz.x,nz.y,0)*w.z;
            float3 localNormal = normalize(n + bump*0.18);
            _surface.normal = normalize((scn_node.normalTransform * float4(localNormal,0.0)).xyz);
            float angle = atan2(in.rockPosition.z,in.rockPosition.x);
            float band = 0.5 + 0.5*sin(in.rockPosition.y*0.43 + sin(angle*3.0)*1.8 + sin(in.rockPosition.y*1.1+angle));
            float runoff = pow(0.5+0.5*sin(angle*7.0 + in.rockPosition.y*0.07),4.0);
            float grain = clamp(dot(color,float3(0.2126,0.7152,0.0722))*4.0,0.3,1.0);
            float3 calcite = mix(float3(0.36,0.28,0.19),float3(0.51,0.44,0.33),band*0.55);
            calcite *= (0.72+grain*0.35) * (1.0-runoff*0.14);
            // Use precisely the floor's planar projection, scale, tint and
            // roughness at the foot; mineral deposits emerge gradually above it.
            float2 groundUV = (in.rockPosition.xz + rockGroundOrigin.xz + 150.0) / 58.0;
            float3 bedrock = rockColor.sample(rockSampler,groundUV).rgb * float3(0.82,0.98,1.16);
            float groundRough = clamp(rockRough.sample(rockSampler,groundUV).r*0.65,0.38,0.78);
            float mineralHeight = in.rockPosition.y + sin(angle*3.0)*0.32;
            float deposit = smoothstep(0.45,8.0,mineralHeight);
            float3 stone = mix(bedrock,calcite,deposit);
            _surface.diffuse = float4(stone,1.0);
            _surface.emission.rgb = stone * mix(0.018,0.025,deposit);
            _surface.roughness = mix(groundRough,clamp(rough*0.70,0.52,0.82),deposit);
            float3 groundMap = rockNormal.sample(rockSampler,groundUV).xyz*2.0-1.0;
            float3 groundNormal = normalize(float3(groundMap.x*0.32,1.0,groundMap.y*0.32));
            float meetFloor = 1.0-smoothstep(0.02,0.65,in.rockPosition.y);
            localNormal = normalize(mix(localNormal,groundNormal,meetFloor));
            _surface.normal = normalize((scn_node.normalTransform * float4(localNormal,0.0)).xyz);
            """
        ]
        return material
    }
}
