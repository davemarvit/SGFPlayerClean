#!/usr/bin/env python3
"""Build an independent app, referencing authoritative Go models without copying them."""
from pathlib import Path
import argparse, hashlib, os, plistlib, re, subprocess, shutil
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--occlusion-context-test', action='store_true')
parser.add_argument('--covered-grid-stone-test', action='store_true')
parser.add_argument('--visible-grid-stone-test', action='store_true')
parser.add_argument('--historical-move-test', action='store_true')
parser.add_argument('--move-timing-test', action='store_true')
parser.add_argument('--move-capture-test', action='store_true')
parser.add_argument('--play-mode-test', action='store_true')
parser.add_argument('--timing-panel-test', action='store_true')
parser.add_argument('--correction-photo-test', action='store_true')
parser.add_argument('--touching-shadow-test', action='store_true')
parser.add_argument('--reference-feedback-test', action='store_true')
parser.add_argument('--stone-calibration-test', action='store_true')
parser.add_argument('--stone-appearance-audit', type=Path)
parser.add_argument('--correction-test', action='store_true')
parser.add_argument('--crowded-white-test', action='store_true')
parser.add_argument('--touching-edge-test', action='store_true')
parser.add_argument('--centered-stone-test', action='store_true')
parser.add_argument('--capture-continuation-test', action='store_true')
parser.add_argument('--grid-ui-test', action='store_true')
parser.add_argument('--recovery-ui-test', action='store_true')
parser.add_argument('--lighting-test', action='store_true')
parser.add_argument('--clock-feedback-test', action='store_true')
parser.add_argument('--clock-review-test', action='store_true')
parser.add_argument('--unique-placement-test', action='store_true')
parser.add_argument('--repositioning-test', action='store_true')
parser.add_argument('--stone-tracking-test', action='store_true')
parser.add_argument('--stone-tracking-ui-test', action='store_true')
parser.add_argument('--workflow-ui-test', action='store_true')
parser.add_argument('--move-recovery-test', action='store_true')
parser.add_argument('--order-recovery-test', action='store_true')
parser.add_argument('--review-queue-test', action='store_true')
parser.add_argument('--live-play-test', action='store_true')
parser.add_argument('--layout-voice-test', action='store_true')
parser.add_argument('--score-overlay-test', action='store_true')
parser.add_argument('--voice-assets', action='store_true')
parser.add_argument('--crowded-adjustment-test', action='store_true')
parser.add_argument('--stall-session-test', action='store_true')
parser.add_argument('--visibility-test', action='store_true')
parser.add_argument('--placement-confidence-test', action='store_true')
parser.add_argument('--stone-aspect-test', action='store_true')
parser.add_argument('--recorder-test', action='store_true')
parser.add_argument('--session-regression-test', action='store_true')
parser.add_argument('--morning-session-test', action='store_true')
parser.add_argument('--diagnostic-test', action='store_true')
parser.add_argument('--replay-session', nargs=2, type=Path, metavar=('SESSION','NEW_OUTPUT_FOLDER'))
parser.add_argument('--saved-observations', action='store_true')
parser.add_argument('--replay-diagnostic', nargs=2, metavar=('SESSION','FRAME'))
parser.add_argument('--replay-recording', nargs=3, type=Path, metavar=('SGF','JOURNAL','OUTPUT'))
parser.add_argument('--grid-aspect-test', action='store_true')
parser.add_argument('--view-orientation-test', action='store_true')
parser.add_argument('--online-test', action='store_true')
parser.add_argument('--test', action='store_true')
parser.add_argument('--preview', action='store_true')
parser.add_argument('--camera-test', action='store_true')
parser.add_argument('--inspect-sample', type=Path)
parser.add_argument('--grid-test', action='store_true')
parser.add_argument('--bump-test', action='store_true')
parser.add_argument('--covered-border-test', action='store_true')
parser.add_argument('--appearance-test', action='store_true')
parser.add_argument('--grain-test', action='store_true')
parser.add_argument('--shadow-test', action='store_true')
parser.add_argument('--shaded-cross-test', action='store_true')
parser.add_argument('--reference-offset-test', action='store_true')
parser.add_argument('--displaced-neighbors-test', action='store_true')
parser.add_argument('--geometry-test', action='store_true')
args = parser.parse_args()
if args.saved_observations and not args.replay_session:
    parser.error("--saved-observations requires --replay-session")
