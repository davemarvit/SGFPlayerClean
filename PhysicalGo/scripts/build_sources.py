"""One dependency closure for app builds, regression suites and replay tools."""
from pathlib import Path

DEPENDENCIES = {
    'Sources/BoardVision.swift': ('Sources/BoardAppearanceDetector.swift', 'Sources/LightingCompensation.swift'),
    'Sources/BoardRectifier.swift': ('Sources/GridLineAspectEstimator.swift',),
    'Sources/PhysicalOnlineBoard.swift': (
        'Sources/HistoricalMoveEvidence.swift', 'Sources/PhysicalMoveTiming.swift', 'Sources/ManualBoardCorrections.swift',
        'Sources/PhysicalUndoController.swift', 'Sources/PhysicalUndoView.swift'),
    'Sources/GameRecorder.swift': tuple('Sources/' + name for name in (
        'RecordingIdentity.swift', 'RecordingStore.swift', 'ReviewHistoryCoordinator.swift',
        'AccidentalStoneWithdrawal.swift', 'CaptureReviewPlan.swift', 'BoardRestorationPlan.swift', 'BoardAdjustmentMonitor.swift', 'LocalClockEngine.swift',
        'LocalGameClock.swift', 'LocalClockAudio.swift', 'DeferredMoveHistory.swift', 'ReviewOrderRecovery.swift')),
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
