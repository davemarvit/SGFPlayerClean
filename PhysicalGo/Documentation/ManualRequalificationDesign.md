# Explicit manual requalification after a stopped calibration

Historical design origin. Observed-anchor/manual requalification was subsequently
implemented and physically entered, and later global calibration completed on the
prior setup. This document is not a live launcher or current movement authority.
Use [the checkpoint](LaserMovementCheckpoint.md) and [test plan](NextPhysicalTestPlan.md).

Architecture follow-up, 2026-11-23. This is a future design recommendation, not part of the reviewed interior pilot and not authorization to operate hardware.

The current exact-report-SHA adapters make each unusual stop reviewable, but repeatedly encode incident-specific transcripts in production acquisition paths. Keep them for the existing recorded experiments; replace this pattern incrementally with an explicit manual fresh-requalification operation. Its authority should come from newly established physical state rather than assumptions about what a previous interrupted command did.

The operation should have one typed progression:

1. Obtain exclusive device ownership, stop/reap prior workers, establish a new controller session and confirm full OFF. Preserve the prior report, source hashes, uncertain commands and fault classification as diagnostic history.
2. Read actual current motor pose and current camera identity, geometry, setup and clearance. A current pose and a visible board do not establish where the laser points.
3. Admit an initial optical acquisition separately: require a qualified current candidate with a conservative interior prediction, a demonstrably applicable known safe anchor, or operator coarse alignment when neither is available. Never infer safe relighting solely from successful OFF/reset.
4. Measure a fresh spot and qualify position correspondence. Then take two independent bounded motor probes to qualify steering. Model position agreement must not reinstate a stale local Jacobian.
5. Publish a typed capability describing the newly measured anchor, steering basis, setup identity and applicable motion policy. Downstream movement must consume that capability, rather than interpreting a collection of report flags.

Automatic retry remains a separate, narrower policy. A transport fault or unknown command history must never silently enter this manual operation. User cancellation remains final. The manual operation is explicitly requested by the operator; its fresh safety checks do not require a new software patch for each historical error string.

Retain valid fit data only under explicit setup and reference correspondence, with its original provenance. Requalify steering after torque release and repeat held-out validation before activating a candidate. Diagnostic landing observations must not enter the frozen fit or masquerade as held-out qualification.

Acceptance tests should cover a command that reached the controller before its host write timed out, stale pose and stale geometry, concurrent old workers, missing safe initial optical admission, position agreement with an invalid old Jacobian, one-axis-only probe evidence, and failures at every transition. Each failure must end in confirmed OFF or an explicit failure to confirm OFF, without automatic continuation. A successful operation must preserve historical uncertainty truthfully while deriving new movement authority solely from fresh evidence.

Implement first as a small pure admission/state module plus existing controller/camera adapters. Avoid a new parallel supervisor or broad calibration rewrite. This should reduce incident-specific code and review delay while retaining the same physical evidence requirements.
