import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct VisionTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1
            guard condition() else { fatalError("FAIL: \(message)") }
        }
        let corners = [ImagePoint(x: 0.10,y: 0.12), ImagePoint(x: 0.86,y: 0.18), ImagePoint(x: 0.94,y: 0.90), ImagePoint(x: 0.06,y: 0.83)]
        let perspective = BoardCalibration(size: 19, corners: corners)!
        for (i, rc) in [(0,0),(18,0),(18,18),(0,18)].enumerated() {
            let p = perspective.point(col: Double(rc.0),row: Double(rc.1))
            check(abs(p.x-corners[i].x)<1e-8 && abs(p.y-corners[i].y)<1e-8, "Perspective maps corner \(i)")
        }
        // A projective mapping known independently from the fitted solver.
        func mapping(_ u: Double, _ v: Double) -> ImagePoint { .init(x: (0.65*u+0.05*v+0.12)/(0.12*u+0.08*v+1),y: (0.03*u+0.70*v+0.10)/(0.12*u+0.08*v+1)) }
        let known = BoardCalibration(size: 19, corners: [mapping(0,0),mapping(1,0),mapping(1,1),mapping(0,1)])!
        let center = known.point(col: 7,row: 11), expected = mapping(7.0/18,11.0/18)
        check(abs(center.x-expected.x)<1e-8 && abs(center.y-expected.y)<1e-8, "Interior uses projective mapping")
        check(BoardCalibration(size: 19, corners: [corners[0],corners[2],corners[1],corners[3]]) == nil, "Crossed corners rejected")
        check(BoardCalibration(size: 19, corners: Array(corners.reversed())) == nil, "Reverse order rejected")
        check(BoardCalibration(size: 19, corners: Array(repeating: corners[0],count: 4)) == nil, "Degenerate rejected")
        check(BoardCalibration(size: 8,corners: corners) == nil, "Unsupported size rejected")
        let width = 720, height = 720
        var baseline = [UInt8](repeating: 155,count: width*height)
        // Uneven but stationary lighting.
        for y in 0..<height { for x in 0..<width { baseline[y*width+x] = UInt8(135+x/18+y/36) } }
        let straight = [ImagePoint(x:0.1,y:0.1),ImagePoint(x:0.9,y:0.1),ImagePoint(x:0.9,y:0.9),ImagePoint(x:0.1,y:0.9)]
        for size in [9,13,19] {
            let calibration = BoardCalibration(size:size,corners:straight)!
            let reference = GrayFrame(width:width,height:height,pixels:baseline)
            var pixels = baseline
            let positions: [(Int,Int,Occupancy)] = [(0,0,.black),(size-1,0,.white),(0,size-1,.white),(size-1,size-1,.black),(size/2,size/2,.black)]
            let radius = 0.8*Double(width-1)/Double(size-1)*0.44
            for (col,row,state) in positions {
                let p = calibration.point(col:Double(col),row:Double(row))
                let cx = p.x*Double(width-1), cy = p.y*Double(height-1)
                for y in max(0,Int(cy-radius))...min(height-1,Int(cy+radius)) {
                    for x in max(0,Int(cx-radius))...min(width-1,Int(cx+radius)) where hypot(Double(x)-cx,Double(y)-cy)<radius {
                        pixels[y*width+x] = state == .black ? 22 : 241
                    }
                }
            }
            let frame = GrayFrame(width:width,height:height,pixels:pixels)
            let result = BoardDetector.detect(frame:frame,reference:reference,calibration:calibration,threshold:0.13)!
            check(result.snapshot.stones.count == 5, "\(size): exact stone count")
            for (col,row,state) in positions { check(result.readings[row*size+col].occupancy == state,"\(size): orientation and color \(row),\(col)") }
            check(!result.signature.contains(.uncertain),"\(size): clear fixture classified")
            let sgf = result.positionSGF()!
            let game = SGFGame.from(tree: try SGFParser.parse(text:sgf))
            check(game.setup.count == 5, "\(size): shared SGF parser reads setup")
            check(game.moves.isEmpty,"Position export does not invent moves")
            var stability = ObservationStability()
            for _ in 0..<4 { check(!stability.update(result), "Wait for stable frames") }
            check(stability.update(result),"Fifth consistent frame stable")
            let empty = BoardDetector.detect(frame:reference,reference:reference,calibration:calibration,threshold:0.13)!
            check(!stability.update(empty),"Changed board resets stability")
            let unknown = BoardObservation(readings:[.init(row:0,col:0,occupancy:.uncertain,confidence:0,delta:0)],size: size)
            check(unknown.positionSGF() == nil, "Unknown does not silently export as empty")
            check(!stability.update(unknown),"Unknown resets stability")
            check(result.positionSGF(labels:[0:.empty]) != sgf,"Manual labels affect position export")
            if size == 19 {
                let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/.build/Fixtures")
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                for (name,bytes) in [("empty",baseline),("stones",pixels)] {
                    let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
                    let roundtrip = GrayFrame(image:image)!
                    check(roundtrip.pixels == bytes,"CGImage orientation survives grayscale conversion")
                    let dest = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name+".png") as CFURL,UTType.png.identifier as CFString,1,nil)!
                    CGImageDestinationAddImage(dest,image,nil); check(CGImageDestinationFinalize(dest),"Write reproducible image fixture")
                }
            }
        }
        // Robustness checks independent of the real-board regression image.
        let calibration = BoardCalibration(size: 19, corners: straight)!
        let reference = GrayFrame(width: width, height: height, pixels: baseline)
        let brighter = GrayFrame(width: width, height: height, pixels: baseline.map { UInt8(min(255,Int($0)+12)) })
        let brightEmpty = BoardDetector.detect(frame: brighter, reference: reference, calibration: calibration, threshold: 0.13)!
        check(brightEmpty.signature.allSatisfy { $0 == .empty }, "Modest uniform exposure drift does not invent white stones")
        let tooBright = GrayFrame(width: width, height: height, pixels: baseline.map { UInt8(min(255,Int($0)+45)) })
        let invalidReference = BoardDetector.detect(frame: tooBright, reference: reference, calibration: calibration, threshold: 0.13)!
        check(invalidReference.lightingBlocked && invalidReference.signature.allSatisfy { $0 == .uncertain }, "Featureless view under changed lighting is withheld")
        func disk(_ input: [UInt8], col: Int, row: Int, value: UInt8, radius: Double = 12) -> [UInt8] {
            var pixels = input
            let p = calibration.point(col: Double(col), row: Double(row))
            let cx = p.x*Double(width-1), cy = p.y*Double(height-1)
            for y in max(0,Int(cy-radius))...min(height-1,Int(cy+radius)) {
                for x in max(0,Int(cx-radius))...min(width-1,Int(cx+radius)) where hypot(Double(x)-cx,Double(y)-cy) < radius { pixels[y*width+x] = value }
            }
            return pixels
        }
        let lightWood = [UInt8](repeating: 218, count: width*height)
        var whiteAndBlack = disk(lightWood, col: 0, row: 9, value: 241)
        whiteAndBlack = disk(whiteAndBlack, col: 18, row: 9, value: 24)
        let brightBoard = BoardDetector.detect(frame: .init(width:width,height:height,pixels:whiteAndBlack), reference: .init(width:width,height:height,pixels:lightWood), calibration:calibration, threshold:0.13)!
        check(brightBoard.readings[9*19].occupancy == .white, "White edge stone on bright wood remains detectable below old absolute threshold")
        check(brightBoard.readings[9*19+18].occupancy == .black, "Black edge stone on bright wood remains detectable")
        check(brightBoard.snapshot.stones.count == 2 && !brightBoard.signature.contains(.uncertain), "Bright-board fixture has exactly two stones")
        let shadow = disk(lightWood, col: 9, row: 9, value: 193)
        let shadowResult = BoardDetector.detect(frame:.init(width:width,height:height,pixels:shadow),reference:.init(width:width,height:height,pixels:lightWood),calibration:calibration,threshold:0.13)!
        check(shadowResult.readings[9*19+9].occupancy == .uncertain, "Moderate local shadow is not promoted to a black stone")
        let background = [UInt8](repeating:160,count:width*height)
        let palePatch = disk(background, col:9, row:9, value:174)
        let paleResult = BoardDetector.detect(frame:.init(width:width,height:height,pixels:palePatch),reference:.init(width:width,height:height,pixels:background),calibration:calibration,threshold:0.13)!
        check(paleResult.snapshot.stones.isEmpty,"Weak local brightness change is not promoted to a stone")
        var inkReference = background
        // Several old sample positions land on ink; simulate small line-edge changes.
        for row in 0..<19 { for col in 0..<19 {
            for dy in [-2, -1, 1, 2] {
                let p = calibration.point(col:Double(col)+0.075,row:Double(row)+Double(dy)*0.075)
                let x = Int((p.x*Double(width-1)).rounded()), y = Int((p.y*Double(height-1)).rounded())
                inkReference[y*width+x] = 35
            }
        } }
        let inkResult = BoardDetector.detect(frame:.init(width:width,height:height,pixels:background),reference:.init(width:width,height:height,pixels:inkReference),calibration:calibration,threshold:0.13)!
        check(inkResult.signature.allSatisfy { $0 == .empty }, "Dark grid-reference outliers cannot become false white stones")

        struct SavedSample: Decodable { let calibration: BoardCalibration; let threshold: Double }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("PhysicalGo/Tests/Fixtures/EdgeStones")
        let saved = try JSONDecoder().decode(SavedSample.self, from: Data(contentsOf:fixture.appendingPathComponent("sample.json")))
        func loadReal(_ name: String) -> GrayFrame {
            let source = CGImageSourceCreateWithURL(fixture.appendingPathComponent(name) as CFURL,nil)!
            return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
        }
        let actual = BoardDetector.detect(frame:loadReal("frame.png"),reference:loadReal("empty-reference.png"),calibration:saved.calibration,threshold:saved.threshold)!
        check(actual.readings[15*19].occupancy == .white, "Real board: white A4 detected")
        check(actual.readings[18*19+5].occupancy == .black, "Real board: black F1 detected")
        check(actual.snapshot.stones.count == 2, "Real board: no invented stones")
        check(!actual.signature.contains(.uncertain), "Real board: all 359 empty intersections remain clear")
        let original = loadReal("frame.png")
        var dimPixels = original.pixels
        for i in dimPixels.indices {
            let x = Double(i % original.width)/Double(original.width)
            dimPixels[i] = UInt8(Double(original.pixels[i]) * (0.5 + 0.22*x))
        }
        let dim = GrayFrame(width:original.width,height:original.height,pixels:dimPixels)
        let changed = BoardDetector.detect(frame:dim,reference:loadReal("empty-reference.png"),calibration:saved.calibration,threshold:saved.threshold)!
        check(changed.notice != nil && !changed.lightingBlocked, "Uneven dimming triggers a readable current-light view")
        check(changed.signature.filter { $0 == .empty }.count >= 320 && changed.snapshot.stones.count <= 2, "Dim room does not create spurious stones across the board")
        check(changed.readings[18*19+5].occupancy == .black, "Black stone remains visible after the lighting change")
        let uniformDim=original.scaledLuminance(by:0.64)
        let compensated=BoardDetector.detect(frame:uniformDim,reference:loadReal("empty-reference.png"),calibration:saved.calibration,threshold:saved.threshold)!
        check(!compensated.lightingBlocked && compensated.signature==actual.signature, "Uniform dimming preserves both stones and every empty point")
        let darkFolder=fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Captures/Samples/Whole board rings Physical Go Sample 2026-11-03 01-27-54")
        if FileManager.default.fileExists(atPath:darkFolder.path) {
            struct Pair: Decodable { let calibration, referenceCalibration:BoardCalibration; let threshold:Double }
            let pair=try JSONDecoder().decode(Pair.self,from:Data(contentsOf:darkFolder.appendingPathComponent("sample.json")))
            func loadDark(_ name:String)->GrayFrame {
                let source=CGImageSourceCreateWithURL(darkFolder.appendingPathComponent(name) as CFURL,nil)!
                return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
            }
            let live=BoardDetector.detect(frame:loadDark("frame.png"),reference:loadDark("empty-reference.png"),
                calibration:pair.calibration,threshold:pair.threshold,referenceCalibration:pair.referenceCalibration)!
            check(!live.lightingBlocked && live.signature.filter{$0 == .empty}.count>=285,"Dim game: exposed wood remains visible")
            check([13,350,351,352,353,354,355].allSatisfy{live.readings[$0].occupancy.stone==nil},"Dim game: shadowed wood is never marked as a stone")
            check(live.readings[31].occupancy == .white,"Dim game: retained white B13 stays visible")
        }
        let actualGame = SGFGame.from(tree:try SGFParser.parse(text:actual.positionSGF()!))
        check(actualGame.setup.count == 2 && actualGame.moves.isEmpty, "Real board: two setup stones export without invented move history")
        // Latest live regression: automatic grid, offset white A5, spatial exposure drift.
        let offsetFolder=fixture.deletingLastPathComponent().appendingPathComponent("WhiteEdgeOffset")
        let offsetSaved=try JSONDecoder().decode(SavedSample.self,from:Data(contentsOf:offsetFolder.appendingPathComponent("sample.json")))
        func loadOffset(_ name:String)->GrayFrame {
            let source=CGImageSourceCreateWithURL(offsetFolder.appendingPathComponent(name) as CFURL,nil)!
            return GrayFrame(image:CGImageSourceCreateImageAtIndex(source,0,nil)!)!
        }
        let offsetFrame=loadOffset("frame.png"),offsetReference=loadOffset("empty-reference.png")
        let expectedStones:[(Int,Int,Occupancy)]=[(14,0,.white),(8,9,.white),(18,0,.black),(15,3,.black)]
        for (dx,dy) in [(0.0,0.0),(-1.0,0.0),(1.0,0.0),(0.0,-1.0),(0.0,1.0)] {
            let corners=offsetSaved.calibration.corners.map { ImagePoint(x:$0.x+dx/Double(offsetFrame.width-1),y:$0.y+dy/Double(offsetFrame.height-1)) }
            let calibration=BoardCalibration(size:19,corners:corners)!
            let result=BoardDetector.detect(frame:offsetFrame,reference:offsetReference,calibration:calibration,threshold:offsetSaved.threshold)!
            for (row,col,state) in expectedStones { check(result.readings[row*19+col].occupancy==state,"Offset fixture (\(dx),\(dy)): correct \(state) at \(row),\(col)") }
            check(result.snapshot.stones.count==4,"Offset fixture: no false stones")
            if dx==0 && dy==0 {
                check(result.signature.filter { $0 == .uncertain }.count<=2,"Offset fixture: reduce background uncertainty without masking unresolved points")
                check(result.positionSGF()==nil,"Unresolved background points still prevent unverified SGF export")
                let labels=Dictionary(uniqueKeysWithValues:result.readings.enumerated().filter { $0.element.occupancy == .uncertain }.map { ($0.offset,Occupancy.empty) })
                let game=SGFGame.from(tree:try SGFParser.parse(text:result.positionSGF(labels:labels)!))
                check(game.setup.count==4 && game.moves.isEmpty,"Verified manual empty labels permit four-stone position export")
            }
        }
        // A smooth brightness gradient should be removed using the spaces between stones.
        let flat=[UInt8](repeating:165,count:width*height)
        var gradient=flat
        for y in 0..<height { for x in 0..<width { gradient[y*width+x]=UInt8(165+Int(14*Double(x)/Double(width-1)-8*Double(y)/Double(height-1))) } }
        let gradientReference=GrayFrame(width:width,height:height,pixels:flat)
        let gradientResult=BoardDetector.detect(frame:.init(width:width,height:height,pixels:gradient),reference:gradientReference,calibration:calibration,threshold:0.13)!
        check(gradientResult.signature.allSatisfy { $0 == .empty },"Spatial brightness drift does not invent stones or uncertainty")
        let pitch=0.8*Double(width-1)/18
        for (col,row,state) in [(0,9,Occupancy.white),(18,9,.white),(9,0,.black),(9,18,.black)] {
            let center=calibration.point(col:Double(col)+(col==18 ? -0.22 : 0.22),row:Double(row)+(row==18 ? -0.22 : 0.22))
            let cx=center.x*Double(width-1),cy=center.y*Double(height-1),radius=pitch*0.36
            var pixels=gradient
            for y in max(0,Int(cy-radius))...min(height-1,Int(cy+radius)) { for x in max(0,Int(cx-radius))...min(width-1,Int(cx+radius)) where hypot(Double(x)-cx,Double(y)-cy)<radius {
                pixels[y*width+x]=state == .white ? 235 : 25
            } }
            let result=BoardDetector.detect(frame:.init(width:width,height:height,pixels:pixels),reference:gradientReference,calibration:calibration,threshold:0.13)!
            check(result.readings[row*19+col].occupancy==state,"Off-center \(state) recognized at edge \(col),\(row)")
            check(result.snapshot.stones.count==1,"Offset search does not claim neighboring points")
        }
        let speck=disk(flat,col:9,row:9,value:245,radius:3)
        let speckResult=BoardDetector.detect(frame:.init(width:width,height:height,pixels:speck),reference:gradientReference,calibration:calibration,threshold:0.13)!
        check(speckResult.snapshot.stones.isEmpty,"Isolated bright speck does not trigger a displaced stone search")
        let largePatch=disk(flat,col:9,row:9,value:205,radius:80)
        let patchResult=BoardDetector.detect(frame:.init(width:width,height:height,pixels:largePatch),reference:gradientReference,calibration:calibration,threshold:0.13)!
        check(patchResult.readings[9*19+9].occupancy == .uncertain,"Excessive local brightness change is not a white stone")
        let small = GrayFrame(width:2,height:2,pixels:[0,0,0,0])
        let large = GrayFrame(width:3,height:3,pixels:Array(repeating:0,count:9))
        check(BoardDetector.detect(frame:small,reference:large,calibration:perspective,threshold:0.13) == nil,"Reject mismatched dimensions")
        count += try PlacementTests.run()
        count += try RectificationTests.run()
        print("PASS: \(count) vision, geometry, stability and shared SGF checks. Includes the saved edge-stone regression and synthetic lighting/contrast cases; broader live accuracy remains unmeasured.")
    }
}
