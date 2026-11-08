import SwiftUI
import AppKit

struct DiagnosticControls:View {
    @ObservedObject var model:ExperimentModel
    @ObservedObject var diagnostics:DiagnosticRecorder
    var body:some View {
        GroupBox {
            VStack(alignment:.leading,spacing:10) {
                Text("What to collect").font(.system(size:14*model.interfaceScale,weight:.semibold))
                Text("Game moves and lightweight decision/timing logs are always saved. Camera image collection is optional.")
                    .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
                HStack {
                    Toggle("Record continuous camera images",isOn:Binding(get:{diagnostics.isCapturing},set:{enabled in
                        if enabled {model.startDiagnostics()} else {diagnostics.stop()}
                    })).toggleStyle(.switch).disabled(!diagnostics.isCapturing && !diagnostics.canStart)
                    Button("Show folder") {
                        let folder=diagnostics.folder ?? CaptureFolders.root
                        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                        NSWorkspace.shared.open(folder)
                    }
                }
                Picker("Storage limit",selection:$diagnostics.limitGB) {
                    ForEach([1,5,10],id:\.self) {Text("\($0) GB").tag($0)}
                }.disabled(!diagnostics.canStart)
                Text(diagnostics.status).foregroundStyle(diagnostics.state == .failed ? Color.red : Color.secondary)
                    .font(.system(size:12*model.interfaceScale))
                if diagnostics.folder != nil {
                    Text("\(diagnostics.savedFrames) images · \(ByteCountFormatter.string(fromByteCount:diagnostics.savedBytes,countStyle:.file)) saved")
                        .font(.system(size:12*model.interfaceScale).monospacedDigit())
                }
                MoveEvidenceControls(capture:model.moveEvidenceCapture,textScale:model.interfaceScale)
                Text("About 5 lossless images/second, including skipped frames. Continues while the game is paused. Stops at the limit or when the app closes; saved files stay until you delete them.")
                    .font(.system(size:12*model.interfaceScale)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
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
            Toggle("Save unusual moves automatically",isOn:$capture.enabled)
            Text("Online borderline moves, or local candidates unresolved for 2 seconds, save a short camera clip. Delays over 5 seconds are flagged. 4 seconds before, 3 after, up to 2 frames/second. Stored locally, up to 5 GB; saved clips are retained.")
            Text(capture.recorder.state == .failed ? capture.recorder.status:capture.status)
                .foregroundStyle(capture.recorder.state == .failed ? Color.red:Color.secondary)
            Button("Show move captures") {
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
        if capture.enabled {
            Label("Unusual-move clips enabled",systemImage:"camera.badge.ellipsis")
                .font(.caption).foregroundStyle(.secondary)
        }
        if capture.recorder.state == .failed {
            Label(capture.recorder.status,systemImage:"exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
