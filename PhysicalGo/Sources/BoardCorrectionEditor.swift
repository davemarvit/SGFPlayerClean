import SwiftUI

struct BoardCorrectionEditor: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var corrections: ManualBoardCorrections
    @State private var selection: Int?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Check the board photo").font(.title2.bold())
            Text("Move detection is paused while you check this photo. Select an intersection and label what is there. Labels apply only to this photograph.")
            if let snapshot=model.correctionSnapshot {
                HStack(alignment:.top,spacing:18) {
                    CorrectionBoard(snapshot:snapshot,values:corrections.displayedValues,selection:$selection,
                                    highlightedPoints:RecordingClarity.checkPoints(recorder:model.recorder,observation:snapshot.observation).subtracting(corrections.edits.keys))
                        .aspectRatio(1,contentMode:.fit).frame(width:540,height:540)
                    VStack(alignment:.leading,spacing:12) {
                        Text(selection == nil ? "Select a point on the board" : "Selected intersection").font(.headline)
                        CorrectionPhoto(snapshot:snapshot,selection:selection).frame(width:240,height:240)
                        ForEach(ManualBoardCorrections.Choice.allCases,id:\.self) {choice in
                            Button {
                                if let selection { corrections.set(choice,at:selection) }
                            } label: {
                                HStack {
                                    Image(systemName:choice == .automatic ? "camera" : choice == .empty ? "circle" : "circle.fill")
                                        .foregroundStyle(choice == .white ? Color.gray : Color.primary)
                                    Text(choice.label)
                                    Spacer()
                                    if let selection, choice.occupancy == corrections.displayedValues[selection] {
                                        Image(systemName:"checkmark")
                                    }
                                }.frame(maxWidth:.infinity)
                            }.disabled(selection == nil || model.savingCorrections)
                        }
                        Text("Purple rings mark labels on this photo. Future camera readings are never overridden; new stones remain detectable.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Orange rings mark camera readings that need checking. Select a ring and confirm Black, White, or Empty from the photo; it turns purple when corrected.").font(.callout)
            Text("Your explicit labels and the original images are saved locally for recognition testing. Unedited points are not treated as verified labels.")
                .font(.callout).foregroundStyle(.secondary)
            if model.playMode == .local && model.recorder.state == .paused {
                Text("Clocks stay paused. Saving labels alone does not save a move or resolve a review.").font(.callout)
            }
            if !model.correctionError.isEmpty {Text(model.correctionError).foregroundStyle(.red)}
            if let guidance=model.photoReviewGuidance {Text(guidance).font(.callout)}
            if let action=model.photoReviewAction {
                Text("Check the whole photo before confirming. This resolves only the current review; clocks stay paused.").font(.callout)
                Button(action.title) {model.finishBoardCorrection(confirmReview:true)}
                    .buttonStyle(.borderedProminent).disabled(model.savingCorrections)
            }
            Button("Retake photo") {model.cancelBoardCorrection();model.beginBoardCorrection()}.disabled(model.savingCorrections)
            HStack {
                Button("Clear photo labels") {corrections.useCameraEverywhere()}
                    .disabled(corrections.displayedValues.isEmpty || model.savingCorrections)
                Spacer()
                if model.savingCorrections {ProgressView().controlSize(.small); Text("Saving images…")}
                Button("Cancel") {model.cancelBoardCorrection()}.keyboardShortcut(.cancelAction).disabled(model.savingCorrections)
                Button("Save photo labels") {model.finishBoardCorrection()}
                    .keyboardShortcut(.defaultAction).disabled(model.savingCorrections)
            }
        }.padding(22).frame(width:850)
            .onAppear {selection=model.correctionInitialPoint}
    }
}

