# Physical Go documentation index and November 24 review

Start with [current status](IntegrationChecklist.md), [continuation handoff](NextConversationHandoff.md)
and [next attended session](NextPhysicalTestPlan.md). The [nine-page project guide](AgentGuide/README.md)
owns architecture and task routes. This review covers Physical Go and its pointer
integration; unrelated SGF Player/iPad development history is not a new product audit.

## Reading and maintenance rules

- **Current:** app 0.260/build 261, firmware v44, paired host `1ae717e`; app/driver
  stopped, moved setup unqualified, 600 ms camera expiry open. Exact provenance
  and completed versus pending validation belong in the checklist.
- **Source versus installation:** canonical repositories contain updated guides
  but older runtime code. Use the checklist's installed-source worktrees. Later
  documentation commits are not new compiled app versions or physical tests.
- **Historical:** preserve dated measurements, failed hypotheses, hashes, fixture
  provenance and stopped-run receipts. Old “current”/“next”/“running” statements
  apply only to their checkpoint and cannot authorize today's operation.
- **Design:** explicit proposals remain proposals until implementation and test
  evidence are recorded. Named stone sets, offline appearance/difference work,
  adaptive learning and a transferred calibration estimate do not activate optics.
- **Privacy/data:** advance notice before desktop capture; board evidence comes
  from actual camera images. Preserve unique games/recordings and KEEP evidence;
  pruning needs a reviewed audit, not deletion based only on size or age.

## Operational and evidence pages

