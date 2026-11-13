"""Declarative regression suites. Shared source groups and CLI flags live here."""
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class Suite:
    executable: str
    group: str
    tests: tuple[str, ...]
    extra: tuple[str, ...] = ()
    optimized: bool = True

    def sources(self, root: Path) -> list[Path]:
        shared = [root.parent / 'SGFPlayerClean/Models' / name for name in ('OGSModels.swift', 'OGSScoringState.swift')]
        engine = root.parent / 'SGFPlayerClean/Models/SGFPlayerEngine.swift'
        vision = [root / 'Sources' / name for name in ('BoardVision.swift', 'StoneGeometry.swift')]
        groups = {
            'standalone': [],
            'vision': shared + vision,
            'online': shared + [engine] + vision + [root / 'Sources/PhysicalOnlineBoard.swift'],
            'recorder': shared + [engine] + vision + [root / 'Sources' / name for name in
                ('LocalMoveEvidence.swift', 'MoveObservationHistory.swift', 'RecordingWarningMonitor.swift', 'GameRecorder.swift')],
            'app': shared + [engine] + [p for p in sorted((root / 'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'],
        }
        return groups[self.group] + [root / path for path in (*self.extra, *self.tests)] + [root / 'Tests/TestArtifacts.swift']

SUITES = {
    'clock-scheduler-test': Suite('ClockSchedulerTests', 'app', ('Tests/ClockSchedulerTests.swift',), optimized=False),
    'nudged-stone-guidance-test': Suite('NudgedStoneGuidanceTests', 'app', ('Tests/NudgedStoneGuidanceTests.swift',), optimized=False),
    'known-empty-lighting-test': Suite('KnownEmptyLightingTests', 'vision', ('Tests/KnownEmptyLightingTests.swift','Tests/ResidualGlareTests.swift'), extra=('Sources/KnownEmptyLighting.swift',), optimized=False),
    'live-position-issues-test': Suite('LivePositionIssueTests', 'app', ('Tests/LivePositionIssueTests.swift', 'Tests/LiveIssueTimingTests.swift'), optimized=False),
    'storage-flow-test': Suite('RecordingStorageFlowTests', 'app', ('Tests/RecordingStorageFlowTests.swift',), optimized=False),
    'processing-gap-test': Suite('ProcessingGapTests', 'recorder', ('Tests/ProcessingGapTests.swift',), optimized=False),
    'async-diagnostics-test': Suite('AsyncDiagnosticsTests', 'app', ('Tests/AsyncDiagnosticsTests.swift',), optimized=False),
    'g18-rapid-play-test': Suite('G18RapidPlayTests', 'recorder', ('Tests/G18RapidPlayTests.swift',), optimized=False),
    'placement-timing-test': Suite('PlacementTimingTests', 'recorder', ('Tests/PlacementTimingTests.swift',), optimized=False),
    'resume-alignment-test': Suite('ResumeAlignmentTests', 'vision', ('Tests/ResumeAlignmentTests.swift',), extra=('Sources/AutoGridDetector.swift',)),
    'session-resume-test': Suite('SessionResumeTests', 'app', ('Tests/SessionResumeTests.swift',), optimized=False),
    'diagnostic-cleanup-test': Suite('DiagnosticCleanupTests', 'recorder', ('Tests/DiagnosticCleanupTests.swift',), extra=('Sources/DiagnosticArchiveStorage.swift',), optimized=False),
    'byoyomi-diagnostics-test': Suite('ByoyomiDiagnosticsTests', 'app', ('Tests/ByoyomiDiagnosticsTests.swift',), optimized=False),
    'provisional-play-test': Suite('ProvisionalPlayTests', 'app', ('Tests/ProvisionalPlayTests.swift',), optimized=False),
    'adaptive-frame-rate-test': Suite('AdaptiveFrameRateTests', 'standalone', ('Tests/AdaptiveFrameRateTests.swift',), extra=('Sources/CameraProcessingCadence.swift',), optimized=False),
    'hand-outline-test': Suite('HandOutlineTests', 'standalone', ('Tests/HandOutlineTests.swift','Tests/HandOutlineRecordedTests.swift'), extra=('Sources/HandOutlineTracker.swift','Sources/HandOutlineTiming.swift','Sources/HandMotionTiming.swift'), optimized=True),
    'hand-motion-test': Suite('HandMotionTimingTests', 'standalone', ('Tests/HandMotionTimingTests.swift',), extra=('Sources/HandMotionTiming.swift',), optimized=False),
    'hand-clock-test': Suite('HandClockTests', 'recorder', ('Tests/HandClockTests.swift','Tests/ClockCatchUpIncidentTests.swift'), optimized=False),
    'hand-lab-test': Suite('HandTimingLabTests', 'standalone', ('Tests/HandTimingLabTests.swift',), extra=('Tools/HandTimingLab/Capture.swift','Sources/CameraFrameTimestamp.swift'), optimized=False),
    'recovery-guidance-test': Suite('RecoveryGuidanceTests', 'app', ('Tests/RecoveryGuidanceTests.swift',), optimized=False),
    'archive-storage-test': Suite('ArchiveStorageTests', 'standalone', ('Tests/ArchiveStorageTests.swift',), extra=('Sources/DiagnosticArchiveStorage.swift',), optimized=False),
    'archive-review-test': Suite('ArchiveReviewCorrectionTests', 'app', ('Tests/ArchiveReviewCorrectionTests.swift',), optimized=False),
    'historical-correction-test': Suite('HistoricalCorrectionTests', 'app', ('Tests/HistoricalCorrectionTests.swift', 'Tests/BatchCorrectionTests.swift'), optimized=False),
    'capture-clock-test': Suite('CaptureClockTests', 'app', ('Tests/CaptureClockTests.swift', 'Tests/CaptureUncertaintyTests.swift', 'Tests/CaptureConflictGuidanceTests.swift', 'Tests/LocalClockTests.swift'), optimized=False),
    'recovery-lifecycle-test': Suite('RecoveryLifecycleTests', 'app', ('Tests/RecoveryLifecycleTests.swift',), optimized=False),
    'recovery-glare-test': Suite('RecoveryGlareTests', 'vision', ('Tests/RecoveryGlareTests.swift',)),
    'obstruction-feedback-test': Suite('ObstructionFeedbackTests', 'app', ('Tests/ObstructionFeedbackTests.swift', 'Tests/CoveredBorderTests.swift'), optimized=False),
    'undo-move-test': Suite('UndoMoveTests', 'app', ('Tests/UndoMoveTests.swift', 'Tests/LocalClockTests.swift'), optimized=False),
    'score-overlay-test': Suite('ScoreOverlayTests', 'app', ('Tests/ScoreOverlayTests.swift', 'Tests/PhysicalScoringTests.swift', 'Tests/TerritoryAuditTests.swift', 'Tests/ScoreApprovalTests.swift'), extra=(), optimized=False),
    'layout-voice-test': Suite('LayoutVoiceTests', 'app', ('Tests/LayoutVoiceTests.swift',), extra=(), optimized=False),
    'live-play-test': Suite('LivePlayTests', 'app', ('Tests/LivePlayTests.swift',), extra=(), optimized=False),
    'order-recovery-test': Suite('OrderRecoveryTests', 'app', ('Tests/OrderRecoveryTests.swift',), extra=(), optimized=False),
    'review-queue-test': Suite('ReviewQueueTests', 'app', ('Tests/ReviewQueueTests.swift', 'Tests/PhysicalReviewTests.swift'), extra=(), optimized=False),
    'move-recovery-test': Suite('MoveRecoveryTests', 'app', ('Tests/MoveRecoveryTests.swift',), extra=(), optimized=False),
    'workflow-ui-test': Suite('WorkflowUITests', 'app', ('Tests/CameraContinuityTests.swift', 'Tests/CoveredBorderTests.swift', 'Tests/HandicapTests.swift', 'Tests/HandicapVerificationTests.swift', 'Tests/WorkflowUITests.swift', 'Tests/LocalClockTests.swift', 'Tests/ObstructionEvidenceTests.swift', 'Tests/ObservationHistoryTests.swift', 'Tests/LocalMoveEvidenceTests.swift'), extra=(), optimized=False),
    'stone-tracking-ui-test': Suite('StoneTrackingUITests', 'app', ('Tests/StoneTrackingUITests.swift',), extra=(), optimized=False),
    'stone-tracking-test': Suite('EstablishedStoneTrackerTests', 'vision', ('Tests/EstablishedStoneTrackerTests.swift',), extra=('Sources/EstablishedStoneTracker.swift',)),
    'unique-placement-test': Suite('UniquePlacementTests', 'recorder', ('Tests/UniquePlacementTests.swift',)),
    'repositioning-test': Suite('RepositioningTests', 'recorder', ('Tests/RepositioningTests.swift',)),
    'clock-feedback-test': Suite('ClockFeedbackTests', 'app', ('Tests/ClockFeedbackTests.swift', 'Tests/LocalClockTests.swift', 'Tests/RecordingWarningTests.swift'), extra=(), optimized=False),
    'clock-review-test': Suite('ClockReviewTests', 'app', ('Tests/ClockReviewTests.swift', 'Tests/LocalClockTests.swift'), extra=(), optimized=False),
    'lighting-test': Suite('LightingTests', 'vision', ('Tests/LightingTests.swift',), extra=('Sources/AutoGridDetector.swift',)),
    'recovery-ui-test': Suite('RecoveryUITests', 'app', ('Tests/RecoveryUITests.swift',), extra=(), optimized=False),
    'timing-panel-test': Suite('TimingPanelTests', 'app', ('Tests/TimingPanelTests.swift', 'Tests/LocalClockTests.swift', 'Tests/PhysicalScoringTests.swift'), extra=(), optimized=False),
    'play-mode-test': Suite('PlayModeTests', 'app', ('Tests/PlayModeTests.swift',)),
    'occlusion-context-test': Suite('OcclusionContextTests', 'vision', ('Tests/OcclusionContextTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'covered-grid-stone-test': Suite('CoveredGridStoneTests', 'vision', ('Tests/CoveredGridStoneTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'visible-grid-stone-test': Suite('VisibleGridStoneTests', 'vision', ('Tests/VisibleGridStoneTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'historical-move-test': Suite('HistoricalMoveTests', 'online', ('Tests/HistoricalMoveTests.swift',)),
    'move-capture-test': Suite('MoveCaptureTests', 'app', ('Tests/MoveCaptureTests.swift',)),
    'move-timing-test': Suite('MoveTimingTests', 'standalone', ('Tests/MoveTimingTests.swift',), extra=('Sources/PhysicalMoveTiming.swift',)),
    'correction-photo-test': Suite('CorrectionPhotoOrientationTests', 'app', ('Tests/CorrectionPhotoOrientationTests.swift',)),
    'touching-shadow-test': Suite('TouchingShadowTests', 'vision', ('Tests/TouchingShadowTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'reference-feedback-test': Suite('ReferenceFeedbackTests', 'app', ('Tests/ReferenceFeedbackTests.swift',)),
    'stone-calibration-test': Suite('StoneCalibrationTests', 'app', ('Tests/StoneCalibrationTests.swift',)),
    'correction-test': Suite('BoardCorrectionTests', 'online', ('Tests/BoardCorrectionTests.swift',), extra=('Sources/ManualBoardCorrections.swift', 'Sources/CorrectionArchive.swift')),
    'shaded-cross-test': Suite('ShadedCrossTests', 'vision', ('Tests/ShadedCrossTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'grid-aspect-test': Suite('GridAspectTests', 'vision', ('Tests/GridAspectTests.swift',), extra=('Sources/BoardRectifier.swift', 'Sources/BoardOrientation.swift')),
    'view-orientation-test': Suite('ViewOrientationTests', 'app', ('Tests/ViewOrientationTests.swift',)),
    'online-test': Suite('OnlineBoardTests', 'online', ('Tests/OnlineBoardTests.swift',)),
    'crowded-white-test': Suite('CrowdedWhiteAdjustmentTests', 'recorder', ('Tests/CrowdedWhiteAdjustmentTests.swift',)),
    'touching-edge-test': Suite('TouchingEdgeTests', 'vision', ('Tests/TouchingEdgeTests.swift',)),
    'centered-stone-test': Suite('CenteredStoneTests', 'app', ('Tests/CenteredStoneTests.swift',)),
    'capture-continuation-test': Suite('CaptureContinuationTests', 'app', ('Tests/CaptureContinuationTests.swift',)),
    'grid-ui-test': Suite('GridRefinementUITests', 'app', ('Tests/GridRefinementUITests.swift',)),
    'crowded-adjustment-test': Suite('CrowdedAdjustmentTests', 'recorder', ('Tests/CrowdedAdjustmentTests.swift',)),
    'stall-session-test': Suite('StallSessionTests', 'recorder', ('Tests/StallSessionTests.swift',)),
    'visibility-test': Suite('SixMoveVisibilityTests', 'app', ('Tests/SixMoveVisibilityTests.swift',)),
    'diagnostic-test': Suite('DiagnosticTests', 'app', ('Tests/DiagnosticTests.swift',)),
    'placement-confidence-test': Suite('SpatialPlacementTests', 'recorder', ('Tests/SpatialPlacementTests.swift', 'Tests/PlacementSessionTests.swift')),
    'stone-aspect-test': Suite('StoneAspectTests', 'vision', ('Tests/StoneAspectTests.swift',), extra=('Sources/BoardRectifier.swift', 'Sources/StoneAspectEstimator.swift')),
    'morning-session-test': Suite('MorningSessionTests', 'vision', ('Tests/MorningSessionTests.swift',)),
    'session-regression-test': Suite('DiagnosticSessionTests', 'recorder', ('Tests/DiagnosticSessionTests.swift',)),
    'persistence-test': Suite('RecordingPersistenceTests', 'recorder', ('Tests/RecordingPersistenceTests.swift',), extra=(), optimized=False),
    'recorder-test': Suite('RecorderTests', 'recorder', ('Tests/RecorderTests.swift', 'Tests/HandicapTests.swift', 'Tests/TentativeTailTests.swift', 'Tests/ObservationHistoryTests.swift', 'Tests/RecordingWarningTests.swift', 'Tests/LocalMoveEvidenceTests.swift', 'Tests/RapidPlayTests.swift', 'Tests/TentativeHistoryTests.swift', 'Tests/PlacementConfidenceTests.swift', 'Tests/ObstructionEvidenceTests.swift')),
    'geometry-test': Suite('GeometryTests', 'vision', ('Tests/GeometryTests.swift',)),
    'displaced-neighbors-test': Suite('DisplacedNeighborsTests', 'vision', ('Tests/DisplacedNeighborsTests.swift',)),
    'reference-offset-test': Suite('ReferenceOffsetTests', 'vision', ('Tests/ReferenceOffsetTests.swift',)),
    'shadow-test': Suite('ShadowTests', 'vision', ('Tests/ShadowTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'grain-test': Suite('GrainTests', 'vision', ('Tests/GrainTests.swift',), extra=('Sources/BoardAppearanceDetector.swift',)),
    'appearance-test': Suite('AppearanceTests', 'vision', ('Tests/AppearanceTests.swift',), extra=('Sources/BoardAppearanceDetector.swift', 'Sources/EmptyBoardVerifier.swift', 'Sources/AutoGridDetector.swift')),
    'covered-border-test': Suite('CoveredBorderTests', 'vision', ('Tests/CoveredBorderTests.swift', 'Tests/CoveredBorderTestMain.swift'), extra=('../SGFPlayerClean/Models/SGFPlayerEngine.swift', 'Sources/AutoGridDetector.swift')),
    'bump-test': Suite('BumpTests', 'vision', ('Tests/BumpTests.swift',), extra=('Sources/AutoGridDetector.swift', 'Sources/BoardRecoveryPrompt.swift')),
    'grid-test': Suite('AutoGridTests', 'vision', ('Tests/AutoGridTests.swift',), extra=('Sources/AutoGridDetector.swift',)),
    'camera-test': Suite('CameraHealthTests', 'standalone', ('Tests/CameraHealthTests.swift',), extra=('Sources/CameraHealth.swift','Sources/CameraFeedHealth.swift')),
    'test': Suite('PhysicalGoTests', 'vision', ('Tests/RectificationTests.swift', 'Tests/PlacementTests.swift', 'Tests/VisionTests.swift'), extra=('Sources/BoardOrientation.swift', 'Sources/BoardRectifier.swift')),
}
