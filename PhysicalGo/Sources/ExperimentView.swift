import SwiftUI

/// Presentation only. Changing workspace or hiding a view never pauses recognition.
struct PlayWorkspace {
    enum Activity:String,CaseIterable {case setup="Setup",play="Play"}
    var activity:Activity = .setup
    mutating func gameBecameAvailable() {activity = .play}
    mutating func changedMode() {activity = .setup}
}

struct ExperimentView: View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject private var recorder:GameRecorder
    @ObservedObject private var reviews:ReviewPresentation
    @ObservedObject private var bridge:PhysicalOnlineBoard
    @State private var workspace=PlayWorkspace()
    @State private var showsInfo=false
    @State private var gameOptions=false
    @State private var cameraOptions=false
    @State private var alignmentOptions=false
    @State private var diagnosticData=false
    @State private var changeMode:PhysicalPlayMode?
    init(model:ExperimentModel) {
        self.model=model
        _reviews=ObservedObject(wrappedValue:model.reviewPresentation)
        _recorder=ObservedObject(wrappedValue:model.recorder)
        _bridge=ObservedObject(wrappedValue:model.onlineBoard)
    }
    private var hasSession:Bool {model.playMode == .local ? recorder.hasGame:!bridge.cells.isEmpty}
    var body:some View {
        VStack(spacing:0) {
            header
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if workspace.activity == .play && model.playMode == .online {
                        if model.alignmentNeedsRecovery {BoardRecoveryBanner(model:model)}
                        else if model.lightingNeedsRecovery {LightingRecoveryBanner(model:model)}
                    }
                    if workspace.activity == .setup {setup}
                    else {play}
                    diagnostics
                }.frame(maxWidth:1100).padding(24).frame(maxWidth:.infinity)
            }
        }.font(.system(size:13*model.interfaceScale))
            .background(Color(nsColor:.windowBackgroundColor))
            .onAppear {if hasSession {workspace.gameBecameAvailable()}}
            .onChange(of:recorder.autosaveURL) {_,url in
                if model.playMode == .local && url != nil {workspace.gameBecameAvailable()}
            }
            .onChange(of:bridge.cells.isEmpty) {wasEmpty,isEmpty in
                if model.playMode == .online && wasEmpty && !isEmpty {workspace.gameBecameAvailable()}
            }
            .onChange(of:model.playMode) {_,_ in workspace.changedMode()}
            .sheet(item:Binding(get:{reviews.session},set:{if $0==nil {reviews.close()}}),onDismiss:{reviews.didDismiss()}) {session in
                ReviewSectionView(recorder:session.recorder,id:session.id,orientation:session.orientation,
                    onClose:{reviews.close()},onCheckPhoto:session.onCheckPhoto == nil ? nil:{reviews.checkPhoto()})
            }
            .sheet(isPresented:$showsInfo) {
                VStack(spacing:0) {
                    HStack {Text("Info & settings").font(.title2.bold());Spacer();Button("Done") {showsInfo=false}.keyboardShortcut(.cancelAction)}.padding(20)
                    Divider()
                    ScrollView {GameInfoView(model:model,recorder:recorder).padding(20)}
                }.frame(width:650,height:720)
            }
            .sheet(isPresented:Binding(get:{model.stoneCalibrationSession != nil},set:{if !$0 {model.closeStoneCalibration()}})) {StoneCalibrationView(model:model)}
            .sheet(isPresented:$model.inspectingStoneAppearance) {StoneAppearanceInspector(model:model)}
            .sheet(isPresented:Binding(get:{model.boardCorrections.isEditing},set:{if !$0 {model.cancelBoardCorrection()}})) {
                BoardCorrectionEditor(model:model,corrections:model.boardCorrections).interactiveDismissDisabled(model.savingCorrections)
            }
            .onChange(of:bridge.enabled) {_,_ in model.clearBoardCorrections("Manual corrections cleared because the online connection changed.")}
            .confirmationDialog("Switch play mode?",isPresented:Binding(get:{changeMode != nil},set:{if !$0 {changeMode=nil}}),titleVisibility:.visible) {
                if let mode=changeMode {Button("Switch to \(mode.title)") {model.playMode=mode;changeMode=nil}}
                Button("Cancel",role:.cancel) {changeMode=nil}
            } message: {Text("Local recording and its clock will pause. Switching away from online play disconnects the physical board; the server clock continues.")}
    }
    private var header:some View {
        HStack(spacing:20) {
            Image(systemName:"circle.grid.3x3.fill").font(.title2).foregroundStyle(.teal)
            VStack(alignment:.leading,spacing:2) {
                Text("Physical Go").font(.title2.bold())
                Text(model.playMode.title).font(.caption).foregroundStyle(.secondary)
            }
            Picker("Activity",selection:$workspace.activity) {
                Text("Setup").tag(PlayWorkspace.Activity.setup)
                Text("Play").tag(PlayWorkspace.Activity.play)
            }.pickerStyle(.segmented).labelsHidden().frame(width:200)
                .help("Switch views without interrupting the game or camera.")
            Spacer()
            Button("Info & settings",systemImage:"info.circle") {showsInfo=true}
            Menu {
                Button("Calibrate stones…") {model.beginStoneCalibration()}.disabled(!model.canBeginStoneCalibration)
                if model.resumableStoneCalibrationFolder != nil {
                    Button("Resume calibration…") {model.resumeStoneCalibration()}.disabled(!model.canBeginStoneCalibration)
                }
                Divider()
                Button("Larger text") {model.resizeText(0.1)}.disabled(model.interfaceScale>=1.5)
                Button("Smaller text") {model.resizeText(-0.1)}.disabled(model.interfaceScale<=0.9)
                Button("Reset text size") {model.interfaceScale=1.1}
            } label:{Image(systemName:"ellipsis.circle")}.menuStyle(.borderlessButton).frame(width:28)
                .accessibilityLabel("More options")
        }.padding(.horizontal,24).padding(.vertical,16)
    }
    private var setup:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(hasSession ? "Set up your next game":"Set up a game").font(.largeTitle.bold())
                    Text("Choose the game, check the camera, then begin.").foregroundStyle(.secondary)
                }
                Spacer()
                if hasSession {Button("Return to current game") {workspace.activity = .play}}
            }
            if hasSession {
                Label("The current game is preserved. Opening Setup does not pause it.",systemImage:"info.circle").font(.callout).foregroundStyle(.secondary)
            }
            WorkflowCard(number:1,title:"Game",summary:model.playMode == .local ? "Two players at this board":"Play through SGF Player / OGS") {
                Picker("Play mode",selection:Binding(get:{model.playMode},set:{mode in
                    if hasSession && mode != model.playMode {changeMode=mode} else {model.playMode=mode}
                })) {
                    ForEach(PhysicalPlayMode.allCases,id:\.self) {Text($0.title).tag($0)}
                }.pickerStyle(.segmented).frame(maxWidth:340)
                    .disabled(model.exportingSGF || model.stoneCalibrationSession != nil || model.boardCorrections.isEditing)
                if model.playMode == .local {
                    HStack(spacing:20) {
                        Picker("Board",selection:$model.size) {ForEach([9,13,19],id:\.self) {Text("\($0) × \($0)").tag($0)}}
                            .frame(maxWidth:230).disabled(recorder.hasGame && recorder.state != .finished)
                            .onChange(of:model.size) {_,_ in model.boardSizeChanged()}
                        Text("\(model.newGameInfo.rules ?? "Japanese") · \(model.newGameInfo.komi ?? "6.5") komi · \(model.newGameHandicap == 0 ? "Even game":"\(model.newGameHandicap) handicap stones")")
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Players, rules & clock · \(model.newGameClock.summary)",isExpanded:$gameOptions) {
                        VStack(alignment:.leading,spacing:14) {
                            HStack {
                                TextField("Black player",text:draft(\.playerBlack))
                                TextField("White player",text:draft(\.playerWhite))
                            }.textFieldStyle(.roundedBorder)
                            DatePicker("Date",selection:draftDate,displayedComponents:.date)
                            NewGameSettings(model:model)
                        }.padding(.top,12).frame(maxWidth:650)
                    }
                } else {
                    Text("Create or accept a game in SGF Player, then enable Use physical board there. Keep this camera view aligned with the online board.").foregroundStyle(.secondary)
                }
            }
            WorkflowCard(number:2,title:"Camera & board",summary:"Keep all four corners in view") {
                cameraPreview(height:280)
                SetupCameraStatus(model:model)
                HStack {
                    Label(model.cameraStatus,systemImage:model.running ? "video.fill":"video.slash").lineLimit(2)
                    Spacer()
                    if !model.running {Button("Start camera") {model.start()}.disabled(model.cameraID.isEmpty)}
                    if model.calibration == nil {Button("Find grid") {model.detectGrid(retryAutomatically:model.running)}.disabled(model.image == nil || model.detectingGrid)}
                }
                cameraDetails
            }
            WorkflowCard(number:3,title:model.playMode == .local ? "Ready to play":"Connect & play",summary:"Save setup, then press Start when both players are ready") {
                if model.playMode == .local {
                    if model.showsStartupReferenceControl {StartupReferenceControl(model:model)}
                    HStack(alignment:.center,spacing:24) {
                        Text(model.newGameReadiness).foregroundStyle(model.canStartNewRecording ? Color.green:Color.secondary)
                            .lineLimit(3,reservesSpace:true).frame(maxWidth:.infinity,alignment:.leading)
                        Button("Save game setup") {
                            model.startRecording(startPaused:true)
                            if recorder.awaitingFirstStart {workspace.gameBecameAvailable()}
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStartNewRecording)
                    }
                } else {
                    Text(bridge.status).foregroundStyle(.secondary).lineLimit(3,reservesSpace:true)
                    Button("Open play view") {workspace.activity = .play}.buttonStyle(.borderedProminent)
                }
            }
        }
    }
    private var play:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                if model.playMode == .local {LocalPlayHeading(recorder:recorder,clock:recorder.clock)}
                else {Text("Playing").font(.largeTitle.bold())}
                Spacer()
                Button("Check board photo…") {model.beginBoardCorrection()}
                    .disabled(model.observation == nil || model.calibration == nil || model.alignmentNeedsRecovery)
            }
            if !hasSession && model.playMode == .local {
                ContentUnavailableView {
                    Label("Ready for a game?",systemImage:"circle.grid.3x3")
                } description:{Text("Set up the camera and game before recording moves.")}
                actions:{Button("Go to Setup") {workspace.activity = .setup}.buttonStyle(.borderedProminent)}
            } else {
                if model.playMode == .local {LocalClockHost(recorder:recorder,onReview:{model.reviewPresentation.open(recorder:recorder,id:$0,orientation:model.orientation,onCheckPhoto:{model.beginBoardCorrection()})})}
                GameStatusBanner(model:model,recorder:recorder,bridge:bridge,textScale:model.interfaceScale)
                PlaySessionControls(model:model,recorder:recorder)
            }
            if model.playMode == .online {PhysicalOnlineBoardView(bridge:bridge).frame(maxWidth:600).frame(maxWidth:.infinity)}
            // Keep one stable panel in play. Its tabs are the user's explicit
            // choice; alignment/lighting warnings never insert a second feed.
            RecordingView(model:model,recorder:recorder,showsRecordingControls:false)
            HStack {
                Text(model.running ? "Camera active · recognition continues with views hidden":"Camera stopped").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Set up next game") {workspace.activity = .setup}
            }
        }
    }
    private func cameraPreview(height:CGFloat)->some View {
        VStack(spacing:8) {
            CameraCanvas(model:model).frame(height:height)
                .background(Color.black.opacity(0.9),in:RoundedRectangle(cornerRadius:12))
                .clipShape(RoundedRectangle(cornerRadius:12))
                .overlay(alignment:.topLeading) {
                    if model.image != nil && model.calibration == nil {
                        Text(model.lookingForGrid ? "Looking for grid…":model.cornerPrompt)
                            .padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8)).padding(12).allowsHitTesting(false)
                    }
                }
            HStack {
                Text(model.frozen ? "Frozen frame":model.image == nil ? "Camera preview":"Keep all four corners in view").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Flip view") {model.flipView()}.help("Turn the view 180° to face the other player.")
                Button("Rotate",systemImage:"rotate.right") {model.rotateView()}.help("Rotate the view 90° clockwise.")
            }
        }
    }
    private var cameraDetails:some View {
        VStack(alignment:.leading,spacing:12) {
            DisclosureGroup("Camera source & controls",isExpanded:$cameraOptions) {
                VStack(alignment:.leading,spacing:10) {
                    Picker("Camera",selection:$model.cameraID) {
                        if model.cameras.isEmpty {Text("No camera found").tag("")}
                        ForEach(model.cameras) {Text($0.name).tag($0.id)}
                    }.disabled(model.running)
                    HStack {
                        Button("Refresh list") {model.refreshCameras()}
                        Button(model.running ? "Stop camera":"Start camera") {model.running ? model.stop():model.start()}.disabled(!model.running && model.cameraID.isEmpty)
                        Button("Restart camera") {model.start()}.disabled(model.cameraID.isEmpty)
                    }
                }.padding(.top,10)
            }.actionAttention(!model.running && model.cameraID.isEmpty && !cameraOptions ? .required:.none)
            DisclosureGroup("Grid, orientation & reference",isExpanded:$alignmentOptions) {
                VStack(alignment:.leading,spacing:10) {
                                Label(model.gridIndicator,
                                      systemImage:model.alignmentNeedsRecovery || model.awaitingReferenceFrame ? "viewfinder" : model.calibration != nil ? "checkmark.circle.fill" : "viewfinder")
                                    .foregroundStyle(model.alignmentNeedsRecovery || model.awaitingReferenceFrame ? Color.orange : model.calibration != nil ? Color.green : Color.secondary)
                                Text(model.gridStatus)
                                    .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                                HStack {
                                    Button(model.calibration == nil ? "Find grid now" : "Find grid again") {
                                        model.detectGrid(retryAutomatically:model.running && !model.frozen && model.calibration == nil)
                                    }
                                        .disabled(model.image == nil || model.detectingGrid)
                                    if model.detectingGrid { ProgressView().controlSize(.small) }
                                }
                                Toggle("Auto-orient board",isOn:$model.automaticViewOrientation).toggleStyle(.checkbox)
                                    .disabled(model.orientationLocked)
                                    .help("Use the detected long axis to orient the board before starting a game. Manual rotation turns this off.")
                                Text(model.orientationStatus).font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                                Toggle("Straighten board",isOn:$model.straightenBoard).toggleStyle(.checkbox)
                                    .onChange(of:model.straightenBoard) { _,_ in model.perspectiveViewChanged() }
                                    .help("Show the calibrated board from above, with standard Go-grid proportions.")
                                if model.straightenBoard && model.calibration != nil {
                                    HStack {
                                        Text(model.aspectOverridden ? "Long side adjusted" : (model.aspectStoneCount>0 ? "Long side checked against \(model.aspectStoneCount) stones" : model.aspectGridLineCount>0 ? "Long side checked against the printed grid" : model.aspectConfident ? "Long side detected" : "Long side estimated"))
                                            .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Swap long side") { model.swapLongSide() }.controlSize(.small)
                                            .help("Optional correction when camera geometry leaves the long side ambiguous.")
                                    }
                                }
                                if model.showDiagnostics {
                                Toggle("Show grid overlay",isOn:$model.showGridOverlay).toggleStyle(.checkbox)
                                Toggle("Show stone outlines",isOn:$model.showStoneOutlines).toggleStyle(.checkbox)
                                    .disabled(!model.hasReference)
                                    .help("Available after capturing an empty-board reference.")
                                }
                                HStack {
                                    Button("Undo corner") { model.undoCorner() }.disabled(model.corners.isEmpty)
                                    Button("Manual corners") { model.resetCalibration() }
                                        .help("Hover to magnify, then click the four corner intersections clockwise from the top left of this view.")
                                }
                                Button("Capture empty reference (optional)") { model.captureReference() }
                                    .disabled(model.awaitingReferenceFrame || model.alignmentNeedsRecovery || model.calibration == nil || model.image == nil || (model.running && model.cameraState != .live) || model.detectingGrid)
                                if model.showDiagnostics && model.stoneAppearanceProfile != nil {
                                    Button("Inspect stone appearances…") {model.inspectingStoneAppearance=true}
                                    Text(model.stoneAppearanceProfileIsCurrent ? "Stone calibration saved · experimental comparisons available" : "Camera or reference changed · calibrate stones again")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if model.hasReference {
                                    Button("Use without reference") { model.useWithoutReference() }
                                }
                                Text(model.hasReference ? model.referenceStatus : (model.automaticReferenceAllowed ? "Detecting from nearby wood and visible grid lines. A verified empty board is captured automatically. Clear all stones before optional manual capture." : "Detecting without a reference. Clear all stones before optional manual capture."))
                                    .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)

                }.padding(.top,10)
            }
        }
    }
    private var diagnostics:some View {
        VStack(alignment:.leading,spacing:10) {
            Divider()
            DiagnosticIndicator(diagnostics:model.diagnostics)
            MoveCaptureIndicator(capture:model.moveEvidenceCapture)
            DisclosureGroup(isExpanded:$model.showDiagnostics) {
                VStack(alignment:.leading,spacing:16) {
                    Text("Collection and display are independent. Closing this section keeps your collection choices in effect.").font(.callout).foregroundStyle(.secondary)
                    DiagnosticControls(model:model,diagnostics:model.diagnostics)
                    DisclosureGroup("Live data · recognition, timing & tracking",isExpanded:$diagnosticData) {
                        VStack(alignment:.leading,spacing:16) {
                            MoveTimingPanel(mode:model.playMode,recorder:recorder,quarterTurns:model.viewQuarterTurns)
                            LiveRecognitionDiagnostics(model:model)
                            GroupBox("Established stone tracking") {
                                VStack(alignment:.leading,spacing:6) {
                                    Text("\(model.stoneTrackingReport.tracked) physical positions tracked · checked twice per second")
                                    Text("\(model.stoneTrackingReport.uncertain.count) outlines await a clear view. Game intersections are retained.").foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(8)
                            }
                        }.padding(.top,12)
                    }
                    DisclosureGroup("Samples & detection tools") {
                        VStack(alignment:.leading,spacing:12) {
                            HStack {
                                Button("Open sample…") {model.openSample()}
                                Button("Open photo…") {model.openPhoto()}
                                Button(model.frozen ? "Resume camera":"Freeze camera") {model.toggleFreeze()}.disabled(!model.running || model.image == nil)
                            }
                            TextField("Board and lighting notes",text:$model.sampleName)
                            Button("Save sample…") {model.saveSample()}.disabled(model.image == nil)
                            Toggle("Show grid overlay",isOn:$model.showGridOverlay)
                            Toggle("Show stone outlines",isOn:$model.showStoneOutlines).disabled(!model.hasReference)
                            DetectionTuningView(model:model,recorder:recorder)
                        }.padding(.top,12)
                    }
                }.padding(.top,14)
            } label:{Label("Diagnostics",systemImage:"waveform.path.ecg").font(.headline)}
        }
    }
    private func draft(_ key:WritableKeyPath<SGFGame.Info,String?>)->Binding<String> {
        Binding(get:{model.newGameInfo[keyPath:key] ?? ""},set:{model.newGameInfo[keyPath:key]=$0})
    }
    private var draftDate:Binding<Date> {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd"
        return Binding(get:{formatter.date(from:model.newGameInfo.date ?? "") ?? Date()},set:{model.newGameInfo.date=SGFGame.Info.formattedGameDate($0)})
    }
}

