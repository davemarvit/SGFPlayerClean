# Optional native candidate validation — November 24, 2026

Seven native suites pass **857 checks**, plus20 lightweight Python summary checks.
This is offline validation of the optional candidates listed below. No app was
installed or launched; no window was shown, audio played, camera acquired or
controller accessed. The offscreen play-view render uses a detached hosting view.
This batch does not validate root's different minimal native/host integration or
close any issue awaiting physical acceptance.

## Exact source and runtime

Base `0628a336d5bcd9a4ff2e16c22106b77e7c14e6d8`, with these commits applied in order:

| Scope | Original commit | Combined cherry-pick |
|---|---|---|
| PG03 complete hand tracker checkpoint | `56e8740` | `a3eb4f9` |
| PG00 worker latency classification | `0c1811e` | `0195d37` |
| PG10 stale centering hint cancellation | `29965ff` | `e8a9e05` |
| PG16 camera-stage attribution | `6d4935d` | `03d5be0` |
| PG21 first rejected frame retention | `a975ab7` | `6f1b491` |
| PG21 diagnostic test allowance correction | `7b20745` | `a60394f` |

Final tested source: `a60394ff93c62d72075dce52e7ca8549ae260e27`.
The report commit following that source changes documentation only.
Worktree: `/Users/Dave/SGFPlayerClean-worktrees/optional-native-validation`.

One debug shared runtime was compiled:
`eafcc91160e631dc76942c82464467a6eee88a48b56c6170fc029872c93b68dc`.
The existing `compile_suite` helper was called directly, bypassing asset preflight;
no download or full app build occurred. All seven suites ran serially. Before the
corrected diagnostic runner was rebuilt, every runtime input hash was verified
against the immutable receipt; that runtime and receipt were reused unchanged.

## Results, including the failed attempt

| Suite | Checks | Result |
|---|---:|---|
| `ai-idle-reuse-test` |78|Pass|
| `ai-play-test` |169|Pass, including real KataGo and four HumanSL profiles|
| `ai-laser-test` |283|Pass; audio callback injected, no playback|
| `marker-scenarios-test` |80|Pass|
| `hand-stone-pipeline-test` |67|Pass, retained A18/C1 photographs|
| `latency-trace-test` |26|Pass|
| `async-diagnostics-test` |154|Pass after test-only correction|

The first six suites passed at `6f1b491`. The initial diagnostic suite exited-5
with `PhysicalGo.Diagnostics` Code2, “Diagnostic storage allowance is too small
for this recording.” Its new session called `start` without the1MB explicit
`byteLimit` used by the same fixture's initial session, despite the custom store
having only5MB allowance. Production rejected the oversized default correctly.
PG21's owner supplied the one-line test correction `7b20745`; only that test
runner was rebuilt and rerun. No production storage budget changed. The first
failure remains in the saved log/results rather than being replaced by the pass.

The real-engine test measured a5.499s cold reply and0.070s warm reply in this
execution. These are test-engine observations, not physical placement-to-reply,
move-to-light or current gameplay latency claims. The Python camera and AI-worker
summary suites each passed10 tests before native execution.

Compiler warnings remained for existing trailing-closure syntax, deprecated
`plotAreaFrame`, vendor optional coercion, a mutable test local, and Swift6
concurrency diagnostics while compiling in Swift5 mode. There were no compiler
errors. These unrelated warnings were not edited during validation.

## Durable evidence and resource isolation

[Evidence directory](</Users/Dave/Documents/SGF PLayer/work/optional-native-validation-20261124>)
contains the original seven-suite log, initial failure/results, corrected async
log/results, final results, runtime completion receipt, fixture SHA256 identities,
and the exact original runner script. `final-results.json` records every test
executable path/hash and the resource identities below.

Models/config were accessed through uncommitted symlinks into the frozen
`camera-safety-delivery` worktree. They were not copied, downloaded or modified:

| Input | SHA256 |
|---|---|
| `SGFPlayerClean/Resources/analysis.cfg` |`f0f39c904316e92f67056941434dbd305626c2f14c8d9ee728c9c26e82d50cef`|
| `SGFPlayerClean/Resources/kata1-b18.bin.gz` |`9d7a6afed8ff5b74894727e156f04f0cd36060a24824892008fbb6e0cba51f1d`|
| `PhysicalGo/Resources/AI/b18c384nbt-humanv0.bin.gz` |`637746e44f0efe00ad1245a50aa9bbf0716efe364c43965ead97bd6835d84ab5`|

Two tracked resource paths intentionally remain local symlink typechanges and
must not be committed. The HumanSL path is ignored. Native source files remain
unchanged after the test-only correction. Sparse source checkout was45MB and
initial seven-suite build42MB; no raw evidence or cache cleanup was performed.
Swift/heavy execution slots were released after the original batch and the
corrected runner. Installation, full paired validation and physical acceptance
remain root-owned.
