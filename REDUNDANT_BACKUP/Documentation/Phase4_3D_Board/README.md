# Phase 4: 3D Board Visualization

This directory contains documentation and reference implementation for the 3D Go board using SceneKit.

## Documentation Files

### Architecture & Design
- **SPECIFICATION.md** - Detailed specifications for 3D board implementation
- **TEXTURED_STONES_RESEARCH.md** - Research and implementation notes for realistic stone textures

## Reference Implementation Files

### Core 3D Components
- **ContentView3D.swift** - Main SwiftUI view containing the 3D board
  - SceneKit integration with SwiftUI
  - Camera controls
  - Gesture handling
  - Layout management

- **SceneManager3D.swift** - SceneKit scene management
  - Scene setup and configuration
  - Node hierarchy management
  - Stone placement and animation
  - Board geometry
  - Lighting and materials
  - Camera positioning

## Key Features to Implement

### 1. SceneKit Integration
- SwiftUI + SceneKit bridge
- Scene graph management
- Camera controls (orbit, zoom, pan)
- Touch/gesture handling
- Performance optimization

### 2. Board Geometry
- Traditional kaya wood board
- Grid lines (accurate proportions)
- Star points (hoshi)
- Board edges and bevels
- Shadows and ambient occlusion

### 3. Stone Rendering
- Realistic stone materials
  - Black stones: slate/basalt texture
  - White stones: clamshell texture
- Specular highlights
- Subsurface scattering (advanced)
- Shadows and reflections
- Jitter for natural placement

### 4. Animation System
- Stone placement animation
  - Drop from above
  - Rotation during fall
  - Settle on board
  - Sound effects
- Capture animation
  - Fade out
  - Move to bowl
  - Physics-based motion
- Camera transitions
  - Smooth interpolation
  - Follow last move
  - Zoom to interesting positions

### 5. Camera System
- Orbital camera controls
- Zoom limits
- Auto-framing for board size
- Save/restore camera position
- Cinematic camera moves
- Follow mode (track last move)

### 6. Performance Optimization
- Level of Detail (LOD) for stones
- Instancing for repeated geometry
- Texture atlasing
- Culling off-screen stones
- Shadow map optimization
- Metal rendering pipeline

## Implementation Strategy

### Phase 4.1: Basic 3D Board
1. Create SceneManager3D
2. Render board geometry
3. Add grid lines
4. Implement basic camera controls

### Phase 4.2: Stone Rendering
1. Load stone textures
2. Create stone materials
3. Place stones on board
4. Add shadows

### Phase 4.3: Animation
1. Stone drop animation
2. Capture animation
3. Camera movements
4. Smooth transitions

### Phase 4.4: Polish & Performance
1. Optimize rendering
2. Add lighting effects
3. Improve materials
4. Performance profiling

## Architecture Notes

### Scene Graph Structure
```
SCNScene
├── Camera Node
│   └── Camera (perspective)
├── Light Nodes
│   ├── Ambient light
│   ├── Directional light (sun)
│   └── Spot light (accent)
├── Board Node
│   ├── Board geometry (mesh)
│   ├── Grid lines (geometry)
│   └── Star points (geometry)
└── Stones Container Node
    ├── Black stones (instances)
    └── White stones (instances)
```

### Material System
- **Board Material**: Wood texture with normal map
- **Black Stone Material**: Dark slate/basalt with slight reflectivity
- **White Stone Material**: Clamshell texture with translucency
- **Grid Material**: Black paint on wood

### Camera Controls
- **Orbit**: Rotate around board center
- **Zoom**: Move camera closer/farther
- **Pan**: Translate camera parallel to board
- **Reset**: Return to default position
- **Follow**: Auto-center on last move

## SceneKit Best Practices

1. **Performance**
   - Use instanced geometry for stones
   - Minimize draw calls
   - Use Metal renderer
   - Profile with Instruments

2. **Materials**
   - Reuse materials where possible
   - Use texture atlases
   - Compress textures appropriately
   - Consider PBR materials

3. **Lighting**
   - Use physically-based lighting
   - Limit number of dynamic lights
   - Bake ambient occlusion
   - Use shadow maps efficiently

4. **Animation**
   - Use SCNAction for simple animations
   - Implement complex animations with CAAnimation
   - Consider physics for natural motion
   - Optimize animation framerate

## Assets Required

### Textures
- Board texture (kaya wood, 2048x2048)
- Board normal map
- Black stone texture (slate/basalt)
- White stone texture (clamshell)
- Grid line texture (optional)

### Geometry
- Board mesh (could be procedural)
- Stone mesh (sphere or custom)
- Bowl mesh (for captured stones)

### Sounds (optional)
- Stone placement sound
- Stone capture sound
- Ambient sounds

## Integration with Existing Code

1. **BoardViewModel** - Shares stone positions with 3D view
2. **SGFPlayerEngine** - Game logic remains same
3. **AppModel** - Controls which view mode (2D/3D)
4. **Settings** - Add 3D-specific settings
   - Enable/disable shadows
   - Stone texture quality
   - Animation speed
   - Camera sensitivity

## Technical Considerations

### SwiftUI + SceneKit Integration
```swift
struct ContentView3D: View {
    var body: some View {
        SceneKitView(scene: sceneManager.scene)
            .gesture(dragGesture)
            .gesture(magnificationGesture)
    }
}
```

### Stone Placement
```swift
func placeStone(at position: BoardPosition, color: Stone) {
    let node = createStoneNode(color: color)
    let worldPos = boardToWorld(position)

    // Animate stone drop
    node.position = SCNVector3(worldPos.x, 10, worldPos.z)
    board.addChildNode(node)

    let dropAction = SCNAction.moveTo(y: 0, duration: 0.3)
    node.runAction(dropAction)
}
```

### Camera Orbit
```swift
func rotateCamera(dx: CGFloat, dy: CGFloat) {
    cameraNode.eulerAngles.y += Float(dx * 0.01)
    cameraNode.eulerAngles.x += Float(dy * 0.01)

    // Clamp vertical rotation
    cameraNode.eulerAngles.x = max(-Float.pi/4,
                                    min(Float.pi/4,
                                        cameraNode.eulerAngles.x))
}
```

## Future Enhancements

- VR support (if needed)
- Advanced physics for stone collisions
- Multiplayer with live opponents
- Replay with cinematic camera
- Board themes (different wood types)
- Stone themes (different materials)
- Particle effects for captures
- Screen space reflections