private struct CorrectionBoard: View {
    let snapshot: BoardCorrectionSnapshot
    let values: [Int: Occupancy]
    @Binding var selection: Int?
    var highlightedPoints:Set<Int>=[]
    private var n:Int {snapshot.observation.size}
    private var orientation:BoardOrientation {BoardOrientation(snapshot.quarterTurns)}
    private func state(_ i:Int)->Occupancy {values[i] ?? snapshot.observation.readings[i].occupancy}
    private func label(_ i:Int)->String {
        let p=orientation.display(.init(x:Double(i%n)/Double(n-1),y:Double(i/n)/Double(n-1)))
        return "\(Array("ABCDEFGHJKLMNOPQRST")[Int((p.x*Double(n-1)).rounded())])\(n-Int((p.y*Double(n-1)).rounded())), \(state(i).rawValue)"
    }
    var body: some View {
        GeometryReader {g in
            let side=min(g.size.width,g.size.height),pad=side*0.045,step=(side-2*pad)/Double(n-1)
            Canvas {ctx,_ in
                ctx.fill(Path(roundedRect:CGRect(x:0,y:0,width:side,height:side),cornerRadius:8),with:.color(Color(red:0.80,green:0.66,blue:0.43)))
                var grid=Path()
                for i in 0..<n {
                    let p=pad+Double(i)*step
                    grid.move(to:.init(x:pad,y:p));grid.addLine(to:.init(x:side-pad,y:p))
                    grid.move(to:.init(x:p,y:pad));grid.addLine(to:.init(x:p,y:side-pad))
                }
                ctx.stroke(grid,with:.color(.black.opacity(0.6)),lineWidth:1)
                let stars=n==19 ? [3,9,15] : n==13 ? [3,6,9] : [2,4,6]
                for r in stars {for c in stars where n==19 || (r==n/2)==(c==n/2) {
                    ctx.fill(Path(ellipseIn:CGRect(x:pad+Double(c)*step-2,y:pad+Double(r)*step-2,width:4,height:4)),with:.color(.black))
                }}
                for i in 0..<n*n {
                    let p=orientation.display(.init(x:Double(i%n)/Double(n-1),y:Double(i/n)/Double(n-1)))
                    let center=CGPoint(x:pad+p.x*(side-2*pad),y:pad+p.y*(side-2*pad))
                    let stone=Path(ellipseIn:CGRect(x:center.x-step*0.43,y:center.y-step*0.43,width:step*0.86,height:step*0.86))
                    let value=state(i)
                    if value == .black || value == .white {
                        ctx.fill(stone,with:.color(value == .black ? .black : .white))
                        ctx.stroke(stone,with:.color(.black.opacity(0.5)),lineWidth:0.5)
                    } else if value == .uncertain {
                        ctx.draw(Text("?").font(.system(size:step*0.7,weight:.bold)).foregroundColor(.orange),at:center)
                    }
                    if highlightedPoints.contains(i) {ctx.stroke(stone,with:.color(.orange),lineWidth:3.5)}
                    if values[i] != nil {ctx.stroke(stone,with:.color(.purple),lineWidth:3)}
                    if selection == i {
                        ctx.stroke(Path(CGRect(x:center.x-step*0.50,y:center.y-step*0.50,width:step,height:step)),with:.color(.cyan),lineWidth:3)
                    }
                }
            }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded {tap in
                guard tap.location.x>=pad-step/2,tap.location.x<=side-pad+step/2,
                      tap.location.y>=pad-step/2,tap.location.y<=side-pad+step/2 else {return}
                let p=orientation.source(.init(x:(tap.location.x-pad)/(side-2*pad),y:(tap.location.y-pad)/(side-2*pad)))
                let col=Int((p.x*Double(n-1)).rounded()),row=Int((p.y*Double(n-1)).rounded())
                if (0..<n).contains(row),(0..<n).contains(col) {selection=row*n+col}
            })
            .accessibilityChildren {
                ForEach(0..<n*n,id:\.self) {i in Button(label(i)) {selection=i} }
            }
        }
    }
}

struct CorrectionPhoto: View {
    let snapshot: BoardCorrectionSnapshot
    let selection: Int?
    var body: some View {
        Canvas {ctx,size in
            let image=snapshot.image,w=Double(image.width),h=Double(image.height)
            let point=selection.map {snapshot.calibration.point(col:Double($0%snapshot.observation.size),row:Double($0/snapshot.observation.size))}
            // Show native camera pixels around the selected intersection, with
            // an open ring so the actual cross/stone remains visible.
            let orientation=BoardOrientation(snapshot.quarterTurns)
            let swaps=orientation.turns%2 != 0
            let scale=point == nil ? min(size.width/(swaps ? h:w),size.height/(swaps ? w:h)) : min(size.width,size.height)/180
            let center=point.map {CGPoint(x:$0.x*w,y:$0.y*h)} ?? CGPoint(x:w/2,y:h/2)
            var photo=ctx
            photo.translateBy(x:size.width/2,y:size.height/2)
            photo.rotate(by:.degrees(Double(orientation.turns)*90))
            photo.draw(Image(decorative:image,scale:1),in:CGRect(x:-center.x*scale,y:-center.y*scale,width:w*scale,height:h*scale))
            if point != nil {
                ctx.stroke(Path(ellipseIn:CGRect(x:size.width/2-23,y:size.height/2-23,width:46,height:46)),with:.color(.cyan),lineWidth:2)
            }
        }.clipped().background(.black.opacity(0.1)).accessibilityLabel("Camera photo aligned with the board view")
    }
}
