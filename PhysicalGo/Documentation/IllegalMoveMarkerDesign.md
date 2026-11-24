# Illegal physical placement markers

November 23, 2026. **Screen-only integration candidate:** the read-only tracker is
promoted to `Sources/PhysicalIllegalMoveWarning.swift` and connected to
`PhysicalAI.consume` on the isolated integration branch. It supplies a specific
reason and the existing removal/restoration screen marks. The promoted mechanism
passes 83 independent checks; the new `--ai-illegal-move-test` controller suite is
registered for the combined app regression run. No installation or physical result
is claimed. The optional distinct laser pattern remains a proposal.

The diagnostic path is separate from legal acceptance. It cannot commit a move,
change the accepted position, pause/advance a clock, or create a laser target.
It caches only a private read-only rules engine for the exact diagnostic context;
that cache and its witnesses clear on lifecycle/camera changes and interruptions.

## Existing behavior and the specific gap

`SGFPlayerClean/Models/SGFPlayerEngine.swift` already exposes
`moveRejection(color:x:y:)` with separate suicide, ko and superko reasons. It uses
the complete visible history and `GameAnalysisSettings.playRules`; replay and
legality share the same capture/self-capture simulation. New marker logic should
call this engine, rather than implement Go rules again.

`PhysicalAI.consume` checks that rejection only after
`PhysicalMoveInference.candidate` has identified a possible move. The inference
helper rejects a no-liberty placement first. Before this diagnostic hook, an attempted suicide
reached the generic board-mismatch message, while a recognizable ko
recapture can receive the specific ko message. A regression reproduces this gap.
This is a diagnostic gap, not evidence that the app accepts suicide.

The existing mismatch overlay already marks extra stones with an × and missing
stones with placement rings. There is no distinct illegal-placement laser purpose
or capability. Reusing capture indication for an illegal stone would conflate
legal prisoner removal with undoing an unaccepted move.

## Use the actual game policy

These are the application's present mappings, not a claim that every ruleset
with a similar name uses the same repetition policy:

| Current application/model setting | Engine behavior relevant to this marker |
|---|---|
| Physical AI: Japanese | Simple ko; self-capture prohibited. |
| Physical AI: Chinese, local game | Simple ko; self-capture prohibited. |
| Model: Chinese with online context (`chinese-ogs`) | Positional superko; self-capture prohibited. |
| Model: AGA/BGA | Situational superko; self-capture prohibited. |
| Model: New Zealand | Situational superko; self-capture allowed. |
| Model: Tromp–Taylor | Positional superko; self-capture allowed, but repetition may still prohibit a move. |
| Unknown/unsupported policy | Do not infer an illegal-move reason. |

Physical AI's settings currently accept only Japanese and Chinese. The other rows
are existing engine capabilities tested for future integration, not newly enabled
AI choices. Online play must use the authoritative server policy and rejection;
this proposal does not wire online laser guidance or change server clocks.

## Recommended behavior

First expose a specific screen explanation and the existing × at the positively
observed illegal stone. Examples: “Self-capture is not allowed. Remove B9.” and
“Ko: undo this placement before playing elsewhere.” If an attempted recapture has
already removed stones, also show the required restoration rings. Removing only
the new stone is insufficient in that case.

Keep all three categories distinct:

- Ambiguous or off-center: mark the observed disk for centering; do not guess an
  intersection or label its intended move illegal.
- Captured prisoner: the accepted legal move identifies it; request removal using
  the existing captured-stone indication and capture-clock policy.
- Illegal placement: the move has not been accepted; identify the new physical
  stone and ask the player to undo the attempt. Preserve the current turn, history,
  captures and clock policy. Do not count the illegal move or manufacture a capture.

An optional laser extension should use a new `illegal` purpose and
`illegalMoveIndicationV1` capability. A proposed distinct pattern is a repeating
pair of short stationary light pulses at the observed stone, followed by a longer
dark gap; capture indication remains steady and centering remains a wiggle.
This pattern is not implemented or physically validated. It should be silent,
bounded by the normal indication lease, and stop immediately for a hand or lost
positive stone evidence. Its internal dark gaps must never be published as a
confirmed recognition/full-OFF receipt. Before adding that pattern, verify its
visible distinction on both stone colors in the calibrated setup.

