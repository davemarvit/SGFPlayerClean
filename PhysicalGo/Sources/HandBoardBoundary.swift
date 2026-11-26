import Foundation

/// Explicit physical wooden-board perimeter in canonical grid coordinates.
/// This is independent of intersection calibration and laser model identity.
struct HandBoardBoundary:Codable,Equatable {
    struct Point:Codable,Equatable {let x:Double,y:Double}
    let size:Int
    let vertices:[Point] // TL, TR, BR, BL in the camera's canonical grid.
    private struct Edge:Equatable {let nx:Double,ny:Double,offset:Double,tx:Double,ty:Double,alongOffset:Double}
    private let edges:[Edge]

    init?(size:Int,vertices:[Point]) {
        guard [9,13,19].contains(size),vertices.count==4,
              vertices.allSatisfy({$0.x.isFinite && $0.y.isFinite &&
                  (-2...Double(size+1)).contains($0.x) && (-2...Double(size+1)).contains($0.y)}) else {return nil}
        for i in 0..<4 {
            let a=vertices[i],b=vertices[(i+1)%4],c=vertices[(i+2)%4]
            guard hypot(b.x-a.x,b.y-a.y)>1,
                  (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x)>0 else {return nil}
        }
        let center=Double(size-1)/2
        guard vertices[0].x<center,vertices[0].y<center,
              vertices[1].x>center,vertices[1].y<center,
              vertices[2].x>center,vertices[2].y>center,
              vertices[3].x<center,vertices[3].y>center else {return nil}
        self.size=size;self.vertices=vertices
        edges=(0..<4).map {i in
            let a=vertices[i],b=vertices[(i+1)%4],dx=b.x-a.x,dy=b.y-a.y,length=hypot(dx,dy)
            let nx = -dy/length,ny=dx/length,tx=dx/length,ty=dy/length
            return Edge(nx:nx,ny:ny,offset:-(nx*a.x+ny*a.y),tx:tx,ty:ty,alongOffset:-(tx*a.x+ty*a.y))
        }
        let n=Double(size-1)
        guard [(0.0,0.0),(n,0),(n,n),(0,n)].allSatisfy({contains(x:$0.0,y:$0.1)}) else {return nil}
    }
    func depth(x:Double,y:Double,edge:Int)->Double {
        guard (0..<4).contains(edge),x.isFinite,y.isFinite else {return -.infinity}
        let side=edges[edge]
        return side.nx*x+side.ny*y+side.offset
    }
    func minimumDepth(x:Double,y:Double)->Double {
        guard x.isFinite,y.isFinite else {return -.infinity}
        var result=Double.infinity
        for side in edges {result=min(result,side.nx*x+side.ny*y+side.offset)}
        return result
    }
    func contains(x:Double,y:Double)->Bool {minimumDepth(x:x,y:y)>=0}
    func closestEdge(x:Double,y:Double)->Int {(0..<4).min{depth(x:x,y:y,edge:$0)<depth(x:x,y:y,edge:$1)}!}
    /// Distance along an edge is used only to narrow the independently checked
    /// interior strip; outside pixels never supply its visibility proof.
    func along(x:Double,y:Double,edge:Int)->Double {
        let side=edges[edge]
        return side.tx*x+side.ty*y+side.alongOffset
    }
    private enum CodingKeys:String,CodingKey {case size,vertices}
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        guard let value=Self(size:try c.decode(Int.self,forKey:.size),vertices:try c.decode([Point].self,forKey:.vertices)) else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid physical board perimeter"))
        }
        self=value
    }
}