private struct WorkflowCard<Content:View>:View {
    let number:Int
    let title:String
    let summary:String
    @ViewBuilder let content:()->Content
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:12) {
                Text("\(number)").font(.headline).foregroundStyle(.teal).frame(width:28,height:28)
                    .background(.teal.opacity(0.12),in:Circle())
                Text(title).font(.title3.bold())
                Spacer()
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(2,reservesSpace:true)
            }
            content()
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(nsColor:.controlBackgroundColor).opacity(0.65),in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).stroke(.primary.opacity(0.08),lineWidth:1))
    }
}

private func fittedRect(image: CGImage, orientation:BoardOrientation, in size: CGSize) -> CGRect {
    let imageWidth = CGFloat(orientation.swapsDimensions ? image.height : image.width)
    let imageHeight = CGFloat(orientation.swapsDimensions ? image.width : image.height)
    let scale = min(size.width/imageWidth, size.height/imageHeight)
    let width = imageWidth*scale, height = imageHeight*scale
    return CGRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height)
}

struct CameraCanvas: View {
    @ObservedObject var model: ExperimentModel
    @State private var pointer: CGPoint?

    func selectCorner(at location: CGPoint, imageRect: CGRect, rectification: BoardRectifiedGeometry?) {
        guard imageRect.contains(location) else { return }
        let displayed = ImagePoint(x:(location.x-imageRect.minX)/imageRect.width,
                                   y:(location.y-imageRect.minY)/imageRect.height)
        let source = model.orientation.source(displayed)
        model.addCorner(rectification?.sourcePoint(from:source) ?? source)
    }

