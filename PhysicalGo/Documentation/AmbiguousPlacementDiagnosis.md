# Between-intersection placement, 2026-11-23

The attended test correctly recognized a White stone but incorrectly chose its
intersection. In the preserved recording `Diagnostic 2026-11-23 16-37-13
81D4E9F0`, frames 697–700 label point 275 White with confidence 1, while neighboring
point 294 is uncertain (confidence about 0.69–0.72). The fitted outline center is
at column 9, row 14.28. The assignment ambiguity threshold is 0.30, so that fit did
not trigger abstention. The controller then retained the previously verified
empty value at 294. Together these readings appeared to be one stable new White
move at 275; it was accepted after roughly 0.576 seconds, followed by AI move 288.

The earlier legitimate White move 180 also had a fitted displacement 0.28, but
all eight neighboring readings were definite. Lowering the global displacement
threshold would flag both observations. The physical reason for the outline
underestimating the between-intersection displacement remains unproven; these
tests replay recorded observations rather than recomputing image analysis.

The candidate fix requires fresh evidence at adjacent expected-empty crossings
before accepting a newly observed stone or confirming a pending AI placement.
If any such neighbor is uncertain or below the existing 0.8 confidence boundary,
the controller waits and discards its current placement-confirmation streak.
It cannot use an old empty label to resolve the new stone's intersection.
Uncertainty far from a new placement, and unchanged established stones, can still
retain previously verified labels. The tradeoff is conservative: a correctly
centered new stone may wait while an immediately neighboring empty point is noisy.

The mandatory assignment gate applies with `Mark ambiguous stones` either on or
off. A future stricter optional centering tolerance is a separate policy: it may
request guidance for a stone whose intended intersection is already clear.
Disabling that preference must never permit a spatially unresolved move. This
patch does not change the marker threshold, and the recorded 0.28 outline still
does not qualify for the existing laser centering hint. Laser marker behavior
requires its own calibrated physical test.

`PhysicalAIAmbiguousPlacementTests` uses the real controller and exact recorded
readings/outlines/timestamps for both moves. It verifies abstention, unchanged
saved history, unchanged clock anchor and no pending AI target, removal recovery,
and acceptance of the legitimate move. Synthetic variants additionally cover
both colors, four corners, the 0.8 boundary, fresh witnesses after an interrupted
streak, distant uncertainty, and pending AI placement with a prompt human reply.
The setting is tested both ways with the laser disabled, matching this attended
session; this is not a test of actual illumination or enabled centering guidance.

Register the suite in `scripts/test_suites.py` as:

```python
'ai-ambiguous-placement-test': Suite('PhysicalAIAmbiguousPlacementTests', 'app',
    ('Tests/PhysicalAIAmbiguousPlacementTests.swift',), optimized=False),
```

The suite is compatible with installed-source baseline `d5d84ef` and the current
branch. For the baseline only, set `PHYSICAL_GO_EXPECT_AMBIGUITY_BUG=1` to prove
that the archived bad placement is accepted while the legitimate placement also
passes. Normal mode requires the fix. Tests use temporary game/bridge folders,
an injected engine callback, and a disabled nonautomatic laser controller.

## Narrow installed-baseline candidate

Root applies this patch to `d5d84ef` as a separate0.256/build257 candidate.
Before modification, the resolved Swift source hash exactly matched installed
0.253: `ce241953f14c58738578888ccd7ec9fb62b367f9644ed135ab999435510c0aba`.
This candidate does not include the staged0.254/0.255 recovery/progress changes.
The new regression is registered as `--ai-ambiguous-placement-test`.

The user's proposed stricter centering tolerance with marker guidance remains a
separate preference, not a reason to accept ambiguous assignments with hints off.
The earlier November16 parallax study remains offline; this patch does not
implement stone-height correction or correct the optical center estimator.
