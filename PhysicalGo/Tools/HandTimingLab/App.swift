import SwiftUI
import AppKit

@MainActor final class LabModel:ObservableObject {
    @Published var deviceID=UserDefaults.standard.string(forKey:"cameraID") ?? LabCapture.devices().first?.uniqueID ?? "" {
        didSet {UserDefaults.standard.set(deviceID,forKey:"cameraID")}
    }
    @Published var seconds=20.0
    @Published var recording=false
    @Published var status="Keep the game paused. Record several hand withdrawals, then label their clear-board boundaries."
    @Published var image:NSImage?
    @Published var cursor=0
    @Published var frames=[LabFrame]()
    @Published var folder:URL?
    @Published var lastObstructed:Int?
    @Published var firstClear:Int?
    @Published var labels=[LabLabel]()
    @Published var calibrating=false
    @Published var corners=[[String:Double]]()
    @Published var size=19
    let capture=LabCapture()
    init() {
        capture.onPreview={[weak self] cg,count in self?.image=NSImage(cgImage:cg,size:.zero);self?.status="Recording · \(count) frames saved"}
        capture.onComplete={[weak self] folder,message in
            guard let self else {return};self.recording=false
            if let folder {self.load(folder)}
            self.status=message
        }
        if let flag=CommandLine.arguments.firstIndex(of:"--capture-folder"),CommandLine.arguments.indices.contains(flag+1) {
            load(URL(fileURLWithPath:CommandLine.arguments[flag+1],isDirectory:true))
        }
    }
    func start() {recording=true;status="Opening camera…";capture.start(deviceID:deviceID,seconds:seconds)}
    func load(_ url:URL) {
        do {
            let text=try String(contentsOf:url.appendingPathComponent("frames.jsonl"))
            frames=try text.split(separator:"\n").map{try JSONDecoder().decode(LabFrame.self,from:Data($0.utf8))}.filter{$0.file != nil}
            folder=url;cursor=0;lastObstructed=nil;firstClear=nil;corners=[];labels=[];calibrating=false
            let labelURL=url.appendingPathComponent("labels.json")
            if FileManager.default.fileExists(atPath:labelURL.path) {
                let saved=try JSONDecoder().decode(LabLabels.self,from:Data(contentsOf:labelURL))
                guard saved.session==url.lastPathComponent else {throw NSError(domain:"Labels belong to another capture",code:1)}
                labels=saved.withdrawals
            }
            showFrame();status="Loaded \(frames.count) frames and \(labels.count) labels"
        } catch {status=error.localizedDescription}
    }
    func open() {let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;if panel.runModal() == .OK,let url=panel.url {load(url)}}
    func showFrame() {guard frames.indices.contains(cursor),let folder,let name=frames[cursor].file else {return};image=NSImage(contentsOf:folder.appendingPathComponent(name))}
    func step(_ delta:Int) {cursor=min(max(0,cursor+delta),max(0,frames.count-1));showFrame()}
    func saveLabel() {
        guard let lower=lastObstructed,let upper=firstClear,lower<upper,let folder else {return}
        do {
            labels.append(.init(lastObstructed:lower,firstClear:upper))
            try JSONEncoder().encode(LabLabels(session:folder.lastPathComponent,withdrawals:labels)).write(to:folder.appendingPathComponent("labels.json"),options:.atomic)
            lastObstructed=nil;firstClear=nil;status="Saved withdrawal \(labels.count). Mark another, or finish."
        } catch {labels.removeLast();status=error.localizedDescription}
    }
    func corner(_ point:CGPoint,in extent:CGSize) {
        guard calibrating,corners.count<4,extent.width>0,extent.height>0,let folder else {return}
        corners.append(["x":Double(point.x/extent.width),"y":Double(point.y/extent.height)])
        if corners.count==4 {
            do {
                try JSONSerialization.data(withJSONObject:["size":size,"corners":corners],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("calibration.json"),options:.atomic)
                calibrating=false;status="Grid saved for offline replay."
            } catch {status=error.localizedDescription}
        }
    }
}

