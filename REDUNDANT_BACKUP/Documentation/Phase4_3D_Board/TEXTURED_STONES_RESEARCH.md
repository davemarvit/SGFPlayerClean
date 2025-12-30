# Textured Stones Research Document
## SGFPlayer3D - Attempts to Implement Textured Go Stones

**Document Purpose**: Comprehensive record of all attempts to implement textured Go stones in the SGFPlayer3D SceneKit-based 3D viewer. This document captures what was tried, what failed, what worked, and what remains unknown.

**Last Updated**: 2025-10-02
**Current Version**: v0.72.0 (textured stones disabled, using solid colors)

---

## Table of Contents
1. [Goals and Requirements](#goals-and-requirements)
2. [Asset Inventory](#asset-inventory)
3. [Texture Mapping Attempts](#texture-mapping-attempts)
4. [Custom Geometry Attempts](#custom-geometry-attempts)
5. [Material and Rendering Issues](#material-and-rendering-issues)
6. [What Works in 2D (Reference)](#what-works-in-2d-reference)
7. [Current Status](#current-status)
8. [Known Issues](#known-issues)
9. [Potential Solutions to Explore](#potential-solutions-to-explore)
10. [Code References](#code-references)

---

## Goals and Requirements

### Visual Goals
- Render realistic Go stones with photographic textures in 3D SceneKit view
- **White stones**: Clamshell texture variants (6 different images: `clamNH_01` through `clamNH_06`)
- **Black stones**: Slate texture (single image: `stone_blackNH`)
- Stones should have proper biconvex shape (flattened sphere, 0.486 height-to-diameter ratio)
- Textures should appear correctly mapped without distortion, stretching, or transparency artifacts

### Technical Requirements
- Use SceneKit (SCNNode, SCNGeometry, SCNMaterial)
- Support standard Go stone dimensions (black slightly larger: diameter 1.009, white: 0.995)
- Maintain proper collision detection and shadows
- Textures should work with scaled sphere geometry (currently using `SCNSphere` with Y-scale = 0.486)

---

## Asset Inventory

### White Stone Textures (Clamshell - No Highlights)
Located in: `/SGFPlayer3D/SGFPlayer3D/Assets.xcassets/`

- `clamNH_01.imageset/` - Multiple variants within this imageset:
  - `clamNH_01_alpha.png` - Version with alpha channel
  - `clamNH_01_new.png` - Alternative version
  - `clamNH_01.png` - Original version
- `clamNH_02.imageset/clamNH_02.png`
- `clamNH_03.imageset/clamNH_03.png`
- `clamNH_04.imageset/clamNH_04.png`
- `clamNH_05.imageset/clamNH_05.png`
- `clamNH_06.imageset/clamNH_06.png`

### White Stone Textures (Clamshell - With Highlights)
- `clam_01.imageset/clam_01.png`
- `clam_02.imageset/clam_02.png`
- `clam_03.imageset/clam_03.png`
- `clam_04.imageset/clam_04.png`
- `clam_05.imageset/clam_05.png`

**Note**: The "NH" suffix appears to mean "No Highlights" - these were likely created to avoid double-highlighting when SceneKit lighting is applied.

### Black Stone Textures
- `stone_blackNH.imageset/stone_blackNH.png` - Black slate texture without highlights
- `stone_black.imageset/stone_black.png` - Black slate texture with highlights

---

## Texture Mapping Attempts

### Attempt 1: Direct Texture on Scaled Sphere
**Date**: Unknown (early development)
**Location**: `ContentView3D.swift:711-730` (createStone function)

**Approach**:
```swift
private func createStone(color: Stone, at position: SCNVector3) -> SCNNode {
    let radius = color == .black ? blackStoneRadius : whiteStoneRadius
    let thicknessRatio: CGFloat = 0.486

    let sphere = SCNSphere(radius: radius)
    sphere.segmentCount = 48

    let material = SCNMaterial()
    material.diffuse.contents = color == .black ? NSColor.black : NSColor.white
    material.specular.contents = NSColor(white: 0.5, alpha: 1.0)
    sphere.materials = [material]

    let stoneNode = SCNNode(geometry: sphere)
    stoneNode.scale = SCNVector3(1.0, thicknessRatio, 1.0)  // Flatten to biconvex
    stoneNode.position = position
    stoneNode.castsShadow = true

    return stoneNode
}
```

**What was tried**: Attempted to replace solid colors with texture images:
```swift
// For white stones:
if let texture = NSImage(named: "clamNH_01") {
    material.diffuse.contents = texture
} else {
    material.diffuse.contents = NSColor.white
}

// For black stones:
if let texture = NSImage(named: "stone_blackNH") {
    material.diffuse.contents = texture
} else {
    material.diffuse.contents = NSColor.black
}
```

**Result**: **FAILED**
- Textures appeared to load (no fallback to solid color)
- Visual artifacts appeared - exact nature unclear from code alone
- Scaled sphere geometry (Y-scale = 0.486) may cause texture distortion
- UV mapping on scaled sphere not suitable for photographic textures

**Why it failed**:
- `SCNSphere` generates UV coordinates for a full sphere
- Scaling the sphere in Y-axis distorts the geometry but doesn't adjust UV coordinates
- The texture gets stretched/compressed in the Y direction
- Photographic stone textures expect 1:1 circular projection, not elliptical

---

### Attempt 2: Test Disks for Texture Debugging
**Location**: `ContentView3D.swift:1049-1101` (createLargeTestStones function - currently disabled)

**Approach**: Created large test disks to isolate texture mapping from geometry issues:

```swift
private func createLargeTestStones() {
    NSLog("DEBUG3D: Creating BIG test disks to see texture mapping clearly")

    let testRadius: CGFloat = 3.0
    let testY: CGFloat = 0.5  // Just above board

    // Test 1: Solid colored disk (for baseline)
    let solidDisk = SCNPlane(width: testRadius * 2, height: testRadius * 2)
    let solidMaterial = SCNMaterial()
    solidMaterial.diffuse.contents = NSColor.white
    // ... positioned at x=-4

    // Test 2: Textured disk with clamshell texture
    let textureDisk = SCNPlane(width: testRadius * 2, height: testRadius * 2)
    let textureMaterial = SCNMaterial()

    if let whiteImage = NSImage(named: "clamNH_01") {
        textureMaterial.diffuse.contents = whiteImage
    } else {
        textureMaterial.diffuse.contents = NSColor.white
    }

    textureMaterial.specular.contents = NSColor(white: 0.9, alpha: 1.0)
    textureMaterial.shininess = 1.0
    textureMaterial.transparency = 1.0
    textureMaterial.transparencyMode = .default
    textureMaterial.writesToDepthBuffer = true
    textureMaterial.readsFromDepthBuffer = true
    // ... positioned at x=4
}
```

**Result**: **PARTIALLY SUCCESSFUL** (for debugging)
- Confirmed that textures can load and display on flat geometry
- `SCNPlane` with texture successfully showed the clamshell image
- Proved that the issue is with 3D geometry mapping, not texture loading
- Test stones were later disabled (line 591: commented out call to `createLargeTestStones()`)

**Key Finding**: The textures themselves are valid and can be rendered - the problem is specifically with mapping them onto biconvex stone geometry.

---

### Attempt 3: Test Stones with Custom Biconvex Geometry
**Location**: `ContentView3D.swift:871-912` (createTestStone function)

**Approach**: Attempted to create textured stones using custom biconvex geometry:

```swift
private func createTestStone(radius: CGFloat, color: Stone) -> SCNNode {
    let stoneDiameter = radius * 2
    let totalStoneHeight = stoneDiameter * 0.486

    let geometry = createBiconvexStoneGeometry(
        radius: radius,
        totalHeight: totalStoneHeight,
        segments: 48
    )

    // Scale the sphere to match the stone height
    let stoneNode = SCNNode(geometry: geometry)
    let scaleY = totalStoneHeight / (radius * 2)
    stoneNode.scale = SCNVector3(1.0, scaleY, 1.0)

    let material = SCNMaterial()

    // Apply texture based on color
    switch color {
    case .white:
        if let texture = NSImage(named: "clamNH_01") {
            material.diffuse.contents = texture
        } else {
            material.diffuse.contents = NSColor.white
        }
    case .black:
        if let texture = NSImage(named: "stone_blackNH") {
            material.diffuse.contents = texture
        } else {
            material.diffuse.contents = NSColor.black
        }
    }

    material.transparencyMode = .aOne
    material.writesToDepthBuffer = false
    material.readsFromDepthBuffer = true
    material.lightingModel = .lambert
    material.specular.contents = NSColor.black  // No specular
    material.isDoubleSided = true

    geometry.materials = [material]
    return stoneNode
}
```

**Result**: **FAILED** (custom geometry abandoned)
- See "Custom Geometry Attempts" section below for details
- Function still exists but createBiconvexStoneGeometry just returns a scaled sphere
- Custom geometry code is disabled (see line 915: "GIVE UP ON CUSTOM GEOMETRY")

---

## Custom Geometry Attempts

### Attempt 1: Two Intersecting Hemispheres
**Location**: `ContentView3D.swift:914-1047` (createBiconvexStoneGeometry function)

**Goal**: Create proper biconvex geometry by manually constructing two hemispheres that meet at the equator.

**Approach**:
1. Create vertices for top hemisphere (from north pole to equator)
2. Create vertices for bottom hemisphere (from equator to south pole)
3. Duplicate vertices at equator to ensure proper closure
4. Generate triangle indices to connect all rings
5. Generate UV texture coordinates (planar projection from top-down view)

**Code Structure**:
```swift
private func createBiconvexStoneGeometry(radius: CGFloat, totalHeight: CGFloat, segments: Int) -> SCNGeometry {
    // CURRENTLY DISABLED - just returns scaled sphere:
    let sphere = SCNSphere(radius: radius)
    sphere.segmentCount = segments
    return sphere

    // DISABLED CODE BELOW:
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var texCoords: [CGPoint] = []
    var indices: [UInt16] = []

    let rings = 6  // Simplified

    // Top center vertex
    vertices.append(SCNVector3(0, radius, 0))
    normals.append(SCNVector3(0, 1, 0))
    texCoords.append(CGPoint(x: 0.5, y: 0.5))

    // TOP HEMISPHERE - rings from top down to equator
    for ring in 1...rings {
        let theta = (CGFloat(ring) / CGFloat(rings)) * (.pi / 2)
        let y = radius * cos(theta)
        let ringRadius = radius * sin(theta)

        for seg in 0..<segments {
            let phi = (CGFloat(seg) / CGFloat(segments)) * 2 * .pi
            let x = ringRadius * cos(phi)
            let z = ringRadius * sin(phi)

            vertices.append(SCNVector3(x, y, z))

            // Outward-pointing normal
            let len = sqrt(x*x + y*y + z*z)
            normals.append(SCNVector3(x/len, y/len, z/len))

            // Planar UV projection
            texCoords.append(CGPoint(x: 0.5 + x/(radius*2), y: 0.5 + z/(radius*2)))
        }
    }

    // BOTTOM HEMISPHERE - duplicates equator vertices
    for ring in 0..<rings {
        let theta = (.pi / 2) + (CGFloat(ring) / CGFloat(rings-1)) * (.pi / 2)
        let y = radius * cos(theta)
        let ringRadius = radius * sin(theta)

        for seg in 0..<segments {
            // ... same vertex/normal/texcoord generation
        }
    }

    // Bottom center vertex
    vertices.append(SCNVector3(0, -radius, 0))
    normals.append(SCNVector3(0, -1, 0))
    texCoords.append(CGPoint(x: 0.5, y: 0.5))

    // Generate triangle indices...
    // Top cap, ring connections, bottom cap

    return SCNGeometry(sources: [vertexSource, normalSource, texCoordSource],
                      elements: [element])
}
```

**Issues Encountered**:
1. **Equator Gap**: Visible seam/gap at equator where top and bottom hemispheres meet
2. **Winding Order**: Possible face orientation issues causing rendering artifacts
3. **UV Mapping**: Planar projection may not match photographic texture expectations
4. **Complexity**: Debugging vertex/index generation proved difficult

**Diagnostic Logging**:
The code includes extensive NSLog statements:
- Line 925: "createBiconvexStoneGeometry called with radius=..."
- Line 945: "Top ring N: theta=..., y=..., radius=..."
- Line 971: "Bottom ring 0 (EQUATOR DUPLICATE): theta=..."
- Line 996: "Total vertices: ..., expected: ..."
- Line 1017: "Connecting TOP ring 6 to BOTTOM ring 0"

These logs suggest the developer was trying to debug vertex connectivity at the equator.

**Result**: **ABANDONED**
- Line 915 comment: "GIVE UP ON CUSTOM GEOMETRY - just use a scaled sphere"
- Function now just returns `SCNSphere(radius: radius)` with no custom geometry
- All custom geometry code remains in place but is unreachable (after the early return)

---

### Attempt 2: Simplified Hemisphere Construction
**Evidence**: Comments in code suggest multiple iterations:
- Line 920: "SIMPLEST TEST: Two hemispheres (DISABLED FOR NOW)"
- Line 962: "BOTTOM HEMISPHERE - CREATE DUPLICATE AT EQUATOR"
- Line 963: "This will create duplicate vertices but should close the gap"

**Approach**: Create duplicate vertices at equator to ensure no gaps
- Top hemisphere ends at ring N (equator)
- Bottom hemisphere starts at ring 0 (also equator) with duplicate vertices
- Hope that duplicates eliminate the gap

**Result**: **STILL FAILED**
- Gap persisted or new artifacts appeared
- Eventually abandoned in favor of returning to scaled sphere

---

## Material and Rendering Issues

### Transparency Mode Experiments
**Location**: Various material configurations in test stone creation

**Settings Tried**:
```swift
// Attempt 1: Alpha transparency
material.transparencyMode = .aOne
material.writesToDepthBuffer = false
material.readsFromDepthBuffer = true

// Attempt 2: Default transparency
material.transparencyMode = .default  // Only fully transparent pixels
material.writesToDepthBuffer = true
material.readsFromDepthBuffer = true
```

**Issues**:
- Clamshell textures may have alpha channels that cause unexpected transparency
- Different transparency modes affect how stones layer/overlap
- Depth buffer settings critical for proper occlusion

**Finding**: The "NH" (No Highlights) textures may have been created specifically to avoid transparency issues with alpha channels.

---

### Lighting Model Experiments
**Location**: Test stone material setup (line 905)

**Settings Tried**:
```swift
material.lightingModel = .lambert  // Simple diffuse lighting
material.specular.contents = NSColor.black  // No specular highlights
```

**Rationale**:
- Stone textures already contain highlights (in non-NH versions)
- Using `.lambert` lighting avoids double-highlighting
- Disabling specular prevents additional shine artifacts
- "NH" textures designed for this lighting approach

---

### Double-Sided Rendering
**Location**: Line 907

**Setting**:
```swift
material.isDoubleSided = true  // Show both sides to debug winding
```

**Purpose**:
- Helps debug face orientation issues
- If normals are flipped, faces might be culled
- Double-sided rendering shows geometry regardless of normal direction

---

## What Works in 2D (Reference)

The 2D SwiftUI views successfully use textured stones. Here's what works there:

### SimpleBoardView.swift Implementation
**Location**: `/SGFPlayer3D/SGFPlayer3D/Views/SimpleBoardView.swift:261`

```swift
// In 2D board view, stones rendered as images
Image(stone == .white ? "clam_0\((row * 19 + col) % 5 + 1)" : "stone_black")
    .resizable()
    .frame(width: stoneSize, height: stoneSize)
```

**Key Points**:
- Uses 5 clamshell variants for white stones (clam_01 through clam_05)
- Deterministic selection based on board position: `(row * 19 + col) % 5 + 1`
- Simple 2D image rendering, no 3D geometry issues
- These are the "with highlights" versions (not NH versions)

### BoardViewport.swift Implementation
**Location**: `/SGFPlayer3D/SGFPlayer3D/BoardViewport.swift:203-207`

```swift
// Canvas-based rendering with texture selection
switch p.kind {
case .black:
    img = ctx.resolve(textures.blackStone)
case .white:
    let idx = abs((p.ix &* 73856093) ^ (p.iy &* 19349663)) % textures.clamVariants.count
    img = ctx.resolve(textures.clamVariants[idx])
}
```

**Key Points**:
- Uses hash-based random selection for white stone variants
- Canvas rendering allows sophisticated effects (jitter, collision)
- 2D projection means no UV mapping issues

**Why This Works in 2D**:
1. No geometry distortion - flat circular images
2. No UV coordinate mapping needed
3. No lighting interaction to cause artifacts
4. Direct image blitting, no material system complexity

---

## Current Status

### Working Features (v0.72.0)
✅ Solid color stones render correctly
✅ Proper biconvex shape (scaled sphere, Y = 0.486)
✅ Accurate stone sizes (black 1.009, white 0.995 diameter)
✅ Shadows cast properly from directional light
✅ Collision detection with per-stone radius
✅ Traditional Go board proportions (1.073:1 cell ratio)

### Disabled Features
❌ Textured stones (using solid NSColor.black / NSColor.white)
❌ Custom biconvex geometry (using scaled SCNSphere instead)
❌ Test stones for debugging (createLargeTestStones() not called)

### Code Status
- `createStone()` function uses solid colors only (lines 711-730)
- `createTestStone()` function exists but is never called (lines 871-912)
- `createBiconvexStoneGeometry()` exists but just returns scaled sphere (lines 914-1047)
- Test stone creation code exists but disabled (lines 1049-1138)

---

## Known Issues

### Issue 1: Texture Distortion on Scaled Sphere
**Problem**: When texture is applied to scaled sphere (Y-scale = 0.486), UV coordinates don't adjust
**Symptom**: Textures appear stretched or compressed in Y direction
**Status**: Unresolved, textures disabled
**Potential Impact**: Even with correct UVs, photographic textures may not look good on distorted geometry

### Issue 2: Custom Geometry Equator Gap
**Problem**: When building biconvex from two hemispheres, visible gap at equator
**Attempted Fix**: Duplicate vertices at equator
**Status**: Abandoned
**Note**: Extensive logging suggests developer spent significant time debugging vertex connectivity

### Issue 3: UV Mapping for Biconvex Shape
**Problem**: Photographic stone textures are circular (top-down view), but biconvex stones need proper 3D projection
**Current Approach**: Planar projection from top-down (lines 958, 984)
**Issue**: Planar projection may cause distortion around edges
**Unexplored**: Cylindrical or spherical UV mapping alternatives

### Issue 4: Transparency Artifacts
**Problem**: Some texture images have alpha channels that cause unexpected transparency
**Evidence**: Multiple transparency mode experiments
**Mitigation**: "NH" (No Highlights) versions may address this
**Status**: Unresolved

### Issue 5: Highlight Doubling
**Problem**: Texture images with baked-in highlights + SceneKit lighting = double highlights
**Solution**: Use "NH" (No Highlights) textures with Lambert lighting
**Status**: Implemented in test code, but textures still disabled

---

## Potential Solutions to Explore

### Solution 1: Custom Shader for UV Correction
**Approach**: Write Metal shader to correct UV coordinates for scaled geometry
**Pros**: Could work with existing scaled sphere approach
**Cons**: Requires Metal/shader programming expertise
**Complexity**: Medium-High
**References**: SceneKit shader modifiers, MDLMaterialPropertyNode

### Solution 2: Pre-Scale Texture Images
**Approach**: Distort texture images to match Y-scaled geometry (compress in Y by factor 0.486)
**Pros**: No code changes needed, works with current geometry
**Cons**: Textures only work for this specific scale factor, need separate asset processing
**Complexity**: Low
**Tools**: ImageMagick, sips, or similar image processing

### Solution 3: Cylindrical UV Mapping
**Approach**: Use cylindrical projection instead of spherical
**Implementation**: Modify `createBiconvexStoneGeometry()` UV coordinate generation
**Pros**: May reduce edge distortion
**Cons**: Still requires working custom geometry (currently broken)
**Complexity**: Medium

### Solution 4: Use SCNCylinder Instead of SCNSphere
**Approach**: Start with cylinder geometry, apply stone textures to top/bottom caps
**Pros**: Caps are circular, may map textures better
**Cons**: Cylinder caps are flat, not biconvex - would need custom geometry anyway
**Complexity**: Medium

### Solution 5: Fix Custom Geometry Equator Gap
**Approach**: Debug and fix the hemisphere connection issue
**Implementation**:
- Ensure vertices at equator are exactly identical (same coordinates)
- Check triangle winding order for consistent face orientation
- Verify normal directions at equator
**Pros**: Would provide proper biconvex geometry with correct UVs
**Cons**: Debugging effort is high, no guarantee of success
**Complexity**: High
**Next Steps**:
  1. Re-enable custom geometry code
  2. Log vertex positions at equator (top ring 6 and bottom ring 0)
  3. Verify they match exactly
  4. Check triangle indices connecting these rings
  5. Render with wireframe mode to visualize mesh

### Solution 6: Use SCNShape with Custom Path
**Approach**: Use SCNShape to extrude a custom 2D path that defines biconvex profile
**Pros**: SceneKit handles geometry generation
**Cons**: Extrusion may not produce correct 3D shape for biconvex stone
**Complexity**: Medium
**Reference**: SCNShape(path:extrusionDepth:)

### Solution 7: Use Model I/O to Generate Mesh
**Approach**: Use Model I/O framework (MDL) to generate parametric sphere mesh, then modify
**Pros**: More control over vertex generation, better UV support
**Cons**: Adds dependency, more complex API
**Complexity**: High
**Reference**: MDLMesh, MDLVertexDescriptor

### Solution 8: Import Pre-Made 3D Models
**Approach**: Model biconvex stone in Blender/Maya, import as .dae or .scn file
**Pros**: Full control over geometry and UVs, can test/preview outside code
**Cons**: Adds asset pipeline complexity, harder to adjust programmatically
**Complexity**: Medium
**Tools**: Blender (free), export as COLLADA (.dae)

### Solution 9: Hybrid Approach - Billboard Textures
**Approach**: Use 3D sphere for shadows/physics, but render stone faces as billboarded 2D textures
**Pros**: Guaranteed correct texture appearance (like 2D version)
**Cons**: Loses 3D appearance from side angles, hacky
**Complexity**: Low-Medium
**Implementation**: Invisible sphere for collision/shadow, textured SCNPlane as child node

---

## Code References

### Key Files
1. **ContentView3D.swift** - Main 3D rendering
   - Lines 711-730: `createStone()` - main stone creation (solid colors)
   - Lines 871-912: `createTestStone()` - test stone with texture attempts
   - Lines 914-1047: `createBiconvexStoneGeometry()` - custom geometry (disabled)
   - Lines 1049-1138: `createLargeTestStones()` - debugging test disks (disabled)

2. **SimpleBoardView.swift** - 2D reference implementation
   - Line 261: Working textured stone rendering in 2D

3. **BoardViewport.swift** - Canvas-based 2D rendering
   - Lines 203-207: Texture selection logic for white stone variants

### Asset Locations
- `/SGFPlayer3D/SGFPlayer3D/Assets.xcassets/clamNH_XX.imageset/` - White stone textures (no highlights)
- `/SGFPlayer3D/SGFPlayer3D/Assets.xcassets/clam_XX.imageset/` - White stone textures (with highlights)
- `/SGFPlayer3D/SGFPlayer3D/Assets.xcassets/stone_blackNH.imageset/` - Black stone texture (no highlights)

### Current Implementation Details

**Stone Creation** (ContentView3D.swift:711-730):
```swift
private func createStone(color: Stone, at position: SCNVector3) -> SCNNode {
    let radius = color == .black ? blackStoneRadius : whiteStoneRadius
    let thicknessRatio: CGFloat = 0.486

    let sphere = SCNSphere(radius: radius)
    sphere.segmentCount = 48

    let material = SCNMaterial()
    material.diffuse.contents = color == .black ? NSColor.black : NSColor.white
    material.specular.contents = NSColor(white: 0.5, alpha: 1.0)
    sphere.materials = [material]

    let stoneNode = SCNNode(geometry: sphere)
    stoneNode.scale = SCNVector3(1.0, thicknessRatio, 1.0)
    stoneNode.position = position
    stoneNode.castsShadow = true

    return stoneNode
}
```

**To Enable Textures** (would need to replace line 720):
```swift
// Current:
material.diffuse.contents = color == .black ? NSColor.black : NSColor.white

// To enable textures:
if color == .black {
    if let texture = NSImage(named: "stone_blackNH") {
        material.diffuse.contents = texture
    } else {
        material.diffuse.contents = NSColor.black
    }
} else {
    // For white stones, could randomize texture variant
    let variant = Int.random(in: 1...6)
    let textureName = String(format: "clamNH_%02d", variant)
    if let texture = NSImage(named: textureName) {
        material.diffuse.contents = texture
    } else {
        material.diffuse.contents = NSColor.white
    }
}
```

---

## Testing and Verification

### How to Test Texture Changes

1. **Re-enable test stones** (ContentView3D.swift line 591):
   ```swift
   // Uncomment this line:
   createLargeTestStones()
   ```

2. **Build and run** SGFPlayer3D app

3. **Look for**:
   - Two large test disks should appear (one solid white, one textured)
   - Positioned at x=-4 (solid) and x=4 (textured)
   - Labels underneath reading "SOLID DISK" and "TEXTURED DISK"

4. **What to check**:
   - Does texture load? (or fallback to white?)
   - Any transparency artifacts?
   - Does texture appear circular and undistorted?
   - How does lighting affect the texture?

### Diagnostic Build Flags

The code includes extensive logging (NSLog statements). To see these:
- Run app from Xcode
- Check Console output for lines like:
  - "DEBUG3D: Creating BIG test disks..."
  - "DEBUG: createBiconvexStoneGeometry called..."
  - "DEBUG: Top ring N: theta=..."

---

## Questions and Unknowns

### Unanswered Questions

1. **What exact visual artifacts appear when textures are enabled on scaled spheres?**
   - Stretching? Seams? Transparency holes? Color shifts?
   - No screenshots or detailed descriptions available

2. **Why was custom geometry abandoned specifically?**
   - Was it the equator gap? Performance? Texture mapping still broken?
   - Comment says "GIVE UP" but doesn't specify the final blocker

3. **Have the "NH" (No Highlights) textures been tested in 3D?**
   - Code references them but may never have been actually rendered
   - All texture attempts may have used original "clam" versions

4. **What does the equator gap actually look like?**
   - Is it a thin line? A visible hole? Z-fighting?
   - How wide is the gap?

5. **Do the texture images expect specific UV layouts?**
   - Are they radial (centered)? Rectangular?
   - What projection was used when creating the original photos?

6. **Why are there three variants of clamNH_01?**
   - `clamNH_01.png`, `clamNH_01_new.png`, `clamNH_01_alpha.png`
   - Which one is correct? What are the differences?

7. **Is there existing 3D modeling work for these stones?**
   - Were 3D models ever created in external tools?
   - Are there .dae or .scn files anywhere in the project?

---

## Recommendations for Next Steps

### Immediate Next Steps (Low-Hanging Fruit)

1. **Re-enable test stones and document exact visual issues**
   - Uncomment `createLargeTestStones()` call
   - Take screenshots of artifacts
   - Document specific problems (stretching? transparency? seams?)

2. **Try pre-scaled texture approach**
   - Use ImageMagick or sips to compress texture images vertically by 0.486
   - Save as new assets (e.g., `clamNH_01_scaled.png`)
   - Test on scaled sphere geometry
   - Quick test, minimal code changes

3. **Verify texture file formats**
   - Check if PNG files have unexpected alpha channels
   - Compare "NH" vs non-"NH" versions pixel-by-pixel
   - Ensure Contents.json is correct in imagesets

### Medium-Term Approaches

4. **Debug custom geometry with wireframe rendering**
   - Re-enable custom geometry code (remove early return)
   - Set material to wireframe mode: `material.fillMode = .lines`
   - Visually inspect equator connection
   - Log exact vertex coordinates at seam

5. **Research SceneKit UV mapping capabilities**
   - Check if SCNSphere exposes UV generation parameters
   - Investigate shader modifiers for UV correction
   - Look for SceneKit examples with textured scaled geometry

6. **Create minimal test case outside main app**
   - New Xcode project: just one textured scaled sphere
   - Isolate the problem from all other complexity
   - Easier to get help on forums with minimal repro

### Long-Term Solutions

7. **Consider 3D modeling approach**
   - Create proper biconvex stone model in Blender
   - UV unwrap correctly for circular texture
   - Export as .dae with baked UVs
   - Import into SceneKit

8. **Investigate alternative 3D rendering**
   - Could RealityKit handle this better than SceneKit?
   - Are there third-party geometry libraries?
   - Is Metal direct rendering needed?

---

## Conclusion

**Current State**: Textured stones attempted but disabled due to unresolved visual artifacts. The codebase contains multiple abandoned approaches, suggesting significant effort was invested without success.

**Root Cause**: Likely a combination of:
- UV mapping issues with scaled sphere geometry
- Texture format/alpha channel problems
- Custom geometry generation bugs (equator gap)
- Mismatch between photographic texture expectations and 3D geometry projection

**Path Forward**: The most promising approaches appear to be:
1. Pre-scale textures to match geometry (quick test)
2. Fix custom geometry equator gap (high effort, high reward)
3. Use external 3D modeling tool (reliable but adds pipeline complexity)

**Key Insight**: The 2D implementation works perfectly, which confirms:
- Textures are valid and look good when displayed correctly
- The problem is purely about 3D geometry/UV mapping
- A solution should be possible, just needs the right approach

---

**End of Document**

*This document should be updated whenever new texture rendering attempts are made. Include screenshots, error messages, and specific visual descriptions of any artifacts encountered.*
