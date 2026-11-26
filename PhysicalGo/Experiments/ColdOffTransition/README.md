# PG37 cold OFF transition — offline candidate, November25,2026

Base: installed native `3fe6290d0ed8612b2aa852b7bb6a8b218a53c7cd`
(0.266), host release `2f8c4daed12389f1c96bcd930b893ed9bf3bd580-app0266`.
No app, camera, controller or installation operation is part of this work.

## Evidence and reproduced defect

`live-trace-summary.json` pins and extracts the relevant native events from
`work/attended-0266-1795627659791165000`. Initial schema2 revision8 waited for
full OFF with no setup; the native reader then observed `transitioning` with
`illuminationConfirmed=false` and151.554ms status age. It latched
`standby_context_changed`69µs later. Matching full OFF subsequently supplied the
setup, but could not clear that latch. Same-scope Retry repeated this at revision11
with130.113ms status age. All requests stayed OFF; no aiming worker began.

The200ms external monitor sampled OFF and missed the complete transitional
status. Its raw live payload is **not** recovered or claimed as a fixture. Native
trace state and admission bookkeeping are retained. `generate_fixture.py` uses
the installed production Request parser, LeaseGate and BridgeRuntime publisher
with a fake OFF command sink to independently produce the missing conversation:
schema1 OFF → schema2 replacement OFF → uncertain transition → confirmed full OFF.
It launches no threads or hardware backend; activation of the OFF request rejects.

Installed native code required an already adopted setup to recognize every
transition. Cold negotiation has no adopted setup until full OFF, so the generated
valid transition reproduces the false latch. The exact installed-source regression
runner fails at “Actual host cold OFF transition must not latch
standby_context_changed.”

The later `Errno6`/“Device not configured” belongs to the user's reported departure
and equipment disconnection. It is not attributed to an unexplained controller
failure, and this task obtains no final physical OFF acknowledgement.

## Narrow change

During a cold OFF negotiation only, recognize transition liveness when the current
request is OFF, readiness is false, no motor session is outstanding, no setup has
been adopted, and the status matches the current session (including a nullable
closing session), camera context and stream epoch, with the expected capability
and a nonempty offered setup. The caller still enforces producer, revision,
schema, hardware mode and status freshness.

This exception does not store the offered setup, grant standby/motion, establish
darkness, or report illumination. Only subsequent genuine full OFF adopts setup.
An already known setup must still match exactly. Malformed optical claims retain
their latches. The existing3s transition and12s cold-admission deadlines remain
unchanged. No recognition, target, game, clock, lease or host runtime code changes.

## Reproduction

Generate the small fixtures using the installed host source, without device access:

```sh
python3 -B PhysicalGo/Experiments/ColdOffTransition/generate_fixture.py \
  --host-root '/Users/dave/Library/Application Support/Physical Go/LaserDriver/2f8c4daed12389f1c96bcd930b893ed9bf3bd580-app0266' \
  --output PhysicalGo/Tests/Fixtures/ColdOffTransition
```

`provenance.json` records source SHA256s and the two fake OFF writes. The native
suite consumes the actual publisher outputs, rebinding only test identity/time
and explicitly declared negative-control mutations.

Native regression flags are `--cold-off-transition-test --laser-standby-test
--guidance-continuity-test --debug-tests`. Verification here uses the existing
`shared_regressions.compile_suite` API directly to avoid unrelated model/resource
preparation; no app entrypoint or device enumeration is run.

Cold-transition cases cover current repeated transitions, no revision churn,
no motion/darkness/click authority, delayed setup adoption, known-setup mismatch,
foreign producer/revision/session/context/epoch, stale receipt, simulation,
missing capability/setup, malformed optical claims, the3s bound, nullable cold
cancellation and explicit Retry. Existing suites cover the12s bound and broader
holding/fault/pause/Resume behavior. Physical acceptance remains pending.

## Offline result

The exact installed-source baseline fails the new host-produced transition test.
The candidate passes74 cold-OFF sequence checks,387 existing monitored-standby
checks and263 guidance-continuity checks:724 total. `validation.json` pins source,
runtime and log identities. Independent source review found no blocker; final
combined integration/paired acceptance and attended validation remain root-owned.
This is a fix for the reproduced cold-transition latch, not proof that all other
PG37 recovery episodes are resolved.
