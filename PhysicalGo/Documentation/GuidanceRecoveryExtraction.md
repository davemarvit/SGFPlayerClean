# Scoped guidance recovery extraction experiment

**Current status, November 24:** the reducer described here was integrated into
the installed app lineage and remains in 0.260. The isolated experiment narrative
below records its origin, not the current installation. Later transition/link-loss
changes are recorded in [the checklist](IntegrationChecklist.md).

This isolated `codex/overnight-guidance-reducer` experiment starts from app commit
`c39e7e0`. It changes structure, not admission policy. The primary repository,
installed application, saved game and hardware are untouched.

`PhysicalGuidanceRecovery` now solely owns a classified transient's immutable
session/camera/epoch/setup scope, operation identity, OFF boundary, camera witness
streak and target-specific completion. `PhysicalLaserGuidance` retains the public
API, wire types, receipt authentication, thermal and hard-fault guards, legacy hand
recovery, publication, display and synchronous game callbacks. There is no second
copy of the transient record in the facade.

| Event | Reducer decision | Facade responsibility |
|---|---|---|
| Authenticated classified transient | Begin recovery; request a new OFF revision | Validate producer/revision/status and retain hard-fault boundaries |
| Same-game target replacement | Revoke OFF boundary/witnesses; request new OFF | Provide intrinsic target ownership and publish the revision |
| Scope/target mismatch | Discard recovery; report scope change | Preserve the existing suppression/standby latch policy |
| Missing/stale receipt, hand or inadmissible new frame | Reset witnesses; keep recovery pending | Authenticate full OFF and optical flush/watermark evidence |
| Three new clear frames spanning at least 450 ms | Complete targetless recovery; hold targetful recovery OFF | Apply recovered reason; never publish standby between target proof and verifier |
| Purpose-specific verifier on exact final frame | Complete targetful recovery | Set target evidence and issue point directly |
| Pause, disable, explicit recheck or hard latch | Cancel transient proof | Retain hard/native/controller latches and existing game semantics |

The existing 500 ms freshness, 600 ms maximum witness gap, three-frame minimum,
450 ms witness span, exact-frame tolerance, optical flush and wire lease limits
are unchanged. A changed OFF time or watermark resets witnesses before the
shortcut for a duplicate verdict. A fresh image publication before an already
counted analysis verdict cannot erase the streak. The pure reducer receives
immutable values and returns effects; it performs no IO, timers or callbacks.

## Verification

- `python3 PhysicalGo/build.py --guidance-reducer-test`: **16,825 checks passed**.
  Includes a frozen test-only baseline policy oracle, explicit admission/time
  boundaries, and 200 deterministic ordered-event traces compared after every
  event. The oracle is an adaptation of the baseline methods, not a full baseline
  app execution; real-controller regression remains a separate required gate.
- Independent `PhysicalGuidanceRecoveryReviewTests`: **105 checks passed**, built
  with only the new source and independent test file using `swiftc`.
- Existing actual-host continuity fixture cases are retained; three additional
  foreign target identity cases cover source/session/board-size ownership.
- Parse and whitespace checks pass. Independent source/adapter review is clear.
- The isolated shared debug batch passed **5/5 suites**: continuity **495**
  (all original 492 checks plus three foreign-target cases), legacy laser **278**,
  standby **225**, capture-laser **47**, and pure reducer **16,825**. The native
  continuity suite consumed all 68 actual host status fixtures and four complete
  recovery chains. Shared runtime: `57fcc05251e1`.
- Aggregate log: `PhysicalGo/.build/overnight-guidance/aggregate.log` in this
  worktree; independent log and frozen source hashes are alongside it. All app
  suites use injected temporary game/bridge directories. No physical validation,
  installation or primary-branch adoption is implied.

The review caught a draft mapping error where a proposed target borrowed the
active game's owner; the adapter now supplies intrinsic target identity and the
reducer compares it to the existing authority. Absent owners cannot authorize a
new target. Eager optical-evidence evaluation is explicitly gated by `enabled`
so the helper's disabled-only uncertainty cleanup remains unreachable here.

## Deliberate limits

Older hand recovery and all unrelated native guidance flags remain unchanged.
This extraction does not solve transport IO scheduling or redesign the complete
guidance controller. It supplies a small testable boundary for the most recently
repaired transient lifecycle, suitable for separate review and adoption.

## Reproduction and reviewed snapshot

From this worktree root:

```sh
python3 PhysicalGo/build.py --guidance-reducer-test
swiftc PhysicalGo/Sources/PhysicalGuidanceRecovery.swift PhysicalGo/Tests/PhysicalGuidanceRecoveryReviewTests.swift -o PhysicalGo/.build/PhysicalGuidanceRecoveryReviewTests
PhysicalGo/.build/PhysicalGuidanceRecoveryReviewTests
PHYSICAL_GO_HOST_FAULT_STATUS_FIXTURES='/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer/Firmware/Host tests/Fixtures/GameplayContract/FaultStatus' python3 PhysicalGo/build.py --guidance-continuity-test --ai-laser-test --laser-standby-test --capture-laser-test --guidance-reducer-test --debug-tests
```

The optional host-fixture environment variable is **required for this acceptance
claim**; a run without it does not reproduce the 495 continuity checks. The
independent reviewer cleared the source/adapter after the intrinsic-owner fix.

- Reducer SHA-256: `47796561265cbefb4c4e782f3967e3756b9c2c16f9d2fbc7e86fc1dbbe3c49e7`
- Facade SHA-256: `6cb9a68c64f4a66136cce4d91943be738047a0f51ef56646c285dd2c05a6a948`

The facade loses its transient record and witness algorithm (31 net lines fewer).
The new pure source adds explicit value types, events and effects rather than a
parallel state copy. Total source grows modestly; the simplification is the single
owner and independently executable policy boundary, not a claim of fewer total
lines or a complete guidance-controller redesign.