build = root / '.build'
build.mkdir(exist_ok=True)
shared = [root.parent / 'SGFPlayerClean/Models' / f for f in ['OGSModels.swift', 'OGSScoringState.swift']]
if args.voice_assets:
    executable=build/'KokoroVoiceTests'
    sources=[root/'Sources/KokoroSpeech.swift',root/'Tests/KokoroVoiceTests.swift']
elif args.score_overlay_test:
    executable=build/'ScoreOverlayTests'
    sources=shared+[root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift']+[p for p in sorted((root/'Sources').glob('*.swift')) if p.name!='PhysicalGoApp.swift']+[root/'Tests/ScoreOverlayTests.swift',root/'Tests/PhysicalScoringTests.swift',root/'Tests/TerritoryAuditTests.swift',root/'Tests/ScoreApprovalTests.swift']
elif args.layout_voice_test:
    executable=build/'LayoutVoiceTests'
    sources=shared+[root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift']+[p for p in sorted((root/'Sources').glob('*.swift')) if p.name!='PhysicalGoApp.swift']+[root/'Tests/LayoutVoiceTests.swift']
elif args.live_play_test:
    executable = build / 'LivePlayTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/LivePlayTests.swift']
elif args.order_recovery_test:
    executable = build / 'OrderRecoveryTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/OrderRecoveryTests.swift']
elif args.review_queue_test:
    executable = build / 'ReviewQueueTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/ReviewQueueTests.swift']
elif args.move_recovery_test:
    executable = build / 'MoveRecoveryTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/MoveRecoveryTests.swift']
elif args.workflow_ui_test:
    executable = build / 'WorkflowUITests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/CameraContinuityTests.swift',root/'Tests/CoveredBorderTests.swift',root/'Tests/HandicapTests.swift',root/'Tests/HandicapVerificationTests.swift',root/'Tests/WorkflowUITests.swift',root/'Tests/LocalClockTests.swift',root/'Tests/ObstructionEvidenceTests.swift',root/'Tests/ObservationHistoryTests.swift',root/'Tests/LocalMoveEvidenceTests.swift']
elif args.stone_tracking_ui_test:
    executable = build / 'StoneTrackingUITests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/StoneTrackingUITests.swift']
elif args.stone_tracking_test:
    executable = build / 'EstablishedStoneTrackerTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','EstablishedStoneTracker.swift']] + [root/'Tests/EstablishedStoneTrackerTests.swift']
elif args.unique_placement_test or args.repositioning_test:
    executable = build / ('RepositioningTests' if args.repositioning_test else 'UniquePlacementTests')
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/('Tests/RepositioningTests.swift' if args.repositioning_test else 'Tests/UniquePlacementTests.swift')]
elif args.clock_feedback_test:
    executable = build / 'ClockFeedbackTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/ClockFeedbackTests.swift',root/'Tests/LocalClockTests.swift',root/'Tests/RecordingWarningTests.swift']
elif args.clock_review_test:
    executable = build / 'ClockReviewTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/ClockReviewTests.swift',root/'Tests/LocalClockTests.swift']
elif args.lighting_test:
    executable = build / 'LightingTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','AutoGridDetector.swift']] + [root/'Tests/LightingTests.swift']
elif args.recovery_ui_test:
    executable = build / 'RecoveryUITests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/RecoveryUITests.swift']
elif args.timing_panel_test:
    executable = build / 'TimingPanelTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/TimingPanelTests.swift',root/'Tests/LocalClockTests.swift',root/'Tests/PhysicalScoringTests.swift']
elif args.play_mode_test:
    executable = build / 'PlayModeTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/PlayModeTests.swift']
elif args.occlusion_context_test:
    executable = build / 'OcclusionContextTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift']] + [root/'Tests/OcclusionContextTests.swift']
elif args.covered_grid_stone_test:
    executable = build / 'CoveredGridStoneTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift']] + [root/'Tests/CoveredGridStoneTests.swift']
elif args.visible_grid_stone_test:
    executable = build / 'VisibleGridStoneTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift']] + [root/'Tests/VisibleGridStoneTests.swift']
