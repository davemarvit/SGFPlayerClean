import SwiftUI
import AppKit

struct DiagnosticControls:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var diagnostics:DiagnosticRecorder
    @State private var confirmClear=false
    @State private var clearing=false
    @State private var clearMessage:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Advanced settings").font(.title2.bold())
            Toggle("Diagnostics mode",isOn:$model.diagnosticSettings.enabled).toggleStyle(.switch)
            Text("Diagnostics mode is for troubleshooting and development and is off by default. It enables optional camera clips and keeps detailed game logs. With it off, a finished game's observation log is deleted after successful SGF export; unfinished games keep their recovery evidence. Game moves and clock state stay. Turning the mode off stops image collection; closing these settings leaves it unchanged.")
                .font(.callout).foregroundStyle(.secondary)
            GroupBox("Automatic camera clips") {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Save a clip when a byoyomi period is lost",isOn:$model.diagnosticSettings.byoyomiLosses)
                    Text("Includes the final period expiring. Clips keep clock states, hand-clear estimates and any automatic restoration of the period. Works with speech off.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Save uncertain or delayed moves",isOn:$model.diagnosticSettings.unusualMoves)
                    Text("Saves recognition problems, not unusual Go strategy. Local clips cover moves uncertain for 2 seconds, delays of at least 5 seconds, unrecorded-stones warnings, and move-order reviews or recovery. Online clips also include low-confidence or off-center detections.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Before the event",selection:$model.diagnosticSettings.beforeSeconds) {
                        ForEach([2,4,6],id:\.self) {Text("\($0) seconds").tag($0)}
                    }
                    Picker("After the event",selection:$model.diagnosticSettings.afterSeconds) {
                        ForEach([3,5,8],id:\.self) {Text("\($0) seconds").tag($0)}
                    }
                    Picker("Clip frame rate",selection:$model.diagnosticSettings.framesPerSecond) {
                        ForEach([2,5,10],id:\.self) {Text("Up to \($0) fps").tag($0)}
                    }
                    Text("Collection is inactive when Diagnostics mode is off. Full-resolution images. Actual coverage depends on camera delivery and the 256 MB buffer; higher rates use more memory and disk. This setting does not change recognition or clock timing.")
                        .font(.caption).foregroundStyle(.secondary)
                    MoveEvidenceControls(capture:model.moveEvidenceCapture,textScale:model.interfaceScale)
                }.padding(6)
            }
            GroupBox("Continuous diagnostics") {
                VStack(alignment:.leading,spacing:10) {
                    Toggle("Record continuous camera images",isOn:Binding(get:{diagnostics.isCapturing},set:{enabled in
                        if enabled {model.startDiagnostics()} else {diagnostics.stop()}
                    })).toggleStyle(.switch).disabled(!model.diagnosticSettings.enabled || (!diagnostics.isCapturing && !diagnostics.canStart))
                    Picker("Maximum continuous capture",selection:$diagnostics.limitGB) {
                        ForEach([1,5,10],id:\.self) {Text("\($0) GB").tag($0)}
                    }.disabled(!diagnostics.canStart)
                    Text("Continuous recording must be started manually after opening the app. It includes camera frames while play is paused.").font(.caption).foregroundStyle(.secondary)
                    Text(diagnostics.status).foregroundStyle(diagnostics.state == .failed ? Color.red:Color.secondary)
                    KeepDiagnosticCapture(folder:diagnostics.folder)
                    Button("Show continuous captures") {
                        let folder=diagnostics.folder ?? CaptureFolders.root
                        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                        NSWorkspace.shared.open(folder)
                    }
                }.padding(6)
            }
            Text("Camera archives share a 10 GB allowance. Oldest inactive clips rotate automatically. Keep a capture to exclude it from rotation.")
                .font(.caption).foregroundStyle(.secondary)
            Button(clearing ? "Clearing diagnostic data…":"Clear diagnostic data…",role:.destructive) {confirmClear=true}
                .disabled(clearing)
                .alert("Clear diagnostic data?",isPresented:$confirmClear) {
                    Button("Cancel",role:.cancel) {}
                    Button("Delete camera archives",role:.destructive) {clearArchives()}
                } message: {
                    Text("Permanently delete completed automatic clips and continuous camera captures, including their diagnostic logs. Captures marked Keep and active captures stay. Saved games, game and clock history, calibration and photo samples stay. Diagnostics settings are unchanged; enabled collection can save new clips. This cannot be undone.")
                }
            if let clearMessage {Text(clearMessage).font(.callout).textSelection(.enabled)}
            Toggle("Show diagnostic data and detection tools in the main window",isOn:$model.showDiagnostics)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func clearArchives() {
        clearing=true;clearMessage=nil
        let roots=DiagnosticArchiveStorage.shared.roots
        Task { @MainActor in
            do {
                let result=try await Task.detached(priority:.utility) {try DiagnosticArchiveStorage.clearInactive(roots:roots)}.value
                clearMessage=result.message
            } catch {clearMessage="Could not clear diagnostic data: \(error.localizedDescription)"}
            clearing=false
        }
    }
}

