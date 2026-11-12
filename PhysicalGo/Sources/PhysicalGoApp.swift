import SwiftUI

@main @MainActor struct PhysicalGoApp: App {
    @NSApplicationDelegateAdaptor(DiagnosticAppDelegate.self) private var delegate
    @StateObject private var model: ExperimentModel
    private let startsCamera:Bool
    init() {
        let model = ExperimentModel()
        let arguments = ProcessInfo.processInfo.arguments
        startsCamera = !arguments.contains("--open-sample") && !arguments.contains("--no-camera")
        if let index = arguments.firstIndex(of:"--open-sample"), index+1 < arguments.count {
            do { try model.openSample(from:URL(fileURLWithPath:arguments[index+1])) }
            catch { model.message = "Could not open sample: \(error.localizedDescription)" }
        }
        if let index=arguments.firstIndex(of:"--review-recording"),index+1<arguments.count {
            do {
                try model.recorder.restoreSavedGame(from:URL(fileURLWithPath:arguments[index+1]))
                if model.size != model.recorder.game.boardSize { model.size=model.recorder.game.boardSize;model.boardSizeChanged() }
            } catch { model.message="Could not restore recording: \(error.localizedDescription)" }
        } else if startsCamera {
            model.restoreLastLocalGame()
        }
        _model = StateObject(wrappedValue:model)
    }
    var body: some Scene {
        WindowGroup("Physical Go") {
            ExperimentView(model: model)
                .frame(minWidth: 1060, minHeight: 740)
                .task {model.scoring.startMonitoring(recorder:model.recorder,isLocal:{[weak model] in model?.playMode == .local});delegate.recorder=model.recorder;delegate.scoring=model.scoring;delegate.diagnostics=model.diagnostics;delegate.onlineBoard=model.onlineBoard;delegate.moveEvidence=model.moveEvidenceCapture;if startsCamera {model.startCameraOnLaunch()}}
                .onDisappear { model.scoring.shutdown();model.stop() }
        }.defaultSize(width: 1280, height: 880)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
