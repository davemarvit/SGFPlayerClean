import SwiftUI

struct StoneCalibrationView:View {
    @ObservedObject var model:ExperimentModel
    @State private var selection:Int?
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Calibrate your stones").font(.title2.bold())
            if let session=model.stoneCalibrationSession {
                if session.stage<3 {
                    Text("Step \(session.stage+1) of 3 · \(session.stage==0 ? "Empty board" : session.stage==1 ? "Place six stones" : "Swap the colors")").font(.headline)
                    Text(session.stage==0 ? "Clear every stone from the board. Keep the board, camera and lighting in place." : session.stage==1 ? "Place three black and three white stones exactly as shown. The center pair touches; the other stones sample different parts of the board." : "Replace each black stone with white, and each white stone with black, at the same six intersections.")
                    HStack(alignment:.top,spacing:18) {
                        VStack {
                            Text("Target board").font(.headline)
                            CalibrationDiagram(size:session.size,turns:session.quarterTurns,stones:session.targets,samples:Set(session.labels.keys),selection:$selection)
                                .frame(width:390,height:390)
                        }
                        VStack {
                            Text(session.pending == nil ? "Live camera" : "Photo to confirm").font(.headline)
                            if let image=session.pending?.image ?? model.image {
                                CalibrationCameraPreview(image:image,turns:session.quarterTurns).frame(width:390,height:390)
                            }
                        }
                    }
                    if session.pending != nil {
                        Text("Check the photo: every stone should match the diagram, with no hands covering the board. Confirm only when it matches.")
                    } else {
                        Text("Move your hands away, then capture a photo. You will check it before saving.")
                    }
                    if !model.stoneCalibrationContextValid {Text("The camera, reference, or game context changed. Cancel and restart calibration.").foregroundStyle(.red)}
                    if !model.stoneCalibrationError.isEmpty {Text(model.stoneCalibrationError).foregroundStyle(.red)}
                    HStack {
                        Button("Cancel") {model.closeStoneCalibration()}.keyboardShortcut(.cancelAction)
                        Spacer()
                        if model.savingStoneCalibration {ProgressView().controlSize(.small);Text("Saving confirmed photo…")}
                        if session.pending != nil {
                            Button("Retake") {model.stoneCalibrationSession?.pending=nil;model.stoneCalibrationError=""}
                            Button("Photo matches — save & continue") {model.confirmStoneCalibrationPhoto()}
                                .disabled(!model.stoneCalibrationContextValid)
                        } else {
                            Button("Capture photo") {model.captureStoneCalibrationPhoto()}
                                .disabled(!model.liveBoardReady || !model.stoneCalibrationContextValid)
                        }
                    }.disabled(model.savingStoneCalibration)
                    Text("Confirmed photos remain saved even if you cancel. Teal rings mark empty samples; only these and the six stone positions become training labels. Online moves and recording are paused during calibration.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Calibration saved").font(.headline)
                    Text("We captured both stone colors at six locations, plus empty intersections beside them. You can now inspect how closely each intersection matches those appearances.")
                    Text("The appearance model is experimental. Camera recognition and automatic moves still use the existing detector while we evaluate these predictions.")
                    Text("Remove the six calibration stones before starting a game.").font(.headline)
                    HStack {
                        Button("Show saved photos") {if let folder=model.stoneCalibrationFolder {NSWorkspace.shared.activateFileViewerSelecting([folder])}}
                        Spacer()
                        Button("Done") {model.closeStoneCalibration()}.keyboardShortcut(.defaultAction)
                    }
                }
            }
        }.padding(22).frame(width:820)
        .interactiveDismissDisabled()
    }
}

struct StoneAppearanceInspector:View {
    @ObservedObject var model:ExperimentModel
    @State private var selection:Int?
    @State private var measurement:(StoneAppearanceFeatures,StoneAppearanceModel.Prediction,StoneNeighborContext)?
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Compare stone appearances").font(.title2.bold())
            Text("Select an intersection, then read its appearance. These comparisons do not change the detected board or send moves.")
            HStack(alignment:.top,spacing:20) {
                CalibrationDiagram(size:model.size,turns:model.viewQuarterTurns,
                    stones:Dictionary(uniqueKeysWithValues:(model.observation?.readings ?? []).map{($0.row*model.size+$0.col,$0.occupancy)}),selection:$selection)
                    .frame(width:390,height:390)
                VStack(alignment:.leading,spacing:12) {
                    Button("Read selected point") {if let selection {measurement=model.inspectStoneAppearance(at:selection)}}
                        .disabled(selection==nil || !model.liveBoardReady || !model.stoneAppearanceProfileIsCurrent)
                    if !model.stoneAppearanceProfileIsCurrent {
                        Text("This calibration no longer matches the camera or reference. Calibrate again.").foregroundStyle(.orange)
                    } else if let measurement,let profile=model.stoneAppearanceProfile {
                        Text(measurement.1.label == .uncertain ? "Appearance is ambiguous or outside the learned ranges." : "Closest appearance: \(measurement.1.label.rawValue)").font(.headline)
                        Grid(alignment:.leading,horizontalSpacing:14,verticalSpacing:12) {
                            GridRow {Text("State");Text("Expected brightness");Text("Fit")}.font(.caption.bold())
                            ForEach(profile.distributions,id:\.label) {d in
                                GridRow {
                                    Text(d.label.rawValue.capitalized)
                                    Text(brightness(profile.distribution(for:d.label,context:measurement.2) ?? d,wood:measurement.0.woodLevel)).monospacedDigit()
                                    Text(fit(measurement.1.matches.first{$0.label==d.label}?.compatibility ?? 0))
                                }
                            }
                        }
                        Text("Empty-point surroundings: \(measurement.2.group). Black and white share their original appearance ranges.").font(.caption)
                        Text("Expected brightness is a descriptive range on a 0–100 lightness scale, adjusted for nearby wood. Fit also uses color, grid contrast, edge contrast, and variation across the stone. It is not a probability.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Select a point to compare black, white and empty appearances. A fresh aligned view and similar lighting are required.").foregroundStyle(.secondary)
                    }
                }.frame(width:360)
            }
            HStack {Spacer();Button("Done") {model.inspectingStoneAppearance=false}.keyboardShortcut(.cancelAction)}
        }.padding(22).frame(width:810)
        .onChange(of:selection) {_,point in measurement=point.flatMap{model.inspectStoneAppearance(at:$0)}}
    }
    private func brightness(_ d:StoneAppearanceModel.Distribution,wood:Double)->String {
        let low=max(0,min(1,wood+d.center[0]-d.radius[0]))*100
        let high=max(0,min(1,wood+d.center[0]+d.radius[0]))*100
        return "\(Int(low.rounded()))–\(Int(high.rounded()))"
    }
    private func fit(_ value:Double)->String {value>=0.7 ? "Close" : value>=0.3 ? "Possible" : "Poor"}
}