struct DiagnosticIndicator:View {
    @ObservedObject var diagnostics:DiagnosticRecorder
    var body:some View {
        if diagnostics.isCapturing {
            Label("Saving diagnostics · \(diagnostics.savedFrames) images",systemImage:"circle.inset.filled")
                .foregroundStyle(.orange).accessibilityLabel("Diagnostic image recording active")
        } else if diagnostics.state == .failed {
            Label("DIAGNOSTICS STOPPED",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if diagnostics.state == .finishing {
            Text("Finishing diagnostics…").foregroundStyle(.secondary)
        }
    }
}

@MainActor final class DiagnosticAppDelegate:NSObject,NSApplicationDelegate {
    weak var recorder:GameRecorder?
    weak var scoring:PhysicalScoring?
    weak var diagnostics:DiagnosticRecorder?
    weak var onlineBoard:PhysicalOnlineBoard?
    weak var moveEvidence:MoveEvidenceCapture?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard recorder?.flushForExit() != false else {return .terminateCancel}
        scoring?.shutdown()
        diagnostics?.closeForExit()
        onlineBoard?.flushTiming()
        moveEvidence?.closeForExit()
        return .terminateNow
    }
}

private struct MoveEvidenceControls:View {
    @ObservedObject var capture:MoveEvidenceCapture
    let textScale:Double
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            Text(capture.recorder.state == .failed ? capture.recorder.status:capture.status)
                .foregroundStyle(capture.recorder.state == .failed ? Color.red:Color.secondary)
            KeepDiagnosticCapture(folder:capture.recorder.folder)
            Button("Show saved clips") {
                do {
                    try FileManager.default.createDirectory(at:capture.root,withIntermediateDirectories:true)
                    NSWorkspace.shared.open(capture.root)
                } catch {NSLog("Could not open move captures: %@",error.localizedDescription)}
            }
        }.font(.system(size:12*textScale))
    }
}


/// Visible even when the diagnostic controls are collapsed.
struct MoveCaptureIndicator:View {
    @ObservedObject var capture:MoveEvidenceCapture
    var body:some View {
        if capture.storageBlocked {
            Label(capture.status,systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else if capture.enabled && capture.recorder.state != .failed {
            Label("Automatic diagnostic clips enabled",systemImage:"camera.badge.ellipsis")
                .font(.caption).foregroundStyle(.secondary)
        }
        if capture.recorder.state == .failed {
            Label(capture.recorder.status,systemImage:"exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}


private struct KeepDiagnosticCapture:View {
    let folder:URL?
    @State private var kept=false
    @State private var error:String?
    var body:some View {
        Group {
            if let folder {
                Toggle("Keep this capture — exclude from rotation",isOn:Binding(get:{kept},set:{value in
                    do {
                        let marker=folder.appendingPathComponent("KEEP")
                        if value {try Data().write(to:marker,options:.atomic)}
                        else if FileManager.default.fileExists(atPath:marker.path) {try FileManager.default.removeItem(at:marker)}
                        kept=value;error=nil
                    } catch {self.error="Could not change capture retention: \(error.localizedDescription)"}
                })).disabled(!FileManager.default.fileExists(atPath:folder.path))
                if let error {Text(error).foregroundStyle(.red)}
            }
        }.onAppear {refresh()}.onChange(of:folder) {_,_ in refresh()}
    }
    private func refresh() {kept=folder.map{FileManager.default.fileExists(atPath:$0.appendingPathComponent("KEEP").path)} ?? false;error=nil}
}