    private func drawMagnifier(in context: GraphicsContext, at pointer: CGPoint, bounds: CGSize,
                               drawImage: (GraphicsContext) -> Void) {
        let radius = min(65, min(bounds.width, bounds.height) / 4)
        guard radius > 12 else { return }
        func center(_ p: CGFloat, extent: CGFloat) -> CGFloat {
            let offset = radius + 16
            let proposed = p < extent / 2 ? p + offset : p - offset
            return min(extent - radius - 3, max(radius + 3, proposed))
        }
        let focus = CGPoint(x:center(pointer.x,extent:bounds.width), y:center(pointer.y,extent:bounds.height))
        let circle = Path(ellipseIn:CGRect(x:focus.x-radius,y:focus.y-radius,width:2*radius,height:2*radius))
        context.fill(circle, with:.color(.black))
        var zoom = context
        zoom.clip(to:circle)
        zoom.translateBy(x:focus.x,y:focus.y)
        zoom.scaleBy(x:4,y:4)
        zoom.translateBy(x:-pointer.x,y:-pointer.y)
        drawImage(zoom)
        context.stroke(circle, with:.color(.black), lineWidth:4)
        context.stroke(circle, with:.color(.white), lineWidth:2)
        var reticle = Path()
        for direction in [CGPoint(x:1,y:0), CGPoint(x:-1,y:0), CGPoint(x:0,y:1), CGPoint(x:0,y:-1)] {
            reticle.move(to:CGPoint(x:focus.x+direction.x*3,y:focus.y+direction.y*3))
            reticle.addLine(to:CGPoint(x:focus.x+direction.x*13,y:focus.y+direction.y*13))
        }
        context.stroke(reticle, with:.color(.black), lineWidth:3)
        context.stroke(reticle, with:.color(.white), lineWidth:1)
    }
    var body: some View {
        GeometryReader { geometry in
            if let rawImage = model.image {
                let image = model.rectifiedImage ?? rawImage
                let rectification = model.rectifiedImage == nil ? nil : model.rectifiedGeometry
                let orientation = model.orientation
                let edgePadding:CGFloat = model.calibration == nil ? 0 : 14
                let available=CGSize(width:max(1,geometry.size.width-2*edgePadding),height:max(1,geometry.size.height-2*edgePadding))
                let rect = fittedRect(image:image,orientation:orientation,in:available).offsetBy(dx:edgePadding,dy:edgePadding)
                Canvas { context, _ in
                    func drawImage(_ target: GraphicsContext) {
                        var imageContext = target
                        imageContext.translateBy(x:rect.midX,y:rect.midY)
                        imageContext.rotate(by:.degrees(Double(orientation.turns)*90))
                        let sourceWidth = orientation.swapsDimensions ? rect.height : rect.width
                        let sourceHeight = orientation.swapsDimensions ? rect.width : rect.height
                        imageContext.draw(Image(decorative:image,scale:1),in:CGRect(x:-sourceWidth/2,y:-sourceHeight/2,width:sourceWidth,height:sourceHeight))
                    }
                    drawImage(context)
                    func project(_ p: ImagePoint) -> CGPoint {
                        let displayed = orientation.display(rectification?.normalizedPoint(from:p) ?? p)
                        return CGPoint(x:rect.minX+displayed.x*rect.width,y:rect.minY+displayed.y*rect.height)
                    }
                    if let calibration = model.calibration, !model.alignmentNeedsRecovery {
                        for label in BoardCoordinates.labels(size:calibration.size,orientation:orientation,margin:0.30) {
                            let p=project(calibration.point(col:label.grid.x,row:label.grid.y))
                            let q=project(calibration.point(col:label.grid.x+1,row:label.grid.y))
                            let fontSize=max(8,min(12,hypot(q.x-p.x,q.y-p.y)*0.26*model.interfaceScale))
                            context.draw(Text(label.text).font(.system(size:fontSize,weight:.regular)).foregroundColor(.black.opacity(0.85)),at:p)
                        }
                        var grid = Path()
                        for i in 0..<calibration.size {
                            grid.move(to: project(calibration.point(col: Double(i), row: 0)))
                            grid.addLine(to: project(calibration.point(col: Double(i), row: Double(calibration.size-1))))
                            grid.move(to: project(calibration.point(col: 0, row: Double(i))))
                            grid.addLine(to: project(calibration.point(col: Double(calibration.size-1), row: Double(i))))
                        }
                        if model.showDiagnostics && model.showGridOverlay {
                            var gridContext = context
                            for reading in model.visibleObservation?.readings ?? [] where reading.occupancy.stone != nil {
                                let col = Double(reading.col), row = Double(reading.row)
                                let p = project(calibration.point(col:col,row:row))
                                let nextCol = project(calibration.point(col:col+1,row:row))
                                let nextRow = project(calibration.point(col:col,row:row+1))
                                let radius = 0.65*max(hypot(nextCol.x-p.x,nextCol.y-p.y),hypot(nextRow.x-p.x,nextRow.y-p.y))
                                gridContext.clip(to:Path(ellipseIn:CGRect(x:p.x-radius,y:p.y-radius,width:2*radius,height:2*radius)),options:.inverse)
                            }
                            gridContext.stroke(grid, with: .color(.cyan.opacity(0.55)), lineWidth: 1)
                        }
                        if model.showDiagnostics && model.showStoneOutlines {
                            for footprint in model.visibleObservation?.footprints ?? [] {
                                var outline=Path()
                                for step in 0...48 {
                                    let angle=Double(step)*2*Double.pi/48
                                    let point=project(calibration.point(col:footprint.center.x+cos(angle)*footprint.radiusCol,
                                        row:footprint.center.y+sin(angle)*footprint.radiusRow))
                                    if step==0 { outline.move(to:point) } else { outline.addLine(to:point) }
                                }
                                outline.closeSubpath()
                                context.stroke(outline,with:.color(.cyan.opacity(0.85)),lineWidth:1.2)
                                let center=project(calibration.point(col:footprint.center.x,row:footprint.center.y))
                                var cross=Path()
                                cross.move(to:CGPoint(x:center.x-2,y:center.y));cross.addLine(to:CGPoint(x:center.x+2,y:center.y))
                                cross.move(to:CGPoint(x:center.x,y:center.y-2));cross.addLine(to:CGPoint(x:center.x,y:center.y+2))
                                context.stroke(cross,with:.color(.cyan.opacity(0.85)),lineWidth:1)
                            }
                        }
                        for reading in model.visibleObservation?.readings ?? [] where reading.occupancy != .empty {
                            let p = project(calibration.point(col: Double(reading.col), row: Double(reading.row)))
                            let radius = max(3, min(rect.width,rect.height)/Double(model.size)*0.25)
                            let ring = Path(ellipseIn: CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2))
                            context.stroke(ring, with: .color(.cyan), lineWidth: 5)
                            context.stroke(ring, with: .color(reading.occupancy == .black ? .black : reading.occupancy == .white ? .white : .orange), lineWidth: 3)
                        }
                    }
                    for (i, corner) in model.displayedCorners.enumerated() where model.showGridOverlay && !model.hasReference && !model.alignmentNeedsRecovery {
                        let p = project(corner)
                        context.fill(Path(ellipseIn: CGRect(x: p.x-5, y: p.y-5, width: 10, height: 10)), with: .color(.cyan))
                        context.draw(Text("\(i+1)").font(.system(size:14*model.interfaceScale,weight:.semibold)).foregroundColor(.cyan), at: CGPoint(x: p.x+12, y: p.y-12))
                    }
                    if model.selectingCorners, let pointer, rect.contains(pointer) {
                        drawMagnifier(in:context,at:pointer,bounds:geometry.size,drawImage:drawImage)
                    }
                }.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): pointer = model.selectingCorners && rect.contains(point) ? point : nil
                        case .ended: pointer = nil
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { tap in
                        selectCorner(at:tap.location, imageRect:rect, rectification:rectification)
                    })
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 64)).foregroundStyle(.teal)
                    Text("Bring your board into view").font(.system(size:22*model.interfaceScale))
                    Text("Connect a webcam and start the camera,\nor open a saved board photo.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct DetectedBoard: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var recorder: GameRecorder
    private var starPoints: [BoardPosition] {
        if model.size == 19 {
            return [3,9,15].flatMap { row in [3,9,15].map { BoardPosition(row,$0) } }
        }
        let inset = model.size == 9 ? 2 : 3
        let far = model.size-1-inset
        return [BoardPosition(inset,inset),BoardPosition(inset,far),
                BoardPosition(far,inset),BoardPosition(far,far),
                BoardPosition(model.size/2,model.size/2)]
    }
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let origin = CGPoint(x: (geometry.size.width-side)/2+26, y: 26)
            let pitch: CGFloat = (side-52)/CGFloat(model.size-1)
            Canvas { context, _ in
                let bounds = CGRect(x: (geometry.size.width-side)/2, y: 0, width: side, height: side)
                context.fill(Path(roundedRect: bounds, cornerRadius: 8), with: .color(Color(red: 0.80, green: 0.66, blue: 0.43)))
                var grid = Path()
                for i in 0..<model.size {
                    let d = CGFloat(i)*pitch
                    grid.move(to: CGPoint(x: origin.x+d,y: origin.y)); grid.addLine(to: CGPoint(x: origin.x+d,y: origin.y+side-52))
                    grid.move(to: CGPoint(x: origin.x,y: origin.y+d)); grid.addLine(to: CGPoint(x: origin.x+side-52,y: origin.y+d))
                }
                context.stroke(grid, with: .color(.black.opacity(0.55)), lineWidth: 0.7)
                for label in BoardCoordinates.labels(size:model.size,orientation:BoardOrientation(0)) {
                    context.draw(Text(label.text).font(.system(size:max(8,min(11,pitch*0.42)),weight:.regular)).foregroundColor(.black),
                        at:CGPoint(x:origin.x+label.grid.x*pitch,y:origin.y+label.grid.y*pitch))
                }
                let starRadius = min(2.5,max(1.6,pitch*0.13))
                for point in starPoints {
                    let displayed = model.orientation.display(ImagePoint(x:Double(point.col)/Double(model.size-1),y:Double(point.row)/Double(model.size-1)))
                    let center = CGPoint(x:origin.x+displayed.x*(side-52),y:origin.y+displayed.y*(side-52))
                    let dot = Path(ellipseIn:CGRect(x:center.x-starRadius,y:center.y-starRadius,width:starRadius*2,height:starRadius*2))
                    context.fill(dot,with:.color(.black.opacity(0.8)))
                }
                let pending=Dictionary(recorder.pendingConfidence.compactMap { evidence in evidence.point.map{($0,evidence)} },uniquingKeysWith:{_,latest in latest})
                let interpreted=model.playMode == .local && recorder.game.boardSize==model.size ? recorder.interpretedBoard : nil
                let lastPoint=model.playMode == .local && recorder.game.boardSize==model.size ? recorder.lastInterpretedPoint : nil
                let spatialWarnings=model.observation?.ambiguousPlacements ?? []
                let accepted=model.playMode == .local && recorder.game.boardSize==model.size ? recorder.positions.last : nil
                for (index, reading) in (model.correctedObservation?.readings ?? []).enumerated() {
                    let evidence=model.playMode == .local && recorder.game.boardSize==model.size ? pending[index] : nil
                    let interpretation=interpreted?.grid[reading.row][reading.col]
                    let inferred:Occupancy = interpretation == .black ? .black : interpretation == .white ? .white : .uncertain
                    let state = model.boardCorrections.values[index] ?? model.labels[index] ?? (reading.occupancy == .uncertain && interpretation != nil ? inferred : reading.occupancy)
                    let displayed = model.orientation.display(ImagePoint(x:Double(reading.col)/Double(model.size-1),y:Double(reading.row)/Double(model.size-1)))
                    let p = CGPoint(x:origin.x+displayed.x*(side-52),y:origin.y+displayed.y*(side-52))
                    let circle = Path(ellipseIn: CGRect(x: p.x-pitch*0.43, y: p.y-pitch*0.43, width: pitch*0.86, height: pitch*0.86))
                    if state == .uncertain {
                        context.fill(Path(ellipseIn:CGRect(x:p.x-pitch*0.16,y:p.y-pitch*0.16,width:pitch*0.32,height:pitch*0.32)),with:.color(.orange))
                    } else if state != .empty {
                        context.fill(circle,with:.color(state == .black ? .black : .white))
                    }
                    let recorded=accepted?.grid[reading.row][reading.col] != nil
                    let needsPlacementReview = !recorded && evidence?.level != "high" && spatialWarnings.contains(index)
                    if state.stone != nil && (needsPlacementReview || (evidence != nil && evidence!.level != "high")) {
                        let ring=Path(ellipseIn:CGRect(x:p.x-pitch*0.48,y:p.y-pitch*0.48,width:pitch*0.96,height:pitch*0.96))
                        context.stroke(ring,with:.color(.red),lineWidth:2)
                    }
                    if lastPoint==index,state.stone != nil {
                        context.fill(Path(ellipseIn:CGRect(x:p.x-pitch*0.13,y:p.y-pitch*0.13,width:pitch*0.26,height:pitch*0.26)),with:.color(state == .black ? .white : .black))
                    }
                    if model.showDiagnostics && model.stoneTrackingReport.uncertain.contains(index) {
                        context.stroke(circle,with:.color(.orange),style:StrokeStyle(lineWidth:2,dash:[4,3]))
                    }
                    if model.labels[index] != nil { context.stroke(circle, with: .color(.blue), lineWidth: 2) }
                    if model.boardCorrections.values[index] != nil { context.stroke(circle, with:.color(.purple),lineWidth:3) }
                }
            }.contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    let source = model.orientation.source(ImagePoint(x:(tap.location.x-origin.x)/(side-52),y:(tap.location.y-origin.y)/(side-52)))
                    let col = Int((source.x*Double(model.size-1)).rounded()), row = Int((source.y*Double(model.size-1)).rounded())
                    guard (0..<model.size).contains(col), (0..<model.size).contains(row), model.observation != nil else { return }
                    model.label(row*model.size+col)
                })
        }.accessibilityLabel("Best estimated board. Red rings indicate assignments needing attention. A contrasting center dot marks the latest interpreted move. Freeze to label diagnostic samples; labels do not change recorded moves.")
    }
}


