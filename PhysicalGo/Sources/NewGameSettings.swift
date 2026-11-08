import SwiftUI

/// Draft settings only: an existing record's rules and setup cannot be reinterpreted.
struct NewGameSettings:View {
    @ObservedObject var model:ExperimentModel
    var showsClockSettings=true
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Picker("Rules",selection:Binding(get:{model.newGameInfo.rules ?? "Japanese"},set:{model.newGameInfo.rules=$0})) {
                ForEach(LocalGameSetup.rules,id:\.self) {Text($0).tag($0)}
            }
            Picker("Handicap",selection:$model.newGameHandicap) {
                Text("None — even game").tag(0)
                ForEach(2...9,id:\.self) {Text("\($0) black stones").tag($0)}
            }
            HStack {
                Text("Komi")
                TextField("Komi",text:Binding(get:{model.newGameInfo.komi ?? ""},set:{model.newGameInfo.komi=$0}))
                    .accessibilityLabel("Next game komi")
            }
            if !model.validNewGameKomi {Text("Enter a numeric komi before starting.").foregroundStyle(.red)}
            if model.newGameHandicap>0 {
                Text("Fixed placement · White plays first. Check the agreed komi; changing handicap does not change it automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                HandicapSetupBoard(size:model.size,handicap:model.newGameHandicap,orientation:model.orientation)
                    .frame(width:220,height:220)
            }
            if showsClockSettings {LocalClockSettingsView(settings:$model.newGameClock)}
            else {Text("Clock: \(model.newGameClock.summary). Change clock settings in Info.").font(.callout)}
            Text("Rules and handicap are fixed when recording starts. Results are entered manually in Info.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HandicapSetupBoard:View {
    let size:Int
    let handicap:Int
    let orientation:BoardOrientation
    var body:some View {
        Canvas {context,canvas in
            let side=min(canvas.width,canvas.height),margin=side*0.07,pitch=(side-2*margin)/Double(size-1)
            context.fill(Path(CGRect(x:0,y:0,width:side,height:side)),with:.color(Color(red:0.78,green:0.63,blue:0.39)))
            func point(_ x:Int,_ y:Int)->CGPoint {
                let p=orientation.display(ImagePoint(x:Double(x)/Double(size-1),y:Double(y)/Double(size-1)))
                return CGPoint(x:margin+p.x*(side-2*margin),y:margin+p.y*(side-2*margin))
            }
            var grid=Path()
            for n in 0..<size {
                grid.move(to:point(n,0));grid.addLine(to:point(n,size-1))
                grid.move(to:point(0,n));grid.addLine(to:point(size-1,n))
            }
            context.stroke(grid,with:.color(.black.opacity(0.65)),lineWidth:0.7)
            for (_,x,y) in LocalGameSetup.stones(size:size,handicap:9) {
                let p=point(x,y)
                context.fill(Path(ellipseIn:CGRect(x:p.x-1.6,y:p.y-1.6,width:3.2,height:3.2)),with:.color(.black))
            }
            for (_,x,y) in LocalGameSetup.stones(size:size,handicap:handicap) {
                let p=point(x,y),r=pitch*0.46
                context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(.black))
            }
        }.accessibilityLabel("Setup board: \(handicap) black handicap stones, oriented like the playing board")
    }
}