struct LabView:View {
    @StateObject private var model=LabModel()
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Hand Timing Lab — development only").font(.title2.bold())
            HStack {
                Picker("Camera",selection:$model.deviceID) {ForEach(LabCapture.devices(),id:\.uniqueID){Text($0.localizedName).tag($0.uniqueID)}}.frame(maxWidth:420)
                Picker("Seconds",selection:$model.seconds) {ForEach([10.0,20,30],id:\.self){Text("\(Int($0))").tag($0)}}.frame(width:130)
                Button("Record 30 fps"){model.start()}.disabled(model.recording || model.deviceID.isEmpty)
                Button("Stop"){model.capture.stop()}.disabled(!model.recording)
                Button("Open capture…"){model.open()}.disabled(model.recording)
            }.disabled(model.calibrating)
            if let image=model.image {
                Image(nsImage:image).resizable().aspectRatio(contentMode:.fit)
                    .overlay {GeometryReader {geometry in
                        ZStack(alignment:.topLeading) {
                            Color.clear.contentShape(Rectangle()).onTapGesture {point in model.corner(point,in:geometry.size)}
                            ForEach(Array(model.corners.enumerated()),id:\.offset) {i,p in
                                Text("\(i+1)").font(.title.bold()).foregroundStyle(.red).position(x:(p["x"] ?? 0)*geometry.size.width,y:(p["y"] ?? 0)*geometry.size.height)
                            }
                        }
                    }}
            } else {Rectangle().fill(.black).overlay{Text("No capture yet").foregroundStyle(.white)}.frame(minHeight:350)}
            if !model.frames.isEmpty && !model.recording {
                HStack {
                    Button("← Frame"){model.step(-1)}.keyboardShortcut(.leftArrow,modifiers:[])
                    Slider(value:Binding(get:{Double(model.cursor)},set:{model.cursor=Int($0);model.showFrame()}),in:0...Double(max(1,model.frames.count-1)),step:1)
                    Button("Frame →"){model.step(1)}.keyboardShortcut(.rightArrow,modifiers:[])
                    Text("\(model.cursor+1) / \(model.frames.count)").monospacedDigit()
                }
                HStack {
                    Button("Mark last obstructed"){model.lastObstructed=model.frames[model.cursor].index}
                    Button("Mark first clear"){model.firstClear=model.frames[model.cursor].index}
                    Button("Save withdrawal"){model.saveLabel()}.disabled(model.lastObstructed==nil || model.firstClear==nil || (model.lastObstructed ?? 0)>=(model.firstClear ?? 0))
                    Text("\(model.labels.count) saved · marks \(model.lastObstructed.map(String.init) ?? "—") / \(model.firstClear.map(String.init) ?? "—")")
                }.disabled(model.calibrating)
                HStack {
                    Picker("Board",selection:$model.size){ForEach([9,13,19],id:\.self){Text("\($0)×\($0)").tag($0)}}.frame(width:150)
                    Button(model.calibrating ? "Cancel grid":"Set grid corners"){model.corners=[];model.calibrating.toggle()}
                    Text(model.calibrating ? "Click corner intersections: top left, top right, bottom right, bottom left.":"Grid corners are needed for offline motion replay.").font(.caption)
                    Spacer()
                    Button("Show files"){if let folder=model.folder {NSWorkspace.shared.open(folder)}}
                }
            }
            Text(model.status).textSelection(.enabled)
            Text("Labels describe when the entire hand/arm clears the board. Frames and timestamps stay in Movies/Physical Go Timing Lab. Capture stops after the selected duration or 2 GB. This tool never changes the game or clocks.").font(.caption).foregroundStyle(.secondary)
        }.padding().frame(minWidth:900,minHeight:650)
    }
}
@main struct HandTimingLabApp:App {
    var body:some Scene {WindowGroup{LabView()}}
}
