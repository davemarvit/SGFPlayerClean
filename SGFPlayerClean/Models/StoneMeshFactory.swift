import SceneKit

class StoneMeshFactory {
    
    /// Generates a custom SCNGeometry for a Go stone with top-down (Planar) UV mapping.
    static func createStoneGeometry(radius: CGFloat, thickness: CGFloat) -> SCNGeometry {
        let steps = 32 // Horizontal resolution (higher = smoother roundness)
        let layers = 16 // Vertical resolution (higher = smoother curve)
        
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texCoords: [CGPoint] = []
        var indices: [Int32] = []
        
        // 1. Generate Vertices & UVs
        for i in 0...layers {
            // Calculate vertical slice (latitude)
            // theta goes from -PI/2 (bottom) to PI/2 (top)
            let theta = Float(i) * Float.pi / Float(layers) - (Float.pi / 2)
            let y = sin(theta) * Float(thickness) * 0.5
            let ringRadius = cos(theta) * Float(radius)
            
            for j in 0...steps {
                // Calculate horizontal position (longitude)
                let phi = Float(j) * 2 * Float.pi / Float(steps)
                
                let x = cos(phi) * ringRadius
                let z = sin(phi) * ringRadius
                
                // A. Position
                vertices.append(SCNVector3(x, y, z))
                
                // B. Normal (Same as position for a sphere/ellipsoid, normalized)
                let normal = SCNVector3(x, y / Float(thickness) * Float(radius) * 2, z).normalized()
                normals.append(normal)
                
                // C. UV Mapping (CRITICAL STEP)
                // Instead of wrapping around, we project from the top down.
                // Map X/Z range [-radius, radius] -> [0, 1]
                let u = CGFloat(x / Float(radius) * 0.5 + 0.5)
                let v = CGFloat(z / Float(radius) * 0.5 + 0.5) // Flip V if texture is upside down
                
                // Clamp UVs to prevent edge bleeding artifacts
                let clampedU = min(max(u, 0.01), 0.99)
                let clampedV = min(max(v, 0.01), 0.99)
                
                // Only apply texture to the top half to avoid bottom mirroring weirdness
                if y > -0.1 {
                    texCoords.append(CGPoint(x: clampedU, y: clampedV))
                } else {
                    // Bottom half gets a generic white/black pixel (center of texture)
                    texCoords.append(CGPoint(x: 0.5, y: 0.5))
                }
            }
        }
        
        // 2. Generate Indices (Triangles)
        for i in 0..<layers {
            for j in 0..<steps {
                let current = Int32(i * (steps + 1) + j)
                let next = Int32(current + 1)
                let above = Int32((i + 1) * (steps + 1) + j)
                let aboveNext = Int32(above + 1)
                
                // Triangle 1
                indices.append(current)
                indices.append(next)
                indices.append(above)
                
                // Triangle 2
                indices.append(next)
                indices.append(aboveNext)
                indices.append(above)
            }
        }
        
        // 3. Create Geometry Sources
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let uvSource = SCNGeometrySource(textureCoordinates: texCoords)
        
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])
        return geometry
    }
}

extension SCNVector3 {
    func normalized() -> SCNVector3 {
        let len = sqrt(x*x + y*y + z*z)
        if len == 0 { return self }
        return SCNVector3(x/len, y/len, z/len)
    }
}