private struct LocalClockHost:View {
    @ObservedObject var recorder:GameRecorder
    let onReview:(UUID)->Void
    var body:some View {LocalClockVisibility(clock:recorder.clock,recorder:recorder,onReview:onReview)}
}
private struct LocalClockVisibility:View {
    @ObservedObject var clock:LocalGameClock
    @ObservedObject var recorder:GameRecorder
    let onReview:(UUID)->Void
    var body:some View {if clock.enabled {LocalClockPanel(clock:clock,recorder:recorder,showsStatus:false,onReview:onReview)}}
}

/// Always visible during alignment loss, including when diagnostics are hidden.
private struct LightingRecoveryBanner:View {
    @ObservedObject var model:ExperimentModel
    var body:some View {
        HStack(alignment:.top,spacing:14) {
            Image(systemName:"sun.max.trianglebadge.exclamationmark").font(.system(size:32)).foregroundStyle(.orange)
            VStack(alignment:.leading,spacing:6) {
                Text(model.lightingNeedsHelp ? "Improve the board lighting":"Adjusting to the lighting…").font(.title2.bold())
                Text("Please pause play. Light the whole board evenly and reduce glare or strong shadows. Leave the stones in place; recognition resumes automatically when the view is reliable.")
                Text("Automatic move recording and sending are paused. Your saved game is preserved.").font(.callout.bold())
                Text(model.playMode == .online ? "The online game clock continues running."
                     : "Use Pause clock if you need to stop the local game clock.").font(.callout)
                if model.frozen || !model.running {Text("Resume the live camera to verify the lighting.").font(.callout)}
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding(16).background(Color.orange.opacity(0.22),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.orange,lineWidth:2))
            .accessibilityElement(children:.contain).accessibilityLabel("Lighting recovery. Please pause play.")
    }
}

private struct BoardRecoveryBanner:View {
    @ObservedObject var model:ExperimentModel
    var body:some View {
        HStack(alignment:.center,spacing:16) {
            Image(systemName:model.recoveryNeedsFullBoard ? "viewfinder":"camera.metering.unknown")
                .font(.system(size:32)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {
                Text(model.recoveryLikelyObstruction ? "Board partly obscured":model.recoveryNeedsFullBoard ? "Check the board view":model.recoverySearchExhausted ? "Board alignment needs attention":"Checking board view…")
                    .font(.title2.bold()).lineLimit(1)
                Text(model.recoveryLikelyObstruction
                     ? "Visible stones still match their positions. Move hands or other obstructions clear; keep the camera and board in place."
                     : model.recoveryNeedsFullBoard
                     ? "Check room lighting and clear obstructions. Keep the camera and board steady with all four corners visible."
                     : "Please pause play and hold the camera and board steady. Stones can stay in place while we verify their positions.").lineLimit(3,reservesSpace:true)
                Text("Automatic move recording and sending are paused while alignment is uncertain. Your saved game is preserved.")
                    .font(.callout.bold())
                if model.playMode == .online {Text("The online game clock continues running.").font(.callout)}
                Text(model.recoveryDetail.isEmpty ? "Checking grid alignment…":model.recoveryDetail).font(.caption).lineLimit(2,reservesSpace:true)
                Text(model.recoverySearchExhausted ? "Automatic checks continue every 30 seconds. You can retry sooner once the view is clear.":"Keep the camera and board steady while checking.").font(.caption).lineLimit(2,reservesSpace:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            VStack(spacing:10) {
                ProgressView().controlSize(.small).opacity(model.detectingGrid ? 1:0)
                Button("Board is in view — retry") {model.detectGrid()}
                    .buttonStyle(.borderedProminent)
                    .tint(model.recoverySearchExhausted ? .red:.accentColor)
                    .actionAttention(model.recoverySearchExhausted ? .required:.none)
                    .disabled(model.detectingGrid || model.image == nil || model.frozen || model.cameraState != .live)
            }.frame(width:220)
        }.padding(16).foregroundStyle(.primary)
            .background(Color.orange.opacity(0.22),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.orange,lineWidth:2))
            .accessibilityElement(children:.contain)
            .accessibilityLabel("Board recovery. Please pause play.")
    }
}
