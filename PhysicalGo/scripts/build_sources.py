"""One dependency closure for app builds, regression suites and replay tools."""
from pathlib import Path

DEPENDENCIES = {
    'Sources/AutomaticCapture.swift': ('Sources/PlacementAlternatives.swift',),
    'Sources/HandOutlineTracker.swift': ('Sources/HandOutlineTiming.swift','Sources/HandMotionTiming.swift'),
    'Sources/HandOutlineSampling.swift': ('Sources/HandOutlineTracker.swift','Sources/BoardVision.swift'),
    'Sources/DiagnosticRecorder.swift': ('Sources/DiagnosticArchiveStorage.swift',),
    'Sources/CameraCapture.swift': ('Sources/CameraFrameTimestamp.swift','Sources/CameraProcessingCadence.swift','Sources/CameraFeedHealth.swift'),
    'Sources/CameraProcessingCadence.swift': ('Sources/LocalClockEngine.swift',),
    'Sources/BoardHandDetector.swift': ('Sources/HandMotionTiming.swift',),
    'Sources/LocalClockEngine.swift': ('Sources/HandMotionTiming.swift',),
    'Sources/RecordingRecoveryGuidance.swift': ('Sources/BoardCoordinates.swift', 'Sources/BoardOrientation.swift'),
    'Sources/CameraAnalysisPipeline.swift': ('Sources/BoardHandDetector.swift','Sources/HandOutlineSampling.swift','Sources/BoardAlignmentGate.swift'),
    'Sources/BoardVision.swift': ('Sources/BoardAppearanceDetector.swift', 'Sources/LightingCompensation.swift', 'Sources/HandMotionTiming.swift'),
    'Sources/MoveObservationHistory.swift': ('Sources/PlacementAlternatives.swift',),
    'Sources/BoardRectifier.swift': ('Sources/GridLineAspectEstimator.swift',),
    'Sources/PhysicalOnlineBoard.swift': (
        'Sources/HistoricalMoveEvidence.swift', 'Sources/PhysicalMoveTiming.swift', 'Sources/ManualBoardCorrections.swift',
        'Sources/PhysicalUndoController.swift', 'Sources/PhysicalUndoView.swift'),
    'Sources/GameRecorder.swift': tuple('Sources/' + name for name in (
        'LocalPlayFlow.swift', 'PlacementAmbiguity.swift', 'ProvisionalPlay.swift', 'RecordingRecoveryGuidance.swift', 'ReviewObservationEdit.swift', 'HistoricalMoveCorrection.swift', 'RecordingIdentity.swift', 'RecordingStore.swift', 'ReviewHistoryCoordinator.swift',
        'AutomaticCapture.swift', 'HandOutlineTracker.swift', 'AccidentalStoneWithdrawal.swift', 'CaptureReviewPlan.swift', 'CheckedReviewPhoto.swift', 'BoardRestorationPlan.swift', 'BoardAdjustmentMonitor.swift', 'LocalClockEngine.swift',
        'LocalGameClock.swift', 'LocalClockAudio.swift', 'DeferredMoveHistory.swift', 'ReviewOrderRecovery.swift')),
    'Sources/LocalGameClock.swift': ('Sources/DiagnosticSettings.swift','Sources/RecordingStorage.swift'),
    'Sources/LocalClockAudio.swift': ('Sources/KokoroSpeech.swift',),
    'Sources/PhysicalScoring.swift': tuple('../SGFPlayerClean/' + name for name in (
        'Models/AIModels.swift', 'Models/LocalScoring.swift', 'Services/KataGoEngine.swift',
        'Services/Networking/OGSConnectionController.swift')),
}

def resolve_sources(root: Path, sources: list[Path]) -> list[Path]:
    dependencies = {(root / source).resolve(): [root / item for item in items]
                    for source, items in DEPENDENCIES.items()}
    dependencies[(root / 'Sources/KokoroSpeech.swift').resolve()] = sorted(
        (root / 'Vendor/KokoroCoreML/Sources').rglob('*.swift'))
    resolved = []
    seen = set()
    pending = list(sources)
    for source in pending:
        source = source.resolve()
        if source in seen:
            continue
        if not source.is_file():
            raise FileNotFoundError(f'Missing build source: {source}')
        seen.add(source)
        resolved.append(source)
        pending.extend(dependencies.get(source, ()))
    return resolved