elif args.historical_move_test:
    executable = build / 'HistoricalMoveTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','PhysicalOnlineBoard.swift']] + [root/'Tests/HistoricalMoveTests.swift']
elif args.move_capture_test:
    executable = build / 'MoveCaptureTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/MoveCaptureTests.swift']
elif args.move_timing_test:
    executable = build / 'MoveTimingTests'
    sources = [root/'Sources/PhysicalMoveTiming.swift',root/'Tests/MoveTimingTests.swift']
elif args.correction_photo_test:
    executable = build / 'CorrectionPhotoOrientationTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/CorrectionPhotoOrientationTests.swift']
elif args.touching_shadow_test:
    executable = build / 'TouchingShadowTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift']] + [root/'Tests/TouchingShadowTests.swift']
elif args.reference_feedback_test:
    executable = build / 'ReferenceFeedbackTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/ReferenceFeedbackTests.swift']
elif args.stone_calibration_test:
    executable = build / 'StoneCalibrationTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/StoneCalibrationTests.swift']
elif args.stone_appearance_audit:
    executable = build / 'StoneAppearanceAudit'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift','StoneAppearanceModel.swift']] + [root/'Tools/StoneAppearanceAudit.swift']
elif args.correction_test:
    executable = build / 'BoardCorrectionTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','PhysicalOnlineBoard.swift','ManualBoardCorrections.swift','CorrectionArchive.swift']] + [root/'Tests/BoardCorrectionTests.swift']
elif args.shaded_cross_test:
    executable = build / 'ShadedCrossTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift',root/'Tests/ShadedCrossTests.swift']
elif args.grid_aspect_test:
    executable = build / 'GridAspectTests'
    sources = shared + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardRectifier.swift','BoardOrientation.swift']] + [root/'Tests/GridAspectTests.swift']
elif args.view_orientation_test:
    executable = build / 'ViewOrientationTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/ViewOrientationTests.swift']
elif args.online_test:
    executable = build / 'OnlineBoardTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','PhysicalOnlineBoard.swift']] + [root/'Tests/OnlineBoardTests.swift']
elif args.crowded_white_test:
    executable = build / 'CrowdedWhiteAdjustmentTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/'Tests/CrowdedWhiteAdjustmentTests.swift']
elif args.touching_edge_test:
    executable = build / 'TouchingEdgeTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Tests/TouchingEdgeTests.swift']
elif args.centered_stone_test:
    executable = build / 'CenteredStoneTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/CenteredStoneTests.swift']
elif args.capture_continuation_test:
    executable = build / 'CaptureContinuationTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/CaptureContinuationTests.swift']
elif args.grid_ui_test:
    executable = build / 'GridRefinementUITests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/GridRefinementUITests.swift']
elif args.crowded_adjustment_test:
    executable = build / 'CrowdedAdjustmentTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/'Tests/CrowdedAdjustmentTests.swift']
elif args.stall_session_test:
    executable = build / 'StallSessionTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/'Tests/StallSessionTests.swift']
elif args.visibility_test:
    executable = build / 'SixMoveVisibilityTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/SixMoveVisibilityTests.swift']
elif args.replay_session:
    executable = build / 'ReplayDiagnosticSession'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/'Tools/ReplayDiagnosticSession.swift']
elif args.replay_diagnostic:
    executable = build / 'ReplayDiagnostic'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift',root/'Sources/AutoGridDetector.swift',root/'Tools/ReplayDiagnostic.swift']
elif args.diagnostic_test:
    executable = build / 'DiagnosticTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/DiagnosticTests.swift']
elif args.replay_recording:
    executable = build / 'ReplayRecording'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift',root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/LocalMoveEvidence.swift',root/'Sources/MoveObservationHistory.swift',root/'Sources/RecordingWarningMonitor.swift',root/'Sources/GameRecorder.swift',root/'Tools/ReplayRecording.swift']
elif args.placement_confidence_test:
    executable = build / 'SpatialPlacementTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/'Tests/SpatialPlacementTests.swift',root/'Tests/PlacementSessionTests.swift']
elif args.stone_aspect_test:
    executable = build / 'StoneAspectTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardRectifier.swift',root/'Sources/StoneAspectEstimator.swift',root/'Tests/StoneAspectTests.swift']
