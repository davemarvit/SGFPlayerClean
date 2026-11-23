import Foundation
import ImageIO
import CoreImage
@main struct AIWhiteD7GlareTests {
 struct Sample:Decodable {let image:String;let whitePresent:Bool;let calibration:BoardCalibration;let referenceCalibration:BoardCalibration;let threshold:Double}
 static func main() throws {
  setbuf(stdout,nil)
  func check(_ value:Bool,_ message:String) {if !value {print("FAIL",message);exit(1)}}
  let root=URL(fileURLWithPath:"PhysicalGo/Tests/Fixtures/AIWhiteD7Glare")
  let samples=try JSONDecoder().decode([Sample].self,from:Data(contentsOf:root.appendingPathComponent("cases.json")))
  func image(_ name:String)->CGImage {CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL,nil)!,0,nil)!}
  let ref=GrayFrame(image:image("reference.png"))!,context=CIContext();var checks=0
  let old:Set<Int>=[60,72,300,288,320],added:Set<Int>=[318,281,337,319,299,317,297]
  for sample in samples {
   let source=CIImage(cgImage:image(sample.image))
   for brightness in [-0.003,0,0.003] {for offset in [-0.5,0,0.5] {
    let photo=context.createCGImage(source.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:brightness]),from:source.extent)!
    let cal=BoardCalibration(size:19,corners:sample.calibration.corners.map {.init(x:$0.x+offset/1919,y:$0.y-offset/1079)})!
    let raw=BoardDetector.detect(frame:GrayFrame(image:photo)!,reference:ref,calibration:cal,threshold:sample.threshold,referenceCalibration:sample.referenceCalibration)!
    check(sample.whitePresent ? raw.signature[297] == .white : raw.signature[297].stone==nil,"D7 failed: \(sample.image), \(brightness), \(offset), \(raw.readings[297])");checks+=1
    let occupied=sample.whitePresent ? old.union(added):old
    for i in raw.signature.indices where !occupied.contains(i) {check(raw.signature[i].stone==nil,"Invented stone \(i), \(sample.image)");checks+=1}
    let black:Set<Int>=sample.whitePresent ? [60,72,300,318,281,337]:[60,72,300]
    for i in occupied {check(raw.signature[i].stone==nil || raw.signature[i] == (black.contains(i) ? .black:.white),"Recolored stone");checks+=1}
   }}
  }
  let empty=BoardDetector.detect(frame:ref,reference:ref,calibration:samples[0].referenceCalibration,threshold:0.13)!
  check(empty.snapshot.stones.isEmpty,"Empty reference gained stones");checks+=1
  print("PASS: \(checks) D7 glare checks across real positive/negative frames, brightness and subpixel perturbations")
 }
}
