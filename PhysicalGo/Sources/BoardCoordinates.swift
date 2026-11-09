import Foundation

/// Labels use the viewer's orientation, like the interpretation diagram. Keep
/// glyphs upright and transform only their grid anchors back to camera space.
enum BoardCoordinates {
    static func name(point:Int,size:Int,orientation:BoardOrientation)->String {
        guard size>1,size<=19,(0..<size*size).contains(point) else {return "unknown intersection"}
        let last=Double(size-1)
        let displayed=orientation.display(.init(x:Double(point%size)/last,y:Double(point/size)/last))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((displayed.x*last).rounded())])\(size-Int((displayed.y*last).rounded()))"
    }
    struct Label {let text:String;let grid:ImagePoint}
    static func labels(size:Int,orientation:BoardOrientation,margin:Double=0.55)->[Label] {
        guard [9,13,19].contains(size) else {return []}
        let letters=Array("ABCDEFGHJKLMNOPQRST"),last=Double(size-1),rim=margin
        func label(_ text:String,_ col:Double,_ row:Double)->Label {
            let p=orientation.source(ImagePoint(x:col/last,y:row/last))
            return Label(text:text,grid:ImagePoint(x:p.x*last,y:p.y*last))
        }
        var labels=[Label]()
        for i in 0..<size {
            let value=Double(i),letter=String(letters[i]),number=String(size-i)
            labels.append(label(letter,value,-rim))
            labels.append(label(letter,value,last+rim))
            labels.append(label(number,-rim,value))
            labels.append(label(number,last+rim,value))
        }
        return labels
    }
}