elif args.morning_session_test:
    executable = build / 'MorningSessionTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Tests/MorningSessionTests.swift']
elif args.session_regression_test:
    executable = build / 'DiagnosticSessionTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','LocalMoveEvidence.swift','MoveObservationHistory.swift','RecordingWarningMonitor.swift','GameRecorder.swift']] + [root/'Tests/DiagnosticSessionTests.swift']
elif args.recorder_test:
    executable = build / 'RecorderTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift',root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/LocalMoveEvidence.swift',root/'Sources/MoveObservationHistory.swift',root/'Sources/RecordingWarningMonitor.swift',root/'Sources/GameRecorder.swift',root/'Tests/RecorderTests.swift',root/'Tests/HandicapTests.swift',root/'Tests/TentativeTailTests.swift',root/'Tests/ObservationHistoryTests.swift',root/'Tests/RecordingWarningTests.swift',root/'Tests/LocalMoveEvidenceTests.swift',root/'Tests/RapidPlayTests.swift',root/'Tests/TentativeHistoryTests.swift',root/'Tests/PlacementConfidenceTests.swift',root/'Tests/ObstructionEvidenceTests.swift']
elif args.geometry_test:
    executable = build / 'GeometryTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Tests/GeometryTests.swift']
elif args.displaced_neighbors_test:
    executable = build / 'DisplacedNeighborsTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Tests/DisplacedNeighborsTests.swift']
elif args.reference_offset_test:
    executable = build / 'ReferenceOffsetTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Tests/ReferenceOffsetTests.swift']
elif args.shadow_test:
    executable = build / 'ShadowTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift',root/'Tests/ShadowTests.swift']
elif args.grain_test:
    executable = build / 'GrainTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift',root/'Tests/GrainTests.swift']
elif args.appearance_test:
    executable = build / 'AppearanceTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift',root/'Sources/EmptyBoardVerifier.swift',root/'Sources/AutoGridDetector.swift',root/'Tests/AppearanceTests.swift']
elif args.covered_border_test:
    executable = build / 'CoveredBorderTests'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [root/'Sources'/f for f in ['BoardVision.swift','StoneGeometry.swift','AutoGridDetector.swift']] + [root/'Tests/CoveredBorderTests.swift',root/'Tests/CoveredBorderTestMain.swift']
elif args.bump_test:
    executable = build / 'BumpTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/AutoGridDetector.swift',root/'Sources/BoardRecoveryPrompt.swift',root/'Tests/BumpTests.swift']
elif args.grid_test:
    executable = build / 'AutoGridTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/AutoGridDetector.swift',root/'Tests/AutoGridTests.swift']
elif args.inspect_sample:
    executable = build / 'InspectSample'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardAppearanceDetector.swift', root/'Tests/InspectSample.swift']
elif args.camera_test:
    executable = build / 'CameraHealthTests'
    sources = [root/'Sources/CameraHealth.swift', root/'Tests/CameraHealthTests.swift']
elif args.preview:
    executable = build / 'PhysicalGoPreview'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + [p for p in sorted((root/'Sources').glob('*.swift')) if p.name != 'PhysicalGoApp.swift'] + [root/'Tests/Preview.swift']
elif args.test:
    executable = build / 'PhysicalGoTests'
    sources = shared + [root/'Sources/BoardVision.swift',root/'Sources/StoneGeometry.swift',root/'Sources/BoardOrientation.swift',root/'Sources/BoardRectifier.swift',root/'Tests/RectificationTests.swift',root/'Tests/PlacementTests.swift', root/'Tests/VisionTests.swift']
