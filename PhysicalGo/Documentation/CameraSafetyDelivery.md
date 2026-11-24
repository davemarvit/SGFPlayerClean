# Independent camera safety delivery and offline follow-up

November 24, 2026. Implemented on app `codex/camera-safety-delivery` at `9c516f1`
and host branch of the same name at `04b76c7`. See the
[current checklist](IntegrationChecklist.md) for installation status. No physical
test or new calibration was performed by this work.

## Delivery change

The broker now publishes a small `frames/safety.json` independently of PNG
compression, pixel writes and image pruning. It contains the checked frame's
original timestamps/identity, camera/context, geometry and hand/alignment verdict.
It contains no image locator. The separate `latest.json`/PNG pair remains the
only optical frame source; fresh clearance never makes older pixels acceptable.

The small writer has one active write and one replaceable pending observation.
Same-epoch IDs cannot go backward or mutate an already offered frame. Stream reset
discards pending work; readers reject any old-epoch in-flight completion. Failures
leave prior evidence with its original expiration, never renewed timestamps.

The new host accepts an old publisher when the safety channel is initially absent.
Once that channel is present, stale, malformed, unknown, missing or wrong-scope
metadata fails closed rather than falling back to an older clear image. An explicit
rollback requires stopped owners and archival of the stale safety file before a
fresh legacy session; deleting it during active play is not a recovery shortcut.

The 600 ms camera age, 750 ms status age, lease, hand, optical and thermal guards
are unchanged. The existing same-frame analysis callback still passes through the
main thread, and filesystem/scheduling delays can affect both queues. This removes
a specific dependency; it does **not** establish that all 600 ms faults are solved.

Sources: [native broker](/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery/PhysicalGo/Sources/PhysicalLaserFrameBroker.swift),
[native fault-injection suite](/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery/PhysicalGo/Tests/PhysicalCameraSafetyTests.swift),
[host protocol](</Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/camera-safety-delivery/Firmware/Camera safety delivery.md>).

## Verification

- Five integrated suites passed: camera safety (initial 18 checks), broker 49,
  monitored standby 345, guidance continuity 184 and AI laser lifecycle 283.
- The final camera-safety suite passed **26 checks**, including encoding/pixel
  stalls longer than 600 ms, fresh obstruction delivery during the stall,
  latest-only coalescing of 100 pending offers, epoch reset, write failure,
  immutable duplicate rejection and four actual Swift message exports.
- **15 host tests passed with all Swift-export cases enabled**, covering
  legacy compatibility, malformed/oversized/missing/mutated/reversed/future/stale
  evidence and no reuse of old pixels. Host gameplay 134 and bridge 149 tests passed.
  The bridge suite's local optical fixtures were linked read-only for the test;
  the temporary link was removed.
- Mandatory fresh app → host → app acceptance passed, including 68 generated host
  statuses and native recovery consumers. This is a separate wire/recovery check,
  not a live controller or optical test.

Artifacts and exact receipts:
[camera-safety-delivery-20261124](</Users/Dave/Documents/SGF PLayer/work/camera-safety-delivery-20261124>).
`swift-fixture-provenance.json` records literal message hashes. The release/install
receipt and actual physical gaps belong in the checklist, not inferred from test counts.

## Regional change detection follow-up

The frozen [offline prototype](</Users/Dave/SGFPlayerClean-worktrees/frame-change-gate/PhysicalGo/Experiments/FrameChangeGate/README.md>)
was evaluated against the 20 retained full-resolution pre-movement empty-board
images. A fixed first-frame anchor gave 19 comparisons, requesting **4.26 of 361
regions on average**. Sampling/descriptor/comparison took median **7.39 ms**, p95
**8.44 ms**, excluding decoding. This ran alongside software building; it is not a
controlled native speed benchmark. The three later misaligned images were all
ineligible and requested full work; their old grid was not treated as validated.

This is evidence about empty-board noise and scope rejection, not held-out stone,
subtle movement, shadow or hand sensitivity. The prototype is still outside the
application and grants no occupancy/clearance/motion authority. Current hand
detection needs fresh White-stone geometry, so skipping recognition requires an
explicit dependency design and broader validation. No runtime optimization was
promoted from the favorable empty-board counts.

Reproduce the read-only audit with
[audit_recorded_frame_changes.py](/Users/Dave/SGFPlayerClean-worktrees/camera-safety-delivery/PhysicalGo/Tools/audit_recorded_frame_changes.py), passing
`--prototype` for the frozen `change_gate.py`, `--recording` for one saved PNG/JSON
directory and `--output` for a new report. Reports retain image/metadata/prototype
hashes. Inputs are never edited and an existing report is never overwritten.
