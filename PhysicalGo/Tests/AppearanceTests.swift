import Foundation
import CoreGraphics
import ImageIO

@main struct AppearanceTests {
    static func main() throws {
        setbuf(stdout,nil)
        var checks=0
        func check(_ condition:Bool,_ message:String) { checks += 1; if !condition { fatalError(message) } }
        struct Meta:Decodable { let calibration:BoardCalibration; let threshold:Double }
        let expected:[String:[(Int,Int,Occupancy)]] = [
            "EdgeStones":[(15,0,.white),(18,5,.black)],
            "WhiteEdgeOffset":[(8,9,.white),(14,0,.white),(15,3,.black),(18,0,.black)],
            "AdjacentOffset":[(0,0,.white),(10,7,.white),(10,8,.black),(17,0,.black)],
            "CenterFlicker":[(0,0,.white),(1,0,.black),(9,7,.white),(9,8,.black),(15,3,.black),(15,4,.white),(16,3,.white),(16,4,.black),(18,0,.black)],
            "OccupiedTracking":[(3,3,.black),(9,3,.white),(12,16,.black),(13,16,.black),(13,17,.white),(14,16,.black),(14,17,.white),(15,2,.white),(15,3,.white),(15,4,.white),(15,6,.white),(15,15,.black),(15,16,.white),(16,2,.black),(16,3,.black),(16,5,.black),(16,7,.white),(16,9,.black),(16,15,.black),(16,16,.white),(17,6,.black)]
        ]
        for name in ["EdgeStones","WhiteEdgeOffset","AdjacentOffset","CenterFlicker","CameraBump","OccupiedTracking"] {
            let folder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/\(name)")
            let meta=try JSONDecoder().decode(Meta.self,from:Data(contentsOf:folder.appendingPathComponent("sample.json")))
            for filename in ["empty-reference.png","frame.png"] {
                let source=CGImageSourceCreateWithURL(folder.appendingPathComponent(filename) as CFURL,nil)!
                let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
                let cal=try AutoGridDetector.detect(image:image,size:19)?.calibration ?? meta.calibration
                let result=BoardAppearanceDetector.detect(frame:GrayFrame(image:image)!,calibration:cal,threshold:meta.threshold)
                if filename=="empty-reference.png" {
                    check(result.snapshot.stones.isEmpty,"Invented a stone on empty \(name)")
                    if name=="CenterFlicker" || name=="AdjacentOffset" {
                        check(result.signature.allSatisfy{$0 == .empty},"Clear empty board must pass verification")
                    }
                } else {
                    if let expected=expected[name] {
                        for (r,c,state) in expected { check(result.readings[r*19+c].occupancy==state,"Wrong stone in \(name): \(r),\(c)") }
                        if result.snapshot.stones.count != expected.count { print("Unexpected",name,result.readings.filter{$0.occupancy.stone != nil}.map{"\($0.row),\($0.col):\($0.occupancy)"}) }
                        check(result.snapshot.stones.count==expected.count,"Invented stones in \(name)")
                    } else {
                        let whites:Set<BoardPosition>=[BoardPosition(13,17),BoardPosition(14,17),BoardPosition(15,3),BoardPosition(15,16),BoardPosition(16,7),BoardPosition(16,16),BoardPosition(17,15),BoardPosition(17,16)]
                        let blacks:Set<BoardPosition>=[BoardPosition(12,16),BoardPosition(13,16),BoardPosition(14,16),BoardPosition(15,15),BoardPosition(16,5),BoardPosition(16,13),BoardPosition(16,15),BoardPosition(17,14)]
                        for (point,stone) in result.snapshot.stones { check((stone == .black ? blacks : whites).contains(point),"False stone on camera-bump image") }
                        check(result.snapshot.stones.count>=15,"Camera bump appearance regression")
                    }
                    var verifier=EmptyBoardVerifier()
                    for i in 0..<8 { check(!verifier.observe(result,isFresh:true,now:Double(i)),"Occupied image became an empty reference") }
                }
                print(name,filename,Dictionary(uniqueKeysWithValues:Occupancy.allCases.map { state in (state.rawValue,result.signature.filter{$0==state}.count) }))
            }
        }
        // Real USB-webcam corner removal: neighboring black stones leave too
        // few usable gap samples, although both printed axes are exposed.
        struct CornerFrame:Decodable {
            let image:String;let calibration:BoardCalibration;let threshold:Double
            let savedReadings:[IntersectionReading]
        }
        let cornerFolder=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/WebcamCornerRemoval")
        let cornerFrames=try JSONDecoder().decode([CornerFrame].self,from:Data(contentsOf:cornerFolder.appendingPathComponent("manifest.json")))
        for fixture in cornerFrames {
            let source=CGImageSourceCreateWithURL(cornerFolder.appendingPathComponent(fixture.image) as CFURL,nil)!
            let frame=GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
            let result=BoardAppearanceDetector.detect(frame:frame,calibration:fixture.calibration,threshold:fixture.threshold)
            for point in [342,343] {check(result.readings[point].occupancy == .empty,"Removed corner prisoner still uncertain in \(fixture.image): \(point)")}
            let stones=fixture.savedReadings.filter{$0.occupancy.stone != nil}
            for stone in stones {check(result.readings[stone.row*19+stone.col].occupancy==stone.occupancy,"Corner fallback erased a real stone")}
            check(result.snapshot.stones.count==stones.count,"Corner fallback invented a stone")
        }
        let cal=BoardCalibration(size:9,corners:[.init(x:0.1,y:0.1),.init(x:0.9,y:0.1),.init(x:0.9,y:0.9),.init(x:0.1,y:0.9)])!
        func synthetic(stone:UInt8?=nil,grid:Bool=true)->GrayFrame {
            let side=720
            var pixels=[UInt8](repeating:0,count:side*side)
            for y in 0..<side { for x in 0..<side { pixels[y*side+x]=UInt8(160+x/30+y/60) } }
            if grid {
                for line in 0..<9 {
                    let p=Int((0.1+0.1*Double(line))*719)
                    for j in 72...647 { for offset in -1...1 { pixels[j*side+p+offset]=35; pixels[(p+offset)*side+j]=35 } }
                }
            }
            if let stone {
                for y in 330...390 { for x in 330...390 where hypot(Double(x)-359.5,Double(y)-359.5)<30 { pixels[y*side+x]=stone } }
            }
            return GrayFrame(width:side,height:side,pixels:pixels)
        }
        let empty=BoardAppearanceDetector.detect(frame:synthetic(),calibration:cal,threshold:0.13)
        check(empty.signature.allSatisfy{$0 == .empty},"Synthetic visible empty grid failed")
        for (value,state) in [(UInt8(25),Occupancy.black),(240,.white),(178,.uncertain)] {
            let result=BoardAppearanceDetector.detect(frame:synthetic(stone:value),calibration:cal,threshold:0.13)
            check(result.readings[40].occupancy==state,"Synthetic \(state) with covered grid was misread")
            var verifier=EmptyBoardVerifier()
            for i in 0..<8 { check(!verifier.observe(result,isFresh:true,now:Double(i)),"A wood-colored occlusion was learned as empty") }
        }
        let blank=BoardAppearanceDetector.detect(frame:synthetic(grid:false),calibration:cal,threshold:0.13)
        check(!blank.signature.contains(.empty),"Wood without visible grid cannot verify emptiness")
        var verifier=EmptyBoardVerifier()
        for i in 0..<10 { check(!verifier.observe(empty,isFresh:false,now:Double(i)),"Redraws count as fresh evidence") }
        for i in 0..<4 { check(!verifier.observe(empty,isFresh:true,now:Double(i)*0.3),"Empty verification was premature") }
        check(verifier.observe(empty,isFresh:true,now:1.2),"Repeated clear empty frames should enable a reference")
        verifier.reset()
        for i in 0..<4 { _=verifier.observe(empty,isFresh:true,now:Double(i)) }
        _=verifier.observe(blank,isFresh:true,now:4)
        check(!verifier.observe(empty,isFresh:true,now:5),"Uncertainty did not reset the empty-board hypothesis")
        print("PASS: \(checks) reference-free appearance and empty-board verification checks")
    }
}