| Page | How to use it |
|---|---|
| [AIPlayClockLayout.md](AIPlayClockLayout.md) | Current guide/status |
| [AmbiguousPlacementDiagnosis.md](AmbiguousPlacementDiagnosis.md) | Dated study/design/incident evidence |
| [ArchitectureReview.md](ArchitectureReview.md) | Dated study/design/incident evidence |
| [AutomaticHoldAccounting.txt](AutomaticHoldAccounting.txt) | Dated study/design/incident evidence |
| [BuildProvenance.md](BuildProvenance.md) | Current guide/status |
| [CalibrationAccuracyPolicyReview.md](CalibrationAccuracyPolicyReview.md) | Dated study/design/incident evidence |
| [CalibrationAndTiming.md](CalibrationAndTiming.md) | Current guide/status |
| [CalibrationProgressUI.md](CalibrationProgressUI.md) | Current guide/status |
| [CalibrationSpeedProposal.md](CalibrationSpeedProposal.md) | Dated study/design/incident evidence |
| [CameraFreshnessReliability.md](CameraFreshnessReliability.md) | Current guide/status |
| [CandidateHistories.txt](CandidateHistories.txt) | Dated study/design/incident evidence |
| [CaptureOnStart.txt](CaptureOnStart.txt) | Dated study/design/incident evidence |
| [DeferredCleanupDeployment.txt](DeferredCleanupDeployment.txt) | Dated study/design/incident evidence |
| [DeferredLocationsLive.txt](DeferredLocationsLive.txt) | Dated study/design/incident evidence |
| [FastTestIdleReuse.md](FastTestIdleReuse.md) | Design origin; integration status updated |
| [FreshGameConfidenceAudit.txt](FreshGameConfidenceAudit.txt) | Dated study/design/incident evidence |
| [Game85DeepAudit.txt](Game85DeepAudit.txt) | Dated study/design/incident evidence |
| [GameplayContinuityReview.md](GameplayContinuityReview.md) | Design origin; integration status updated |
| [GeometryPerformance.txt](GeometryPerformance.txt) | Dated study/design/incident evidence |
| [GuidanceRecoveryExtraction.md](GuidanceRecoveryExtraction.md) | Design origin; integration status updated |
| [IllegalMoveMarkerDesign.md](IllegalMoveMarkerDesign.md) | Design origin; integration status updated |
| [IntegratedPhysicalTestCandidate.md](IntegratedPhysicalTestCandidate.md) | Historical evidence |
| [IntegrationChecklist.md](IntegrationChecklist.md) | Current guide/status |
| [IntegrationHistoryThrough20261124.md](IntegrationHistoryThrough20261124.md) | Historical evidence |
| [LaptopParallaxIncident-2026-11-16.md](LaptopParallaxIncident-2026-11-16.md) | Dated study/design/incident evidence |
| [LaserCaptureCenteringTests.md](LaserCaptureCenteringTests.md) | Dated study/design/incident evidence |
| [LaserMovementCheckpoint.md](LaserMovementCheckpoint.md) | Current guide/status |
| [LaserMovementHistory20261123.md](LaserMovementHistory20261123.md) | Historical evidence |
| [LaserStandbyThermalDesign.md](LaserStandbyThermalDesign.md) | Design origin; integration status updated |
| [LatencyDiagnostics.md](LatencyDiagnostics.md) | Current guide/status |
| [LivePositionIssues.md](LivePositionIssues.md) | Historical evidence |
| [LocalQualityEvaluation.txt](LocalQualityEvaluation.txt) | Dated study/design/incident evidence |
| [ManualRequalificationDesign.md](ManualRequalificationDesign.md) | Dated study/design/incident evidence |
| [MarkerScenarioReview.md](MarkerScenarioReview.md) | Dated study/design/incident evidence |
| [NextConversationHandoff.md](NextConversationHandoff.md) | Current guide/status |
| [NextPhysicalTestPlan.md](NextPhysicalTestPlan.md) | Current guide/status |
| [ObservationReplay.txt](ObservationReplay.txt) | Dated study/design/incident evidence |
| [OccludedCleanupExperiment.txt](OccludedCleanupExperiment.txt) | Dated study/design/incident evidence |
| [OccupiedBoardTiming.md](OccupiedBoardTiming.md) | Dated study/design/incident evidence |
| [OfflineHandParallax-2026-11-16.md](OfflineHandParallax-2026-11-16.md) | Dated study/design/incident evidence |
| [OvernightSoftwareResults.md](OvernightSoftwareResults.md) | Historical evidence |
| [PairedContractAcceptance.md](PairedContractAcceptance.md) | Current guide/status |
| [PlacementCompetitionExperiment.txt](PlacementCompetitionExperiment.txt) | Dated study/design/incident evidence |
| [PracticeTestPositions.md](PracticeTestPositions.md) | Design origin; integration status updated |
| [PreHandRecognitionExperiment.txt](PreHandRecognitionExperiment.txt) | Dated study/design/incident evidence |
| [RecognitionParameterSearch.txt](RecognitionParameterSearch.txt) | Dated study/design/incident evidence |
| [ReferencePreparation.txt](ReferencePreparation.txt) | Dated study/design/incident evidence |
| [StoneConfidenceExperiment.txt](StoneConfidenceExperiment.txt) | Dated study/design/incident evidence |
| [StonePlacementSessionPlan.md](StonePlacementSessionPlan.md) | Historical evidence |
| [StoneSetProfiles.md](StoneSetProfiles.md) | Current guide/status |
| [TurnLocationExperiment.txt](TurnLocationExperiment.txt) | Dated study/design/incident evidence |
| [UnavailableShadowExperiment.txt](UnavailableShadowExperiment.txt) | Dated study/design/incident evidence |
| [UnavailableShadowValidation85.txt](UnavailableShadowValidation85.txt) | Dated study/design/incident evidence |
| [UnchangedBaselineExperiment.txt](UnchangedBaselineExperiment.txt) | Dated study/design/incident evidence |
| [WhiteTurnAppearance.txt](WhiteTurnAppearance.txt) | Dated study/design/incident evidence |
| [laser-bridge.md](laser-bridge.md) | Design origin; integration status updated |

## Other documentation groups

| Group | Review disposition |
|---|---|
| `AgentGuide/*.md` | All nine pages reconciled with installed behavior, current sources, privacy, timing and remaining physical checks. |
| `PhysicalGo/README.md`, root `README.md` | Current entry points added; dated release histories preserved. |
| `Experiments/EphemeralIPC` | Installation status updated; benchmark no-speedup result and original run findings retained. |
| `Experiments/IllegalMoveMarkers` | Isolated precursor distinguished from installed promoted screen diagnostic; no illegal-laser capability. |
| `Experiments/IntersectionAppearance` | Offline-only contract remains; no classifier/clearance promotion. |
| `Tests/Fixtures/*/README.*` | Historical inputs/provenance retained, not rewritten to claim new validation. |
| `Tools/HandTimingLab/README.md` | Separate development camera tool; not the app broker and not the source for an active calibration. |
| Pointer assembly/firmware guides | See [pointer documentation status](</Users/Dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Documentation status.md>); current v44/0.260 status replaces old v36 pilot instructions. |
| Frozen worktrees, build manifests, source snapshots and retained run reports | Deliberately unchanged. Mutating them would invalidate source hashes and launcher pins. |

The reconciliation checks local links and test-flag/source references. It does
not revalidate mechanical dimensions, electrical measurements, external product
links, archived fixture results or physical hardware. No screenshots, device
commands, audio tests or runtime source changes were part of this documentation pass.