struct CalibrationDiagram:View {
    let size:Int
    let turns:Int
    let stones:[Int:Occupancy]
    var samples:Set<Int> = []
    @Binding var selection:Int?
    private var orientation:BoardOrientation {BoardOrientation(turns)}
    var body:some View {
        GeometryReader {g in
            let side=min(g.size.width,g.size.height),pad=side*0.045,step=(side-2*pad)/Double(size-1)
            Canvas {ctx,_ in
                ctx.fill(Path(roundedRect:CGRect(x:0,y:0,width:side,height:side),cornerRadius:8),with:.color(Color(red:0.80,green:0.66,blue:0.43)))
                var grid=Path()
                for i in 0..<size {
                    let p=pad+Double(i)*step
                    grid.move(to:.init(x:pad,y:p));grid.addLine(to:.init(x:side-pad,y:p))
                    grid.move(to:.init(x:p,y:pad));grid.addLine(to:.init(x:p,y:side-pad))
                }
                ctx.stroke(grid,with:.color(.black.opacity(0.6)),lineWidth:1)
                let stars=size==19 ? [3,9,15] : size==13 ? [3,6,9] : [2,4,6]
                for r in stars {for c in stars where size==19 || (r==size/2)==(c==size/2) {
                    ctx.fill(Path(ellipseIn:CGRect(x:pad+Double(c)*step-2,y:pad+Double(r)*step-2,width:4,height:4)),with:.color(.black))
                }}
                for i in 0..<size*size {
                    let p=orientation.display(.init(x:Double(i%size)/Double(size-1),y:Double(i/size)/Double(size-1)))
                    let center=CGPoint(x:pad+p.x*(side-2*pad),y:pad+p.y*(side-2*pad))
                    let circle=Path(ellipseIn:CGRect(x:center.x-step*0.43,y:center.y-step*0.43,width:step*0.86,height:step*0.86))
                    if let state=stones[i],state.stone != nil {
                        ctx.fill(circle,with:.color(state == .black ? .black:.white))
                        ctx.stroke(circle,with:.color(.black.opacity(0.5)),lineWidth:0.7)
                    } else if stones[i] == .uncertain {ctx.draw(Text("?").foregroundColor(.orange),at:center)}
                    if samples.contains(i),stones[i]?.stone == nil {
                        ctx.stroke(Path(ellipseIn:CGRect(x:center.x-step*0.18,y:center.y-step*0.18,width:step*0.36,height:step*0.36)),with:.color(.teal),lineWidth:1.5)
                    }
                    if selection==i {ctx.stroke(Path(CGRect(x:center.x-step/2,y:center.y-step/2,width:step,height:step)),with:.color(.cyan),lineWidth:3)}
                }
            }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded {tap in
                guard tap.location.x>=pad-step/2,tap.location.x<=side-pad+step/2,tap.location.y>=pad-step/2,tap.location.y<=side-pad+step/2 else {return}
                let p=orientation.source(.init(x:(tap.location.x-pad)/(side-2*pad),y:(tap.location.y-pad)/(side-2*pad)))
                let col=Int((p.x*Double(size-1)).rounded()),row=Int((p.y*Double(size-1)).rounded())
                if (0..<size).contains(row),(0..<size).contains(col) {selection=row*size+col}
            })
            .accessibilityChildren {ForEach(0..<size*size,id:\.self) {i in
                Button("Row \(i/size+1), column \(i%size+1): \(stones[i]?.rawValue ?? "empty")") {selection=i}
            }}
        }
    }
}

/// Uses the same clockwise, display-only transform as the target diagram and
/// main camera view. Archive pixels and raw-grid labels are never rotated.
struct CalibrationCameraPreview:View {
    let image:CGImage
    let turns:Int
    var body:some View {
        Canvas {context,size in
            let orientation=BoardOrientation(turns)
            let width=Double(image.width),height=Double(image.height)
            let displayedWidth=orientation.swapsDimensions ? height:width
            let displayedHeight=orientation.swapsDimensions ? width:height
            let scale=min(size.width/displayedWidth,size.height/displayedHeight)
            context.translateBy(x:size.width/2,y:size.height/2)
            context.rotate(by:.degrees(Double(orientation.turns)*90))
            context.draw(Image(decorative:image,scale:1),in:CGRect(x:-width*scale/2,y:-height*scale/2,width:width*scale,height:height*scale))
        }.accessibilityLabel("Camera photo in the same orientation as the target board")
    }
}
