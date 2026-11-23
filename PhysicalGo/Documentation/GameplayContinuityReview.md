# Gameplay continuity review

Reviewed November 22, 2026, against app source commit `50f28df` and the installed
0.253/build 254 checkpoint. This is a source/test audit, not a physical gameplay
pass. Read the current [checklist](IntegrationChecklist.md) and shared handoffs;
the incoming laser-agent reply is historical, not a current active dependency.
Root reports hardware OFF after the latest commissioning timing stop. A private
150ms commissioning poll limit is not the production gameplay image-age limit
of 600ms. Neither limit should be relaxed to make a test succeed.

Dave's priority is reliable play; longer preparation is acceptable. The main
continuity gap in 0.253 is that stopping the laser does **not** automatically
pause the local AI game. The application preserves its accepted history, but
elapsed practice time can continue accumulating during a hard outage. These are
elapsed practice clocks, not a timed-game forfeiture mechanism.

## Confirmed behavior

| Event | Current behavior and evidence |
|---|---|
| Hard laser/controller fault | Guidance requests OFF and latches recovery. It does not call AI pause or cancel the AI task. [Guidance fault handling](../Sources/PhysicalLaserGuidance.swift#L410), [AI cancellation](../Sources/PhysicalAI.swift#L258). |
| AI reply arrives during outage | If the AI remains in `thinking`, its task can commit a legal reply, persist it as pending placement, and switch elapsed-clock ownership. This is valid engine history, not a phantom camera move, but game progress continues while indication is unavailable. [Task completion](../Sources/PhysicalAI.swift#L472), [commit](../Sources/PhysicalAI.swift#L443). |
| Unexpected camera disconnect | `handleCameraStatus` invalidates stream/evidence and suspends the local recorder; it does not pause the separate AI controller. Explicit camera Stop and Freeze **do** pause AI. [Status](../Sources/ExperimentModel.swift#L894), [Stop/Freeze](../Sources/ExperimentModel.swift#L1033). |
| Hand, unclear stone, marginal alignment, illuminated/buffered frame | Recognition waits and resets witnesses. These are normal evidence gates, not accepted moves or automatic clock transitions. [Recognition admission](../Sources/PhysicalAI.swift#L336), [model gates](../Sources/ExperimentModel.swift#L1486). |
| Confirmed alignment recovery | The model declares `alignmentNeedsRecovery`, clears verified frame state and suspends recorder vision, but still does not pause AI. [Recovery entry](../Sources/ExperimentModel.swift#L1561). |
| Explicit AI Pause | Cancels/generation-fences the pending AI task, revokes the laser session, charges elapsed time once, clears its anchor, and atomically saves the same game. Pending placement and persisted prisoner context remain. [Pause/save](../Sources/PhysicalAI.swift#L181), [pause](../Sources/PhysicalAI.swift#L212). |
| Restore and Resume | Saved games load paused with no downtime charge. Resume verifies the physical position; however a pending AI placement resumes its clock immediately, before board verification. Hard-fault recovery must not blindly invoke Resume while the controller is still unavailable. [Load](../Sources/PhysicalAI.swift#L147), [resume](../Sources/PhysicalAI.swift#L217). |
| Capture cleanup | Single captures retain the next player's elapsed clock; captures of two or more pause it until complete board confirmation. Partial removals and their identity persist separately. A hardware pause must not erase that policy. [Commit/advance](../Sources/PhysicalAI.swift#L450), [capture tests](../Tests/PhysicalCaptureControllerTests.swift#L44). |
| Audible arrival cue | Positive hardware illumination announces an ordinary move once per guidance-object lifetime. Captures/centering and repeated feedback are silent. Pause/retry in the same app is tested; the cue ledger is in memory, so relaunch-level exactly-once behavior is not established. [Cue ledger](../Sources/PhysicalLaserGuidance.swift#L515), [tests](../Tests/PhysicalAILaserTests.swift#L395). |

Accepted game state has substantial protection: `current.json` is the atomic
source of truth, SGF is derived, saved histories are legally replayed on load,
and fresh dark, hand-clear, stable board evidence is required before physical
acceptance. Existing tests cover illuminated false positives, duplicate/stale
receipts, combined placement/reply and partial prisoners. A full OFF receipt can
permit valid recognition even while laser retry remains latched; therefore
continuing with screen guidance is currently possible without a dedicated
explicit fallback choice. [Save/load](../Sources/PhysicalAI.swift#L147),
[recognition/commit](../Sources/PhysicalAI.swift#L308).

## Minimal local-AI change authorized after this audit

Add a typed, revision-bound hard-guidance-fault notification. Only a current,
matching, enabled hardware-guidance fault belonging to the active AI game may
invoke an idempotent AI suspension through the existing pause/save path. Publish
OFF before notifying the AI; avoid callback recursion through pause's guidance
updates. Cancel and generation-fence thinking work before it can commit a late
reply. Preserve session identity, accepted moves and decision timestamps,
pending placement, prisoner ledger, side to play and charged elapsed balances.
Do not implement this by treating every suppressed target as a failure.

Ordinary hand waiting, acquiring/arming, normal holding/cooling, uncertain board
evidence and classified short camera/lease recovery must retain their existing
behavior. Ignore disabled bridges, stale/unrelated producers or revisions, and
old faults from another game. A new target or game must not silently clear a
controller hard latch. Explicit recovery retains full OFF, reset-required and
fresh calibration/camera checks; it never sends an automatic controller reset.
The game must remain paused until explicit Resume. A screen-only continuation,
if offered, must be explicit and still require valid camera evidence.

This change is authorized for implementation, but was **not present in 0.253**
when the audit was written. Subsequent implementation/test results belong in the
checklist and the addendum below; no automatic pause is claimed here yet.

## Separate camera proposal

Connect explicit stream failure and confirmed alignment-recovery entry to local
AI suspension, using their existing model events. Do not classify ordinary hand
obstruction or one unclear/marginal frame as a fatal camera failure. A silent
stream stall while the camera still reports live needs its own reviewed health
policy/test; do not invent a new timeout or permit older images. Keep camera
recovery separate from laser reset, and preserve stones/game while diagnosing.
No camera-continuity source change is part of this audit.

## Targeted regression gaps

| Scenario | Required proof |
|---|---|
| Current hard fault during human turn, thinking, pending AI placement | One pause/save, no subsequent elapsed charge, same accepted history/decision timestamp; late asynchronous engine result cannot commit. |
| Single and multiple captures, including partial/out-of-order removal | Persist prisoner identity/removal ledger and pending placement; do not resume a multiple-capture clock or convert a prisoner into a human reply. |
| Repeated fault, old revision, old game, other producer, stale status, disabled bridge | Only the current authorized fault suspends; duplicates cannot recharge clocks, churn revisions or rewrite history. |
| Hand, brief camera/lease recovery, arming, holding/cooling | No automatic game pause, no move acceptance/cue caused by acknowledgements. |
| Hardware reset, fresh OFF, explicit retry and Resume | Reset cannot be simulated by Retry; neither receipt nor healthy heartbeat automatically resumes the game. Revalidate the pending physical stage without replacing the saved game. |
| Save/relaunch after automatic interruption | Restores paused game with exact charged balances and retained pending placement/prisoners; no downtime charge. Decide/test whether arrival-cue deduplication must persist across relaunch. |
| Camera disconnect versus ordinary unclear frame | Disconnect/confirmed recovery suspends according to a separately approved policy; ordinary evidence waiting stays conservative without premature pause or stale acceptance. |

Existing passing standby tests explicitly prove that **normal** holding/cooling
acknowledgements do not change game records or clocks, then call `ai.pause()`
manually; they do not cover the new automatic-fault requirement.
[Current coverage](../Tests/PhysicalLaserStandbyTests.swift#L225).
Existing lifecycle tests prove manual pause/restart clock preservation and
same-process cue deduplication. No physical gameplay fault/recovery sequence has
yet been validated on the moved setup.

## Online boundary

Current native laser camera publication and authoritative target production are
AI-only; online laser play remains unimplemented. Online board state treats the
server turn as authoritative, and local correction pauses only local evidence/
dispatch. Do not claim a local UI pause freezes an online opponent's server clock.
Future online failure handling must stop unsafe indication/submission, retain
server identity/revision, visibly report that server time may continue, and
reconcile with fresh server state before resuming physical synchronization.
[Online authority](../Sources/PhysicalOnlineBoard.swift#L429),
[local correction](../Sources/PhysicalOnlineBoard.swift#L232),
[current integration scope](IntegrationChecklist.md).

## Implementation addendum — November 23, candidate for 0.254

Source now adds the local-AI suspension boundary and
[real-controller continuity regression suite](../Tests/PhysicalAIGuidanceContinuityTests.swift).
Independent read-only review found no remaining source blocker for this bounded
change. The actual full-app regression executable passed **133 baseline checks**, including
late AI replies, partial prisoners, persisted clocks, strict fault identity, and
manual camera-only continuation after possible illumination. No installation or
physical fault/recovery validation is claimed. A second run consumed 52 actual
`BridgeRuntime` publisher fixtures through the real native decoder/controller and
passed **290 total checks**, covering typed hard/transient results before and after
confirmed OFF. Host provenance will be refreshed at its final source freeze.

- A fresh, current, hardware `controller_fault`, `laser_transport_fault`,
  `laser_setup_fault`, `laser_optical_fault`, `laser_operation_fault`, or a scoped native
  thermal/motor/protocol/admission hard failure, pauses and saves the active local
  AI game. OFF publication precedes the synchronous callback; the callback freezes
  elapsed time at detection and marks the game paused before cancellation/IO.
- Persisted interruption metadata protects restart and explicit Resume. A separate
  durable recheck reason survives camera-only play, repeated relaunch and new games;
  healthy OFF plus explicit native recheck clears it at the next save. Accepted
  moves, AI receipt timestamps, pending placement and prisoner-removal context are
  preserved. Reentrant recognition is generation-fenced after guidance calls.
- Hand waiting, normal status updates, stale/unrelated/disabled receipts, and
  classified camera/lease transients do not automatically pause. **Unclassified
  host optical faults also do not automatically pause:** current host exceptions
  can represent ordinary hand/alignment races. Actual host-publisher fixtures verify the explicit
  reviewed hard codes above and their transient counterparts. Final aggregate
  regression, optimized build and installation remain root-owned checkpoints.
  Untyped future exceptions remain non-pausing.
- Explicit camera-only fallback asks the user to switch physical laser power OFF.
  It keeps the game paused until genuinely newer, clear, presentation-timestamped
  camera frames pass the existing 0.3-second optical flush. This is a separate
  user-confirmed dark boundary, never a fabricated driver OFF acknowledgement.
  Callback-only timestamps cannot satisfy this manual path. A new camera/game
  scope earns a new barrier; enabling guidance revokes the manual override.
- Hardware faults/recheck requirements survive camera-only play and block both
  schema-1 pointing and schema-2 admission on re-enable. OFF renewal remains in
  force while controller power is unconfirmed. No reset command is added.

Camera-disconnect/confirmed-alignment auto-pause and process-restart cue-ledger
persistence remain proposals, not changes in this candidate.

## Transient recovery validation — November 23

The final real-app continuity executable passed **492 checks** using 68 actual
host publisher status fixtures and four recovery chains. Each chain exercises
schema-1 point/targetless OFF and schema-2 point/standby. The earlier targeted
batch also passed legacy laser (278), standby (225), and capture-laser (47)
checks; those three suites preceded the final narrow target-verifier and explicit
Pause fixes. No installation or physical validation is claimed here.

Classified hand, camera-evidence, frame-expiry and lease-expiry interruptions now
retain scoped recovery state while requesting a new OFF revision. Recovery needs
its matching healthy full-OFF receipt and three clear, genuinely new camera
frames beyond the optical flush and driver watermark. Old rejected-revision
receipts cannot restart the revision sequence or authorize recovery. A delayed
receipt and a hand during the wait retain the recovery context without accepting
stale evidence. Unknown light in a fault receipt remains optical contamination;
it does not by itself invent a missing-thermal hard fault during bootstrap.

A targetful recovery keeps that OFF revision until the purpose-specific target
verifier confirms the current frame, then requests the point directly. A new AI
decision during targetless recovery revokes the previous evidence and obtains
its own OFF receipt. Explicit Pause discards transient proof, retains the saved
move/placement and all hard latches, and uses ordinary new admission on Resume.
Wrong game, camera, stream or setup cannot clear recovery. Controller faults
still require explicit recovery; observed stones remain optically suppressed,
with targetless dark holding permitted by the separate motor policy.

Independent source review passed. Final log:
`work/ai-laser-integration/fresh-board-20261122-133741/gameplay-holding-validation/transient-recovery-final-shared.log`
in the shared workspace. Shared regression runtime: `5e6f0cdb0a9a`.

Final source SHA-256:

- `PhysicalLaserGuidance.swift`: `6a86661f3a066c0ca175714fbddbe723d5921765c3ad8efa11fec07878e804fb`
- `PhysicalAI.swift`: `4009c2d35dd8b9d60b13afd778cec1c47db105f6d78fbd009284ef8d6d1797e7`
- `PhysicalAIGuidanceContinuityTests.swift`: `9a4706611542e74cebdbec3067d340bec3180e1376d5e15c376be59daa3ac22b`
