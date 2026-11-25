# Next Physical Go test

See [the issue register](IntegrationChecklist.md) for the authoritative state and checkboxes.
Updated November24,2026 after the completed P15/K18 run. Hardware is fully OFF;
there is no active launcher or pending READY. Seven aiming locations have successful
observations across saved runs. Do not repeat them or restart the full five-plus-nine tour.

1. Resolve PG-31's false alignment rejection with retained-frame and moved/covered-board regressions.
2. Finish PG-06b's offline timing/step-count work; retain real timing and interruption evidence.
3. Implement PG-33's feedback-first gameplay path, including cancellation, fresh pose, hand/lease safeguards and full OFF. The old gameplay launcher/binding is still blocked.
4. Build, paired-test and install the reviewed app/host combination with rollback and preserved game/reference. A source commit alone is not installation.
5. Only then run a short attended game: ask READY at the launcher; check PG-04 placement/clock/AI/dot, PG-07 holding, PG-03 hand recovery, PG-26b click. Measure latency and preserve any first fault (PG-32/PG-06a).

No additional physical test is authorized by this document alone. The user's task
authorizes preparation; use fresh live checks and READY for the next activation.
Broader captures/illegal/ambiguous-placement/thermal tests remain unchecked in the
register rather than disappearing from the plan. Historical test plans are retained
in the Nov24 docs-before-issue-register snapshot linked there.