Suggested priority is AI placement → confirmed prisoners → illegal-placement
warning → centering. Existing capture permission must gate a possible illegal
reply, so a remaining prisoner cannot be relabeled as a new illegal stone.

## Isolated diagnostic candidate

The candidate is tracked under
[`PhysicalGo/Experiments/IllegalMoveMarkers`](../Experiments/IllegalMoveMarkers/README.md).
It is experimental, excluded from the application build, and not installed:

- `PhysicalIllegalMoveWarning.swift`: a diagnostic-only tracker and classifier.
- `IllegalMoveWarningTests.swift`: actual-engine fixtures and evidence guards.
- `run_tests.py`: repository-relative runner that extracts the exact pure inference
  declaration from production to reproduce the existing suicide gap; no model stubs.
- `validated-result.json`: the last reviewed result and exact source/runner hashes.

Generated extraction, binary and execution logs remain in the ignored
`PhysicalGo/.build/Experiments/IllegalMoveMarkers/` directory. The original
`work/illegal-marker-candidate/` investigation artifacts remain local historical
evidence, but are no longer needed to reproduce this experiment from a clone.

`Tracker.observe` accepts the live engine, exact game/history/rules/camera context,
human color, permitted phase, pending AI placement flag, raw observation and
existing `captureGuidance.permitsReply` predicate. It returns a candidate containing
the positively observed point, color, authoritative rejection and restoration
points; it never calls a mutating method on the live engine.

Admission requires three distinct fresh clear, aligned, confirmed-dark observations
spanning at least 450 ms, with no gap over 600 ms. The point must be unambiguous and
strongly classified; other intersections must also have positive readings in this
initial conservative candidate. Unknown/retained readings cannot substantiate an
illegal warning. A hand, illumination, stale evidence, changed context, unresolved
capture permission or pending AI placement clears the witness. Exactly one newly
added human stone is required.

The classifier asks the live rules engine for the reason, then uses a private
snapshot-restored engine to determine which opposing stones the attempted move
would remove. It accepts those stones either still present or positively removed;
the latter become restoration instructions. Unrelated changes or partial removal
of one's own self-captured group remain generic synchronization problems.

Integration should add this diagnostic path without weakening
`PhysicalMoveInference.candidate`, legal move acceptance, hand clearance or capture
cleanup. Run it where raw positive observations and the existing dark-evidence
decision are available. Store the warning separately from accepted move state,
invalidate it on normal lifecycle resets, and let its screen/laser presentation
consume the warning without writing SGF or clock data. A future optimization may
permit carefully qualified unchanged history; this candidate deliberately does
not make that change.

## Verification and next test fixtures

The 83 checks cover Japanese/local-Chinese suicide, the existing inference gap,
allowed New Zealand self-capture, unsupported policy, immediate ko with captured
stone present/removed, legal threat-and-response recapture, online-Chinese superko,
legal snapback and capture into a surrounded point. They also cover unchanged live
board/history/captures, capture permission, pending AI placement, duplicate frames,
hand/unknown-hand, uncertainty, ambiguous locations, stale/future timestamps,
illumination, low confidence, context changes and unrelated/additional stones.

The test compiles only the actual shared models/engine plus the isolated candidate,
not another full app build. Reproduction from the repository root:

```sh
python3 PhysicalGo/Experiments/IllegalMoveMarkers/run_tests.py
```

The runner is independent of the caller's current working directory and writes
the newest source hashes/result under the ignored build directory. It does not
overwrite the tracked validation record or start the installed app.

For a later supervised 9×9 diagnostic fixture (not the current live game), place
black A9 and white A8, B8, C9. A proposed black B9 joins a group with no liberty:
the selected Japanese/local-Chinese engine should report self-capture, while the
allowed-self-capture model must not mislabel it. For ko, set black B9/A8/B7 and
white B8/C9/D8/C7; black C8 captures B8, and immediate white B8 is the forbidden
recapture. Test with the black C8 stone both still present and prematurely removed;
the latter must request restoration. Load these as dedicated reviewed fixtures,
never by replacing the preserved user's game without the appropriate test flow.

Remaining work: execute/review the combined full-app controller regressions and
physically validate the screen feedback after installation. Separately consider
the capability-gated silent laser pattern and its host/firmware tests. No physical
marker result is claimed here.
