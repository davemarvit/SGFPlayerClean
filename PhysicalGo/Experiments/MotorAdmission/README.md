# PG37 motor admission extraction — November 25, 2026

Based on installed native `1f6fb91cac57616791d47c2fea4cc4eca0426a28`.
This is an offline architecture candidate, not an installed or physical repair.

## Retained failure

`retained-evidence.json` pins the four original artifacts without copying or
changing saved games and recordings. The final request/status share schema2,
producer, revision50, game, camera context and stream epoch. The request remains
OFF with reason `explicit_show_again`; the status is real full OFF with released
motors and bus. Its updated timestamp is31.894ms after the request. Recognition
continues in placing phase with only missing D4 and159seconds of stable evidence.

These files do not contain native readiness, closing, standby-fault, setup or
admission-deadline state. They cannot establish which admission conjunct held
OFF, or explain every earlier transition. In particular, the adjacent ordering
case in which an old timer is checked before consuming OFF does not prove the
persistent loop's cause: consumed full OFF resets the timer. No exact-cause or
live recovery claim is made.

## Scope and preserved authority

`PhysicalMotorAdmission` is a pure event owner for possible motor power, cold
admission and continuous handoff deadlines. The facade authenticates receipt
scope/freshness and selects events; it still owns leases, fault classification,
request publication and game callbacks. No policy limit or event ordering moves.

| Event | Existing semantics retained |
|---|---|
| Motor request | Mark possible power; start12s cold deadline only if no possible motor session |
| Authenticated arming | Start a cold deadline only if none exists |
| Healthy active receipt | End cold admission timing; retain possible power |
| Authenticated transition | Start continuous3s handoff once; revisions cannot extend it |
| Authenticated nontransition | Clear handoff only |
| Play session change | Clear handoff only; do not invent full OFF or reset cold timing |
| Confirmed full OFF | Clear possible power and both deadlines |
| Disabled recognition/shutdown release bookkeeping | Clear possible power only, preserving old behavior |

The typed admission blocker reproduces the original ten-condition schema2
conjunction, in its original order. It exposes the first blocked gate; all other
relevant flags remain in the optional change-only `motor_admission` latency trace.
Wire request reasons and game/hardware decisions are unchanged. Tracing remains
opt-in; a historical request is not retroactively assigned a blocker.

## Verification

`python3 PhysicalGo/build.py --motor-admission-test --debug-tests` passes:
4096 exhaustive four-event sequences against frozen pre-extraction assignments,
1024 admission-gate combinations, and deadline/reset boundary cases.

Real-facade sequence checks are added to `PhysicalLaserStandbyTests`: schema2
OFF, fresh camera recovery, foreign target, changed epoch, explicit Retry and
fresh handshake. Existing standby/continuity suites additionally cover stale
receipts, timeout ordering, pause/Resume, hard faults and current full-OFF scope.
Combined native and paired acceptance remain root-owned before installation.

This candidate does not consolidate all guidance flags or promise recovery from
an unexplained persistent loop. Those are later, evidence-led increments.