else:
    app = build / 'Physical Go.app'
    (app/'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (app/'Contents/Resources').mkdir(exist_ok=True)
    executable = app/'Contents/MacOS/PhysicalGo'
    sources = shared + [root.parent/'SGFPlayerClean/Models/SGFPlayerEngine.swift'] + sorted((root/'Sources').glob('*.swift'))
    plist = dict(CFBundleIdentifier='com.davemarvit.PhysicalGo', CFBundleName='Physical Go',
        CFBundleDisplayName='Physical Go', CFBundleExecutable='PhysicalGo', CFBundlePackageType='APPL',
        CFBundleIconFile='PhysicalGo.icns',
        CFBundleShortVersionString='0.120', CFBundleVersion='121', LSMinimumSystemVersion='14.0',
        NSHighResolutionCapable=True, NSCameraUsageDescription='Physical Go uses your camera to recognize stones on your Go board. Images are processed on this Mac.',
        NSCameraUseContinuityCameraDeviceType=True, PhysicalGoCaptureDirectory=str(root/'Captures'),
        PhysicalGoSourceHash=hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest())
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
if root/'Sources/PhysicalOnlineBoard.swift' in sources and root/'Sources/HistoricalMoveEvidence.swift' not in sources:
    sources.append(root/'Sources/HistoricalMoveEvidence.swift')
if root/'Sources/PhysicalOnlineBoard.swift' in sources and root/'Sources/PhysicalMoveTiming.swift' not in sources:
    sources.append(root/'Sources/PhysicalMoveTiming.swift')
if root/'Sources/PhysicalOnlineBoard.swift' in sources and root/'Sources/ManualBoardCorrections.swift' not in sources:
    sources.append(root/'Sources/ManualBoardCorrections.swift')
if root/'Sources/BoardVision.swift' in sources and root/'Sources/BoardAppearanceDetector.swift' not in sources:
    sources.append(root/'Sources/BoardAppearanceDetector.swift')
if root/'Sources/BoardVision.swift' in sources and root/'Sources/LightingCompensation.swift' not in sources:
    sources.append(root/'Sources/LightingCompensation.swift')
if root/'Sources/BoardRectifier.swift' in sources and root/'Sources/GridLineAspectEstimator.swift' not in sources:
    sources.append(root/'Sources/GridLineAspectEstimator.swift')
if root/'Sources/PhysicalScoring.swift' in sources:
    for name in ['Models/AIModels.swift','Models/LocalScoring.swift','Services/KataGoEngine.swift','Services/Networking/OGSConnectionController.swift']:
        sources.append(root.parent/'SGFPlayerClean'/name)
if executable.name == 'PhysicalGo':
    icon_master=root/'Resources/AppIcon/PhysicalGo.png'
    icon_file=root/'Resources/PhysicalGo.icns'
    icon_builder=root/'scripts/build_icon.py'
    if not icon_file.exists() or icon_file.stat().st_mtime < max(icon_master.stat().st_mtime,icon_builder.stat().st_mtime):
        subprocess.run(['python3',str(icon_builder)],check=True)
    shutil.copy2(icon_file,app/'Contents/Resources/PhysicalGo.icns')
    for name in ['analysis.cfg','kata1-b18.bin.gz']:
        shutil.copy2(root.parent/'SGFPlayerClean/Resources'/name,app/'Contents/Resources'/name)
    plist['PhysicalGoSourceHash']=hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
if root/'Sources/GameRecorder.swift' in sources:
    for name in ['AccidentalStoneWithdrawal.swift','BoardAdjustmentMonitor.swift','LocalClockEngine.swift','LocalGameClock.swift','LocalClockAudio.swift','DeferredMoveHistory.swift','ReviewOrderRecovery.swift']:
        if root/'Sources'/name not in sources: sources.append(root/'Sources'/name)
if root/'Sources/LocalClockAudio.swift' in sources and root/'Sources/KokoroSpeech.swift' not in sources:
    sources.append(root/'Sources/KokoroSpeech.swift')
if root/'Sources/KokoroSpeech.swift' in sources:
    sources += sorted((root/'Vendor/KokoroCoreML/Sources').rglob('*.swift'))
    subprocess.run(['python3',str(root/'scripts/prepare_kokoro.py')],check=True)
    resource_destination=app/'Contents/Resources' if executable.name=='PhysicalGo' else build
    for name in ['Kokoro','KokoroResources.bundle']:
        shutil.copytree(root/'Resources'/name,resource_destination/name,dirs_exist_ok=True)
    if executable.name=='PhysicalGo':
        if not (root/'Resources/Kokoro/audio/manifest.json').exists():
            raise SystemExit('Generate bundled countdowns first: python3 PhysicalGo/build.py --voice-assets')
        plist['PhysicalGoSourceHash']=hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
subprocess.run(['xcrun','swiftc','-swift-version','5','-D','PHYSICAL_GO','-Onone' if args.score_overlay_test or args.clock_feedback_test or args.order_recovery_test or args.layout_voice_test or args.live_play_test or args.review_queue_test or args.move_recovery_test or args.workflow_ui_test or args.stone_tracking_ui_test or args.clock_review_test or args.timing_panel_test or args.recovery_ui_test else '-O','-target',subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0', *map(str,sources), '-o',str(executable)],check=True)
if args.voice_assets:
    subprocess.run([str(executable),str(root/"Resources/Kokoro")],check=True,cwd=root.parent)
    raise SystemExit(0)
if args.score_overlay_test or args.clock_feedback_test or args.order_recovery_test or args.layout_voice_test or args.live_play_test or args.review_queue_test or args.move_recovery_test or args.workflow_ui_test or args.clock_review_test or args.unique_placement_test or args.repositioning_test or args.stone_tracking_test or args.stone_tracking_ui_test:
    subprocess.run([str(executable)],check=True,cwd=root.parent)
    raise SystemExit(0)
if args.replay_session:
    subprocess.run([str(executable),*map(lambda p:str(p.resolve()),args.replay_session),*(['--saved-observations'] if args.saved_observations else [])],check=True,cwd=root.parent)
elif args.replay_diagnostic:
    subprocess.run([str(executable),str(Path(args.replay_diagnostic[0]).resolve()),args.replay_diagnostic[1]],check=True,cwd=root.parent)
elif args.replay_recording:
    subprocess.run([str(executable),*map(lambda p:str(p.resolve()),args.replay_recording)],check=True,cwd=root.parent)
elif args.inspect_sample:
    subprocess.run([str(executable), str(args.inspect_sample.resolve())], check=True, cwd=root.parent)
elif args.stone_appearance_audit:
    subprocess.run([str(executable),str(args.stone_appearance_audit.resolve())],check=True,cwd=root.parent)
elif args.covered_border_test or args.lighting_test or args.recovery_ui_test or args.timing_panel_test or args.play_mode_test or args.move_capture_test or args.occlusion_context_test or args.covered_grid_stone_test or args.visible_grid_stone_test or args.historical_move_test or args.move_timing_test or args.correction_photo_test or args.touching_shadow_test or args.reference_feedback_test or args.stone_calibration_test or args.correction_test or args.shaded_cross_test or args.grid_aspect_test or args.view_orientation_test or args.online_test or args.crowded_white_test or args.touching_edge_test or args.centered_stone_test or args.capture_continuation_test or args.grid_ui_test or args.crowded_adjustment_test or args.stall_session_test or args.visibility_test or args.placement_confidence_test or args.morning_session_test or args.session_regression_test or args.diagnostic_test or args.stone_aspect_test or args.recorder_test or args.test or args.preview or args.camera_test or args.grid_test or args.bump_test or args.appearance_test or args.grain_test or args.shadow_test or args.shaded_cross_test or args.reference_offset_test or args.displaced_neighbors_test or args.geometry_test:
    subprocess.run([str(executable)],check=True,cwd=root.parent)
else:
    # TCC camera grants identify the signed app across updates. Ad-hoc signatures
    # use a per-build hash, so do not silently fall back to them for installed apps.
    identity = os.environ.get('PHYSICAL_GO_SIGN_IDENTITY')
    if not identity:
        listing = subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
        identities = re.findall(r'\b([0-9A-F]{40}) "([^"]+)"',listing)
        for prefix in ['Developer ID Application:', 'Apple Development:']:
            matches = [fingerprint for fingerprint,name in identities if name.startswith(prefix)]
            if len(matches) == 1:
                identity = matches[0]
                break
            if len(matches) > 1:
                raise SystemExit('Multiple signing identities found. Set PHYSICAL_GO_SIGN_IDENTITY to the intended certificate name or fingerprint.')
    if not identity:
        raise SystemExit('A code-signing certificate is required to preserve camera permission across updates. Set PHYSICAL_GO_SIGN_IDENTITY; use "-" only for an intentional ad-hoc test build.')
    if identity == '-':
        print('Warning: explicit ad-hoc build; camera permission may be requested again after updates.')
    subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--identifier','com.davemarvit.PhysicalGo',str(app)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    print(app)
