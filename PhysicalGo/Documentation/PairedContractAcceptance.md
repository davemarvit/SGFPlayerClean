# Mandatory offline app/host contract acceptance

`Tools/paired_contract_acceptance.py` is a standalone acceptance command for
[architecture finding2](ArchitectureReview.md). Every stage is required. Missing
fixture exports, hashes, coverage, native build provenance, an unsuccessful
subprocess or an optional native fixture block that did not run makes the command
fail. A failed/partial run never produces a successful acceptance receipt.

This integrated command changes test artifacts only. It does not build, install, launch the
application, access a camera/serial port, activate a calibration or contact a
network service. Host code is read-only. Bytecode is disabled; generated requests,
statuses, native artifacts, logs and `acceptance.json` go into a new system temp
directory that is printed even on failure. Retain that directory as review
evidence. A passing result verifies the supplied source/runner pair, not the
installed application's physical behavior. The latest accepted 0.260/host pair
and receipts are recorded in [the checklist](IntegrationChecklist.md).

## Fresh build receipts are the normal entry point

Have the single build owner build the existing `laser-standby-test` and
`guidance-continuity-test` suites against the exact desired source tree, using the
immutable shared builder. This command consumes its format2 runner/runtime
receipts; it is not a second build system and cannot generate a fresh build
attestation itself.

```sh
python3 -B PhysicalGo/Tools/paired_contract_acceptance.py \
  --app-root '/path/to/exact/app-worktree' \
  --host-root '/path/to/reviewed/laser-worktree' \
  --expected-host-commit FULL_REVIEWED_HOST_COMMIT \
  --standby-build-pointer '/path/to/PhysicalLaserStandbyTests-DIGEST.build.json' \
  --continuity-build-pointer '/path/to/PhysicalAIGuidanceContinuityTests-DIGEST.build.json'
```

Both pointers must identify the same immutable runtime. The adapter verifies
manifest identities, all recorded artifact and snapshot hashes, the expected
suite executable, native linkage (including `@rpath`), and the complete current
source dependency closure. The runner must pin the exact runtime library/module
output hashes, not just its runtime input identity. Each original source path must identify the requested
tree because `#sourceLocation`/`#filePath` can affect runtime fixture/resource
lookups. The build tool owns the receipt format; this command only validates it.
It makes no claim that runtime resources were snapshotted.

The requested host commit must match. Tracked/untracked Python source changes
are rejected; unrelated handoff/documentation edits are allowed. Every tracked
`Firmware/**/*.py` file is inventoried and rechecked, including future imported
logging modules. The generator's selected source manifest is checked separately.
This is bounded Python-source provenance, not a snapshot of the Python installation,
external dependencies or non-Python resources. Logging-only host
branches can be tested with their own reviewed commit; no permanent application
or host commit is hardcoded into the command.

## Explicit reuse of the already validated baseline

An interim, reviewed baseline record is checked in at
`Tests/Fixtures/PairedContract/validated-0254-native.json`. It pins165 native input
files, two existing test executables and their shared runtime. It identifies the
previously validated c39e7e0 source checkpoint; creating this record did not
compile anything. It cannot certify changed production/test/build source.
The separate flag makes this limitation explicit:

```sh
python3 -B PhysicalGo/Tools/paired_contract_acceptance.py \
  --host-root '/Users/dave/Personal/Fab Files/DYNAMIXEL Go Pointer' \
  --expected-host-commit 6dec0c9626a0c33b289f62653878ede2ce67c2ab \
  --native-root '/Users/dave/SGFPlayerClean/PhysicalGo/.build' \
  --native-provenance PhysicalGo/Tests/Fixtures/PairedContract/validated-0254-native.json \
  --allow-reviewed-baseline
```

Missing, replaced or relocated binaries/libraries, changed source hashes, or a
missing opt-in fail clearly. Use fresh builder receipts for subsequent code.
The baseline adapter intentionally does not claim cross-tree resource provenance;
the two pinned consumers generate their game/bridge fixtures in temporary storage.

## What the command proves

1. The actual Swift request encoder exports clear standby, hand retain-only,
   point and OFF requests. The host's existing production-parser/lease tests read
   **these fresh files**, never silently falling back to checked-in golden files.
2. The host production runtime accepts the fresh Swift standby scope with fake
   hardware and publishes actual arming, holding, cooling and full-OFF statuses.
   Its real worker, supervisor, confirmation and guarded-write failure paths
   produce68 fault/status fixtures and four ordered recovery chains.
3. The actual native status decoder consumes the four normal statuses. The
   native game/recovery suite consumes all68 fault snapshots and four causes in
   four recovery modes: schema2 point/standby and schema1 point/targetless OFF.
   Existing checks cover stale receipts, delayed acknowledgements, bootstrap
   uncertainty, new AI targets, explicit Pause/Resume, restart, partial captures,
   clock/history preservation and hard-fault retention.

Coverage is defined independently of fixture manifest assertions: required
filename, route, stage, reason, severity and old/new revision transitions must
agree. A consistently rewritten manifest cannot disguise a missing hand case as
a controller case. Each consumer is also run without fixture opt-ins as a control.
Required fixture checks must increase the normal-status count by at least16 and
the continuity count by at least359, in addition to the overall minimums. Thus an
unset optional fixture variable cannot yield a false pass just because unrelated
baseline tests increased their count. These are aggregate coverage guards backed
by pinned test source; the native executable does not report every assertion ID.

The local host adapter retains11 request tests and5 fault tests. One original
test assumed wall expiry and the derived monotonic deadline were bit-identical.
Fresh Swift timestamps exposed a one-ulp difference. Its explicitly recorded
adapter still checks wall parser rejection at expiry and checks the gate just
before, exactly at and just after its **own** monotonic deadline. No production
threshold or host repository file is changed.

## Limits of the pairing

This is a composed wire-contract conversation, not two concurrently running
application/host processes. Python adjusts lease clocks/revisions while retaining
the fresh Swift scope. Native recovery tests rebind producer/revision, game,
camera/setup/epoch identities, clock origins and evidence watermarks; legacy
recovery cases additionally adapt schema2 fixtures to schema1. They are not
literal schema1 publisher exports. The normal statuses and fault fixtures are
actual Python publisher output, and the request files are actual Swift encoder
output. The four point/OFF/retain-only request shapes pass the production parser
and lease tests; the fake runtime fixture uses the standby request as its scope.

No test here proves optical centering, motor motion, physical safety, thermal
behavior, camera recognition performance or timing under real scheduling. Those
remain separate supervised validation. A passing receipt names the exact tested
artifacts and source, not the installed application's behavior.

Cheap command/negative tests:

```sh
python3 -B PhysicalGo/Tests/test_paired_contract_acceptance.py
python3 -B PhysicalGo/Tests/test_paired_contract_review.py
```

The independent review suite uses the existing local laser repository's68
checked-in status fixtures. Missing fixtures fail rather than skip. Its24 cases
plus10 command tests cover omitted/reclassified coverage, false success output,
timeouts, source/artifact changes, foreign original resource paths, and forged
or missing runtime output pins. The final command passed against explicitly
reused reviewed baseline binaries (229 export/16 host/241 status/492 continuity
checks); the final format2 output-pin extension awaits the root's combined fresh
build. Earlier fresh-format2 execution passed before that last strengthening.
