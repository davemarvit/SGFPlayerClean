# Reviewed dense-response movement correction

This focused follow-up implements the user's request to correct movement and prepare the reviewed host/firmware for activation. Root owns integration, installation, firmware upload and attended operation. Workers remain offline. The frozen three-point benchmark is unchanged.

## Source selection

Start from clean frozen host `fe469196d539db4bbe5e4017dd75437bc54f1d1a`. Apply:

1. `272e4c9` — immutable qualified dense-response loader and provenance/support tests.
2. `f9dde4f` — API and evidence documentation.
3. `115710f` — explicit `attended_full_board_v1` policy with extrapolation diagnostics; optional strict policy remains distinct.
4. `71fe937` — gameplay derivative at actual encoder pose, refreshed after observations, no secant carryover, final optical-age check after derivative/setup work.
5. `a288718` — module wording only.

The assembled branch `codex/dense-response-feedback` uses equivalent dependency cherry-picks `f07f5c4`, `5d74355`, and `a62f700`. Do not apply both original and equivalent commits.

Independent review `a98063b` on `codex/cross-change-review` approves the concrete source and explicitly supersedes the prior response-domain block for this candidate. Final production cohort artifact confirmation is being completed; no additional theoretical proof scope was requested.

## Binding and admission

`feedback_first.response_prior` pins version, model path/hash, training-result path/hash, training-setup path/hash, requalification-result path/hash and support-report identities. Use the reviewed PG02 policy artifact, including semantic setup and fresh-reference pins, rather than reconstructing a partial policy from this summary.

Exact model `all_saved_fit-model.json` SHA256:

`adf8ace866254af7a82cdcfecb984ce539490689794d119357a85fb6fdcb42fa`

Retain original model setup ID `6df953c81527c184` and explicit approved lineage to fresh setup `8d98ed7584c4265a`. Model coefficients/training identity are not rewritten or refitted. The current measured spot anchors each correction; the dense model supplies only the local derivative at measured encoder pose. An invalid prior fails closed, with no silent return to the disproven affine/secant response.

The recommended policy is `attended_full_board_v1`: all 361 board coordinates may be supervised feedback attempts, with actual/command/prelight extrapolation logged. This does not claim every location has been physically validated or every attempt will succeed. The existing finite/motor/conditioning, uniform 0..2-axis plus5px response, actual-pose, hand, optical-age, lease, thermal and full-OFF checks remain unchanged.

The strict observed-hull mode is an optional policy choice, not a calibration requirement. It rejects79 of361 simulated routes despite the corrected dense-response route succeeding; missing coverage alone is not a demonstrated failure.

## Evidence available

- Helper provenance/policy tests:16 passed; runtime-focused combined tests:65 passed.
- A delayed derivative/setup regression advances an optical sample from100ms to601ms and verifies no anchor cache publication.
- Exact production helper replays71 chronological retained movement endpoints: old response4 envelope violations, dense response0. Maximum distance outside the unexpanded dense gain hull is2.0471879349px, within unchanged5px allowance.
- Production-helper exact-anchor cohort:361/361 reached, no simulated containment violations, minimum path margin12.9586px;79 targets record extrapolation.
- Earlier corrected-response center cohort:361/361, minimum14.4118px. Opposite-perimeter cohort:70/72 reached, zero violations, minimum10.5753px; two rounded starting poses fail before movement/light at the unchanged clearance requirement. Final production-helper artifacts will distinguish these from earlier comparison runs.

The diagnostic plant shares the retained model family and does not establish independent physical path/corner accuracy. Chronological endpoint evidence is correlated and does not observe every travel path. These are explicit attended-test limitations, not unsupported absolute safety claims or a mandatory new full calibration tour.

## Root release boundary

Root reports the PG08 firmware fix installed and verified fully OFF at1795578282.7556946, binary SHA256 `f3e4cd52285eaadd4aa9c5772c232201e6b1f758a275d2669543576343119be7`. No worker uploaded firmware or issued motor/light commands.

Root must pin the exact integrated source/binding/package, rerun affected and paired acceptance, and use fresh live setup checks plus READY before any physical aiming. A staged package or passed offline test alone is not activation. Keep the paused game and historical calibration/evidence intact.

