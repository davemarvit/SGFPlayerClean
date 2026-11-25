# November 24 cross-change integration review

This is a dated architecture review for PG-14b/PG-20, not another issue register.
[IntegrationChecklist.md](IntegrationChecklist.md) owns statuses, owners,
installation and physical acceptance. [NextPhysicalTestPlan.md](NextPhysicalTestPlan.md)
owns the next attended sequence. Nothing here authorizes hardware activation.

## Reviewed source and evidence

The native basis is `0628a33` in the immutable `camera-safety-delivery` lineage
(runtime `9c516f1`); the host basis is
`2da3c29785aa7337871b299380dd3dc289437332` in `feedback-indication-stop`.
Review inspected the native guidance/frame broker, host hardware/runtime,
three-point benchmark, and mandatory paired-contract documentation. This pass
performed no build, app operation, camera acquisition, serial operation,
installation or screenshot. Later candidate commits require separate review.

The native recovery reducer owns classified transient OFF recovery; the guidance
facade authenticates receipts, identities and deadlines; the AI owner preserves
logical moves and clocks. The host runtime owns cancellation and supervision;
its optical worker cannot authorize a new generation. The hardware backend is
the only route to the serialized controller, and firmware supplies local guards.
Keep new feedback work inside these boundaries rather than duplicating them.

## Findings and combined acceptance

| Boundary | Finding at reviewed source | Evidence required from the combined candidate |
|---|---|---|
| Benchmark to gameplay | `calibration_three_point_feedback.py` reacquires actual pose/spot and adapts a three-point response; `HardwareBackend.point` still initializes travel using the older prediction model. Benchmark success is not gameplay integration. | An explicit feedback entry point/binding; tests for cold and warm actual-pose acquisition, missing/invalid anchor, setup/stream changes, and finite correction exhaustion. No fallback to an unreviewed old binding. |
| Point request across languages | Mandatory paired acceptance exports actual Swift point JSON and parses it, but its fake runtime scenario uses standby. The current receipt alone cannot validate feedback gameplay. | Actual point request through the production host runtime with fake hardware, authentic status consumed by native guidance, target replacement/cancellation and full OFF. Preserve existing standby/fault coverage. |
| Stale work and safety | `BridgeRuntime._point` generation-gates emitted feedback. Native status freshness, three-second transitions and host request/camera leases are separate limits. | Cancel during acquisition, optical work, motor wait and final hold; suppress late adequate/illumination results. Inject blocked file/image work while supervision continues; calibration overrides must not enter ordinary gameplay. |
| Light, darkness and clocks | `illuminationConfirmed` feeds first-light behavior; transition status is uncertain output. Recognition additionally requires fresh post-dark evidence and flush. | No click or accepted stone from a request/command alone; no repeated move click from corrections/retries. No dark admission from arming/transitioning. Pause/recovery preserves pending move and clock balances. |
| Holding and full OFF | Schema-2 holding retains motor power; full OFF releases it. Hand retain-only cannot cold-arm. | Feedback completion enters only eligible monitored holding; hand, lease, thermal and fault exits preserve the existing OFF/hold distinctions and fresh receipt requirements. |
| Speed changes and optical data reuse | Edge-step policy and median reuse optimize different costs. Neither proves a live speedup, fresh clearance or valid moved-board alignment. | Combined containment/trajectory tests, exact-frame identity for reuse, negative obstruction/movement controls and measurements separating step count from per-cycle duration. |
| First-fault evidence | Cleanup can produce later traffic; an image without exact pre-observation tracker state may not reproduce temporal classification. | Preserve initiating fault and source identities through OFF; distinguish exact saved checkpoint from reconstructed replay state. Diagnostics must not replace safety decisions or mask the original exception. |

The table defines review questions, not passing test results. Candidate-specific
commands, commits and remaining gaps belong in the authoritative register and
worker reports. PG-04 owns paired gameplay coverage; other issue owners retain
their specific implementation and acceptance scopes.

## Integration procedure

1. Select exact app and host commits into fresh integration worktrees. Keep the
   installed and hardware-tested source trees immutable. Inspect overlapping
   production hunks and reconcile imports, bindings and status meanings before
   compiling; isolated branch passes do not validate the combined tree.
2. Have one build owner produce native immutable receipts against that exact
   source closure. Run relevant regressions and mandatory paired acceptance
   against the reviewed host commit, including the point-path extension. Record
   failure output as well as successful receipts. A source hash does not cover
   arbitrary external resources or the Python environment.
3. Root reviews the resulting pair for installation with an exact rollback.
   Preserve games, clocks, frozen models and raw evidence. Record installed
   source/binary identity separately from documentation HEAD.
4. Only root conducts fresh attended acceptance using the authoritative plan and
   launcher authorization. Report actual target/marker/clock/hand behavior,
   latency and final OFF receipt. Offline tests cannot close physical scopes.

During parallel preparation, build and heavy-analysis slots are coordinator-owned.
Use sparse documentation checkouts where appropriate and inspect disk capacity;
resource pressure does not authorize deleting evidence or modifying frozen caches.
