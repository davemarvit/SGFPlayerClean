# Development, tests and evidence

[Start here](README.md) · [Current status](../IntegrationChecklist.md)

Use the existing repositories, preserve unrelated changes and make reviewable
checkpoints. The app and laser are separate Git repositories. Source changes in
one do not install or update the other. Raw recordings and generated builds are
not generally tracked, so a pushed commit is not a backup of every investigation
artifact.

## Application build and targeted tests

Run from the source checkout and commit matching the intended runtime. Resolve
them from the [authoritative checklist](../IntegrationChecklist.md) and
[current release receipt](</Users/Dave/Documents/SGF PLayer/work/feedback-play-release-20261124/current-release.json>),
then verify Git status and the receipt's source hashes. The canonical documentation
checkout may contain older runtime code; do not assume it builds the installed app.
For example, from the verified source checkout:

```sh
python3 PhysicalGo/build.py --list-tests
python3 PhysicalGo/Tests/test_build.py
python3 PhysicalGo/build.py --laser-standby-test --ai-laser-test --capture-state-test --capture-laser-test --capture-controller-test --debug-tests
```

The registry in [test_suites.py](../../scripts/test_suites.py) is authoritative for
flags and test entry points. [build_sources.py](../../scripts/build_sources.py)
resolves shared source dependencies. Multiple selected suites use a
content-addressed shared test runtime via
[shared_regressions.py](../../scripts/shared_regressions.py), avoiding a complete
app rebuild for every suite. Shared builds now serialize cache publication and
compile private source snapshots; identified runner paths prevent another build
from replacing the executable about to run. Use isolated worktrees for coherent
changes. Runtime fixtures/resources are still live, and GUI or hardware tests
still need a single execution owner. See [build provenance](../BuildProvenance.md)
for cache receipts, release-source checks and the precise isolation limits.

| Change area | Useful initial suites |
|---|---|
| AI lifecycle, fast worker, legal acceptance | `--ai-play-test` (includes real local engine cases) |
| Laser intent/dark evidence | `--ai-laser-test`, `--laser-standby-test` |
| Capture and marker interaction | `--capture-state-test`, `--capture-laser-test`, `--capture-controller-test`, `--marker-scenarios-test` |
| Stream restart/pixel identity / independent clearance | `--broker-epoch-test`, `--camera-safety-test` |
| Background bridge IO / ephemeral publication | `--bridge-io-test`, `--ephemeral-io-test` |
| First-light click preference and failures | `--ai-move-click-test` |
| Handoff/fault recovery and clock continuity | `--guidance-continuity-test`, `--laser-standby-test` |
| Cleared-board/ended-game recovery | `--recovery-lifecycle-test` |
| Hand clearance | `--hand-outline-test` and the relevant incident fixture suite |
| Local clocks/capture/review | `--capture-clock-test`, `--clock-review-test`, `--hand-clock-test` |
| Online physical move inference | `--online-test` |
| Storage/review lifecycle | `--storage-flow-test`, `--review-queue-test` |

Select tests for the actual changed behavior. `--all-tests` exists but is not a
substitute for understanding a failing incident. Record failures as well as passes.
Real engine latency depends on warm/cold state; do not present an isolated test
timing as the complete physical move-to-light latency.

`python3 PhysicalGo/build.py` builds and signs the app under `PhysicalGo/.build/`.
It does not itself establish which bundle is running. HumanSL weights are fetched
and verified by [prepare_human_model.py](../../scripts/prepare_human_model.py) and
are ignored in Git; the build reports a missing resource rather than silently
changing opponent behavior. Read the build script before reproducing an install.

## Laser offline verification

The laser project has Python tests under `Firmware/Host tests`, firmware-native
fakes under `Firmware/AimControl tests`, and new gameplay review tests. From the
laser root, a targeted Python discovery command is:

```sh
python3 -m unittest discover -s 'Firmware/Host tests' -p 'test_bridge_*.py'
```

Individual test files may need the project's existing Python dependencies or
local fixtures. Inspect the named test before broadening a run; do not substitute
a live hardware launcher for a missing test. Independent gameplay contract and
transport review files use fake clocks/transports and actual encoded app fixtures.

The cached Arduino CLI is
`/Users/dave/Library/Caches/GoPointerArduino/bin/arduino-cli`, with configuration
`/Users/dave/Library/Caches/GoPointerArduino/arduino-cli.yaml` and board FQBN
`OpenRB-150:samd:OpenRB-150`. A board compile and native simulation are distinct
checks. Uploading firmware is a root-owned hardware action, not part of an offline
test command. Preserve an exact verified rollback binary before installation.

## Validate the interface in both directions

Swift encoding and Python parsing can diverge even when each side's unit tests
pass. `PhysicalLaserStandbyTests` supports a
`PHYSICAL_GO_STANDBY_FIXTURES` output directory for actual Swift JSON requests.
The host's `test_gameplay_contract_review.py` checks representative clear/hand
standby and OFF fixtures. Refresh fixtures after contract changes and retain
provenance; do not hand-edit them until they happen to pass.

The standalone [mandatory paired acceptance command](../PairedContractAcceptance.md)
exports fresh Swift requests, runs the Python parser/runtime with fake hardware,
and requires both native status and ordered-recovery consumers. It validates build
receipts and fixture coverage, fails on missing opt-ins/provenance, and keeps all
generated output temporary. This is an offline contract check, not a device test.

Contract review should cover initial OFF negotiation, unsupported capability,
immutable session/preparation fields, retain-only hand transitions, stale status,
thermal ages, late results and shutdown. A version field alone does not prove
that the installed controller supports a new capability.

## Record four kinds of evidence separately

| Claim | Required record |
|---|---|
| Implemented | Source paths and Git commit/diff describing resulting behavior. |
| Offline verified | Exact test/build commands, outcomes and candidate/source identity. |
| Installed | Bundle version/build/source hash and signature, or firmware identity and verified binary hash/upload receipt. |
| Physically validated | Setup/camera identity, actual sequence, observations, timing limits and final OFF/state receipt. |

The app embeds `PhysicalGoSourceHash` in its Info.plist. A build's version number
alone is insufficient when the working tree or installed bundle can differ.
Firmware similarly needs exact source/binary provenance. Record what was not
tested; a simulated two-hour run is not physical endurance.

## Git and handoff

Use `codex/` branches. Inspect changes before staging so recording directories,
model weights, compiled binaries and private local state are not swept into a
commit. The laser repository deliberately ignores the large `Camera checks/`
directory; keep its evidence locally unless a deliberate bounded regression
fixture is selected with provenance.

After meaningful work, update the current checklist and investigation record,
then the shared handoff if another chat/component needs the result. A useful
handoff names source/commit, tests, installed versions, current physical state,
exclusive hardware owner, exact outstanding step and artifact path. Do not leave
an old “test running” note as the final record after the run has stopped.

`ExperimentModel` accepts optional AI/online-controller dependencies for isolated
UI tests; production defaults are unchanged. Supply temporary AI, laser, online,
recording, evidence, diagnostics and stone-library storage when testing modes.
The old mode test accidentally loaded the live saved AI snapshot; this was fixed
in87fc4a9. Keep source-specific receipts when unchanged suites run before a later
constructor-only isolation change. The historical 0.258 package is recorded in
[IntegratedPhysicalTestCandidate.md](../IntegratedPhysicalTestCandidate.md).
The authoritative checklist and linked current release receipt record the exact
installed app, paired host and latest physical outcome.
Documentation-only revisions do not constitute a rebuild or new physical pass;
keep the compiled source hash and tested runtime commit separate from later doc commits.
