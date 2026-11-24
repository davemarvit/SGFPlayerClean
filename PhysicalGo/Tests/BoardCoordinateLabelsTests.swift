import Foundation

@main struct BoardCoordinateLabelsTests {
    static func main() {
        var checks=0
        func check(_ value:Bool,_ message:String) {precondition(value,message);checks+=1}
        for size in [9,13,19] {for turns in 0..<4 {
            let orientation=BoardOrientation(turns),last=Double(size-1),margin=0.72
            let labels=BoardCoordinates.labels(size:size,orientation:orientation,margin:margin)
            check(labels.count==4*size,"Every intersection needs labels on both opposing edges")
            check(!labels.contains{$0.text=="I"},"Go labels skip I")
            let displayed=labels.map {label -> (String,Double,Double) in
                let point=orientation.display(.init(x:label.grid.x/last,y:label.grid.y/last))
                return (label.text,point.x*last,point.y*last)
            }
            for i in 0..<size {
                let letter=String(Array("ABCDEFGHJKLMNOPQRST")[i]),number=String(size-i)
                func has(_ text:String,_ x:Double,_ y:Double)->Bool {
                    displayed.contains{$0.0==text && abs($0.1-x)<1e-8 && abs($0.2-y)<1e-8}
                }
                check(has(letter,Double(i),-margin),"Top label must match displayed column")
                check(has(letter,Double(i),last+margin),"Bottom label must match displayed column")
                check(has(number,-margin,Double(i)),"Left label must match displayed row")
                check(has(number,last+margin,Double(i)),"Right label must match displayed row")
            }
        }}
        print("PASS: \(checks) four-edge coordinate checks across 9/13/19 boards and all four rotations")
    }
}
