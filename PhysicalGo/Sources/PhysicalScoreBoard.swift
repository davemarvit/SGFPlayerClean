import SwiftUI

/// Uses the same ownership field, strength scale and territory dots as SGF Player Clean.
/// The selected display determines whether to show the AI field or the editable count.
struct PhysicalScoreBoard:View {
    let session:LocalScoringSession
    let ownership:[BoardPosition:AIOwnershipEstimate]
    let likelyDead:[BoardPosition:Double]
    let finalReview:Bool
    let orientation:BoardOrientation
    var onTap:(BoardPosition)->Void = {_ in}
    var countedTerritory:[BoardPosition:Stone]? = nil

    static func displayedOwnership(_ estimates:[BoardPosition:AIOwnershipEstimate],size:Int,orientation:BoardOrientation)->[BoardPosition:AIOwnershipEstimate] {
        guard size>1 else {return [:]}
        var displayed:[BoardPosition:AIOwnershipEstimate]=[:]
        for (point,value) in estimates where (0..<size).contains(point.row) && (0..<size).contains(point.col) {
            let p=orientation.display(ImagePoint(x:Double(point.col)/Double(size-1),y:Double(point.row)/Double(size-1)))
            displayed[BoardPosition(Int((p.y*Double(size-1)).rounded()),Int((p.x*Double(size-1)).rounded()))]=value
        }
        return displayed
    }
    var body:some View {
        let territory=finalReview ? (countedTerritory ?? session.territory):[:]
        let texture=finalReview ? nil:AIOwnershipTexture.image(estimates:Self.displayedOwnership(ownership,size:session.board.size,orientation:orientation),size:session.board.size)
        GeometryReader {geometry in
            let side=min(geometry.size.width,geometry.size.height),margin=side*0.06,pitch=(side-2*margin)/Double(session.board.size-1)
            Canvas {context,_ in
                context.fill(Path(CGRect(x:0,y:0,width:side,height:side)),with:.color(Color(red:0.78,green:0.63,blue:0.39)))
                func point(_ p:BoardPosition)->CGPoint {
                    let v=orientation.display(ImagePoint(x:Double(p.col)/Double(session.board.size-1),y:Double(p.row)/Double(session.board.size-1)))
                    return CGPoint(x:margin+v.x*(side-2*margin),y:margin+v.y*(side-2*margin))
                }
                if let texture {
                    context.draw(Image(decorative:texture,scale:1),in:CGRect(x:margin-pitch/2,y:margin-pitch/2,width:pitch*Double(session.board.size),height:pitch*Double(session.board.size)))
                }
                var grid=Path()
                for i in 0..<session.board.size {
                    grid.move(to:point(BoardPosition(i,0)));grid.addLine(to:point(BoardPosition(i,session.board.size-1)))
                    grid.move(to:point(BoardPosition(0,i)));grid.addLine(to:point(BoardPosition(session.board.size-1,i)))
                }
                context.stroke(grid,with:.color(.black.opacity(0.7)),lineWidth:0.8)
                for (_,x,y) in LocalGameSetup.stones(size:session.board.size,handicap:9) {
                    let p=point(BoardPosition(y,x));context.fill(Path(ellipseIn:CGRect(x:p.x-2,y:p.y-2,width:4,height:4)),with:.color(.black))
                }
                for (position,color) in session.board.stones {
                    let p=point(position),r=pitch*0.46
                    let dead=finalReview && session.deadStones.contains(position)
                    let predicted=finalReview ? 0:(likelyDead[position] ?? 0)
                    context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.color((color == .black ? Color.black:.white).opacity(dead ? 0.35:1-0.65*predicted)))
                    if !dead && predicted>0 {
                        let radius=r*(0.25+0.3*predicted)
                        var cross=Path();cross.move(to:CGPoint(x:p.x-radius,y:p.y-radius));cross.addLine(to:CGPoint(x:p.x+radius,y:p.y+radius));cross.move(to:CGPoint(x:p.x+radius,y:p.y-radius));cross.addLine(to:CGPoint(x:p.x-radius,y:p.y+radius))
                        context.stroke(cross,with:.color((color == .black ? Color.white:.black).opacity(0.3+0.7*predicted)),lineWidth:2)
                    }
                    if dead {
                        var cross=Path();cross.move(to:CGPoint(x:p.x-r*0.7,y:p.y-r*0.7));cross.addLine(to:CGPoint(x:p.x+r*0.7,y:p.y+r*0.7));cross.move(to:CGPoint(x:p.x+r*0.7,y:p.y-r*0.7));cross.addLine(to:CGPoint(x:p.x-r*0.7,y:p.y+r*0.7))
                        context.stroke(cross,with:.color(.red),lineWidth:2)
                    }
                }
                if finalReview {
                    for (position,color) in territory {
                        let p=point(position),r=pitch*0.35
                        let ink:Color=color == .black ? .black:.white
                        context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.radialGradient(Gradient(stops:[.init(color:ink.opacity(0.96),location:0),.init(color:ink.opacity(0.9),location:0.22),.init(color:ink.opacity(0.38),location:0.58),.init(color:.clear,location:1)]),center:p,startRadius:0,endRadius:r))
                    }
                }
            }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded {tap in
                let v=orientation.source(ImagePoint(x:(tap.location.x-margin)/(side-2*margin),y:(tap.location.y-margin)/(side-2*margin)))
                let col=Int((v.x*Double(session.board.size-1)).rounded()),row=Int((v.y*Double(session.board.size-1)).rounded())
                if (0..<session.board.size).contains(row),(0..<session.board.size).contains(col) {onTap(BoardPosition(row,col))}
            }).accessibilityLabel(finalReview ? "Final scoring board, oriented like the playing board. Black and white dots mark counted territory. Unmarked empty intersections are neutral. Click groups to mark dead or alive." : "AI ownership estimate, oriented like the playing board. Black and white shading shows likely control. Unshaded areas are unsettled or neutral. Faded stones with crosses are likely to be lost.")
        }
    }
}
