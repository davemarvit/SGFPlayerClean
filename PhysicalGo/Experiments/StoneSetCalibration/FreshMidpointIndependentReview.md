# Independent review of the fresh midpoint audit

November 23, 2026. Reviewed `7c9f57c` and retained result SHA256
`48d9f3b079856f9efa2aecc8c873694c522effcee1990bfe7bc2edcb03ea1036`.
No app, hardware, camera, profile or captured evidence was changed.

**Clear for the stated offline conclusion:** the two frozen scalar optical models
do not bring these two fresh misplaced stones close to either adjacent crossing.
This is not a result from the live classifier, a measured physical contact point,
a new camera setup or the preselected heldout board locations.

## Findings

No blocking defect was found in the bounded coordinate comparison or its factual
claims. The distinction between a fresh negative placement episode and a heldout
location is correct and material. Actual moved Black is `(15,9)` toward `(14,9)`;
that original location was used for training. The earlier instruction `(9,15)`
was not silently substituted into the evidence. The capture manifest retains the
instruction correction, and the eight-stone comparison shows the actual moved
body changed about `(−.4293,+.0104)` cells while the seven others changed at most
.0125 cells. White subsequently replaced the displaced Black. They are separate
physical placements, so their difference does not isolate a color effect.

The script deliberately uses a known crop location and a fixed 19×19,
1920×1080 study. It is not a generic capture-admission service or blind detector.
The reviewed actual manifests mark both episodes `includeForTraining:false`,
`freshNegativeEpisode:true`, `preselectedHeldOutLocation:false`; image dimensions,
frame identities, camera and epoch independently match their metadata. The script
must not be reused as an automatic compatibility gate merely because this archive
passes its checks.

## Coordinate and exposed-rail audit

The transform is correctly ordered:

`body in that frame's grid → that frame's H → raw pixels → inverse frozen H or G`.

H uses `(width−1,height−1)` pixel scaling and divides board coordinates by 18.
G is already a board-to-pixel matrix and receives no extra normalized-H scaling.
The frozen model's camera coordinates and k are applied in the corresponding
frozen board-coordinate system. The inferred contact is the algebraic inverse
`(apparent + kC)/(1+k)`. No optical field is refitted and no median image shift is
applied to the body pixels. Study01 and study02 fit dictionaries are identical.

Seven exposed printed crossings exclude the moved location. The audit measures
both rail directions in the first and last image of each episode, compares their
raw-pixel positions against the original Black calibration, and records the
remaining common displacement. It is not registering each frame or asserting
zero camera movement. Independent replay reproduces maximum displacements of
.4619 px for Black and .5348 px for White, with maximum residual after diagnostic
median subtraction .1874 px. The median subtraction is diagnostic only. The
source's lack of a general registration acceptance threshold is disclosed rather
than silently promoted into an authorization rule.

## Independent verification

A full rerun of `fresh_midpoint_audit.py` into a new temporary output took about
8 seconds and produced JSON exactly equal to the retained artifact. The rerun
recomputed body masks, rail measurements, movement comparison and summaries.
The original result was not overwritten.

The adjacent `fresh_midpoint_review_check.py` independently checks:

- Result, source/helper, model, sample-manifest, image, metadata and refined-G
  hashes; all 16 actual images and frame identities; camera/epoch/grid dimensions.
- Scalar homography projection and a separate two-equation inverse for all 16
  frames. Maximum native-grid pixel roundtrip error is `2.55e−13` px. Refined-G
  roundtrips also agree within `1e−9` px.
- Reconstruction of apparent positions from inferred contacts and unchanged
  coefficients, both neighbor distances, and rail displacement summaries.
- Equality to original study01 coefficients/heldouts and exclusion of these
  negative manifests from training.
- Two isolated invalid-input controls: changed epoch and changed image hash
  both stop before writing a result. Only temporary metadata/manifests are changed.

The minimum neighbor distance over all frames and both hypotheses is
**.4334398616 cells for Black** and **.4828783446 cells for White**. Distances are
Euclidean norms in grid coordinates, not millimeters and not a physical norm
corrected for unequal row/column pitch. The small ranges reflect one placement's
repeatability, not eight independent negative trials or calibrated confidence.

## Interpretation boundary

“No false centering” is supported only in this narrow sense: the reported frozen
conditional coordinates remain substantially between neighboring crossings.
There is no live move-acceptance or assignment-policy decision in the audit, and
therefore no measured classifier false-positive rate. The approximate midpoint
instruction is not physical contact ground truth. Neither this result nor the
exposed-rail audit identifies physical thickness or validates a portable stone
profile. The exploratory body estimator still has its previous appearance-bias
and grid/camera-assumption limits.

The new data resolves the previously missing fresh Black negative **at this
training location**, and adds a fresh White episode there. It does not resolve
negative placements at `(9,3)`/`(9,15)`, independent setup transfer, crowded or
occluded positions, or the older free-field failure. Those distinctions should
remain explicit in current checklist/profile status. No runtime integration or
profile activation is recommended solely from this audit.
