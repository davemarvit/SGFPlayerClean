# Build snapshots and ownership

Status November 24: this tooling is integrated in the installed-source worktree
and was used for 0.260 verification. The isolated November 23 results at the end
are historical; current build/install receipts are in [the checklist](IntegrationChecklist.md).

The shared regression builder compiles identified source copies rather than live
Swift files. Its command-line interface is unchanged: multiple test flags and
`--all-tests` use the shared runtime. A single suite can opt in using
`PHYSICAL_GO_SHARED_REGRESSIONS=1`.

## What is captured

For each call, the builder reads the resolved runtime and test inputs once,
checks that the capture did not overlap a persistent edit or inventory change,
and retains those exact bytes. It records repository-relative and original paths,
original/prepared SHA-256 values, compiler and frontend paths/content hashes,
compiler version, SDK path/settings/version, target, optimization, selected build
environment and builder hash. A source edit after capture belongs to the next
candidate; it cannot change the bytes currently being compiled.

Original and prepared sources are read-only copies inside a private staging
directory. Preparation adds a Swift `#sourceLocation` directive and, for test
sources, the existing testable runtime import. Unlike textual replacement of
`#filePath`, this does not alter raw strings/comments containing that spelling.
Original source-location directives still take effect. Shebang script inputs
are rejected explicitly; registered regression entry points use `@main`.
The runner compiles with `-parse-as-library`, also supporting a one-file test.

**Resources and fixtures remain live.** Original source paths are retained in
`#filePath`, preserving existing model/fixture lookup. Executables remain in
`.build`, where `Bundle.main` finds the prepared voice resources. This source
manifest is not an immutable snapshot of runtime models, fixtures, installed
SDK contents, environment-dependent external tools or hardware. Acceptance tools
must separately identify their declared fixture/resource inputs. No claim is
made that independent OS/toolchain components are hermetically captured.

## Publication and concurrency

One advisory lock at `.build/RegressionModules/build.lock` serializes shared
builders in this worktree. It covers input capture, cache validation, compilation
and publication. Separate worktrees have separate outputs and locks. The lock
does not serialize later test execution or replace GUI/hardware ownership.

Runtime and runner compilations write into private temporary directories. Only
successful outputs with all required files, unchanged staged inputs and an
unchanged selected toolchain/builder are atomically renamed into the cache:

```text
.build/RegressionModules/runtimes/<runtime identity>/
.build/RegressionModules/runners/<runner identity>/
```

Each `complete.json` contains `manifest` and a `files` map of relative output paths
to SHA-256. The identity is SHA-256 of the UTF-8 canonical JSON manifest, using
sorted keys, no optional whitespace and unescaped Unicode. Cache hits validate
the complete file inventory and every file hash. Missing, malformed, incomplete
or corrupted entries are rebuilt; failed compiles do not publish complete entries.
Inputs and output artifacts are both retained for inspection.

The dylib has install name `@rpath/libPhysicalGoTestRuntime.dylib`; each runner
embeds the exact immutable runtime directory as its rpath. It does not depend on
the temporary compilation directory surviving publication.

`compile_suite()` returns an identified executable:

```text
.build/<registered executable>-<runner identity>
.build/<registered executable>-<runner identity>.build.json
```

The pointer has `schemaVersion: 1`, absolute `runnerReceipt` and `runtimeReceipt`
paths, `runnerIdentity`, and `executableSHA256`. Manifest format is 2. Runtime
manifests have `kind: runtime`, module, configuration and inputs; runner manifests
have `kind: runner`, executable, runtime identity, configuration and test inputs.
The runner also pins the exact dylib and module output hashes in
`runtimeArtifacts`. If repairing a corrupt runtime produces different bytes
under the same input identity, the runner identity changes and it is rebuilt.
Each source name is relative to the repository root. Receipts store original
sources under `original/<source name>` and prepared sources under
`prepared/<index>_<basename>`.

The conventional `.build/<registered executable>` is still refreshed for manual
use. `build.py` executes the identified path instead, so another caller publishing
the same suite cannot replace the executable this caller is about to run.
Changing test source alone reuses the unchanged runtime and creates a new runner.
Existing pre-format-2 cache directories are left intact but are not reused.

## Release-build boundary checks

The full application builder has a separate `.build/release-build.lock`, acquired
before modifying the app bundle and retained through signing/process exit. This
prevents two release builders from overwriting the same output concurrently.

Immediately before compilation, it captures the exact resolved source order,
content hash, file identity and modification/change timestamps. The content hash
must match the bundle's declared source hash. After compilation, the builder
resolves the source inventory again and rejects additions, removals, reordering,
content changes and ordinary edit/revert operations **before code signing**.
This is a boundary check, not a replacement of the release builder with a fully
immutable source/resource build. Do not install a failed/unsigned output as a
verified candidate. External writers that ignore the lock remain outside its
ownership guarantee.

## Verification

```sh
python3 PhysicalGo/Tests/test_build.py
python3 PhysicalGo/Tests/test_build_provenance.py
python3 PhysicalGo/Tests/test_build_provenance_review.py
PHYSICAL_GO_PROVENANCE_SWIFT_SMOKE=1 python3 PhysicalGo/Tests/test_build_provenance.py
```

The last command adds a tiny real Swift module/runner test, not a full app build.
It exercises linking after temporary directories disappear, source-relative
locations and literal `#filePath` preservation. Other tests inject live edits,
staged-source corruption, compiler changes, partial compilation, malformed cache
receipts, test-only edits and competing processes. Separate release checks cover
source changes, disappearance, inventory/order changes and build ownership.
`--all-tests` includes all three Python build-check scripts.

Full shared-runtime validation is separate from these small tests. This work
does not operate a camera, laser, game or installed application.

November 23, 2026 isolated-branch verification: 20 focused checks (including the
tiny real Swift module/runner), seven independent boundary checks and eight
registry checks passed. A real shared-runtime batch passed all three suites:
26 calibration-progress, 492 guidance-continuity checks consuming the actual
68 host statuses, and 225 monitored-standby checks. The runtime identity was
`dbb28de4f6ca43e530afb5ce7510ffd57bd126768bd2a3e820db51e2a5bf970e`;
the log is `.build/provenance-shared-smoke.log` in the experimental worktree.
That full-runtime result predates the final `runtimeArtifacts` output-hash pin.
The pin has an additional same-input/different-output mutation regression and
the tiny real Swift smoke; the combined candidate must rebuild the full runtime
with the final builder. These are offline results; no release app was built or
installed by this branch.
