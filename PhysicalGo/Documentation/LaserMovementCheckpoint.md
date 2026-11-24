# Laser and calibration checkpoint — November 24, 2026

**Driver stopped; last confirmed full OFF `1795516412.7072308`. The previous
calibration completed, but subsequent board/rig displacement requires requalification.**
See [current installed state](IntegrationChecklist.md) and the
[attended test plan](NextPhysicalTestPlan.md). Check actual ownership/state before
starting a new run; this receipt is the last observation, not live telemetry.

## Successful prior setup

`global-full-20261124-002823-16342` completed five fitting targets and nine independent
checks: max final error **2.990 px**, mean **1.901 px**. It retained 205 observations,
204 moves and 102 training poses. First-to-last observation spanned 1,230.9 seconds.
The resulting model covered 361 nominal targets; 130,321 ordered nominal routes
were audited. This is not 361 physical accuracy measurements or a repeatability pass.
The model was bound and used for gameplay before the movement.

Evidence root: [calibration-acceptance-redesign](</Users/Dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign>).
The retained gameplay binding is `gameplay-activation-20261124/binding.json`, setup
`55488244b0fb5395`, SHA-256
`f5fe35d98754cb42665f5be60d41b4178c2047f4f2a7ac6de71154e17f754496`.

## Movement and offline assessment

The 20 empty-board camera frames in `empty-board-20261124-overnight` predate the
movement. The three in `stand-bump-check-20261124` follow it; all native alignment
flags are false and measured corner displacement is approximately 9–35 px.
Dave clarified that camera and laser remained fixed relative to each other.
A camera homography can suggest a transferred aim, but unknown board depth/tilt
and camera–laser parallax prevent certifying it from image alignment alone.

The isolated `codex/calibration-coverage-audit` at `ae40a42` passed 11 offline
tests. Its [report](</Users/Dave/Documents/SGF PLayer/work/ai-laser-integration/laser-position-recovery-20261123/calibration-acceptance-redesign/calibration-audit-source/Firmware/Experiments/CalibrationAudit/README.md>)
keeps the transfer diagnostic nonproduction-loadable (`grants_motion=false`).
35/361 estimated targets extrapolate beyond the old domain. Two moved-image printed
grid diagnostics pass; the third fails weak N1 evidence. None override native
alignment rejection. Prior held-out corrected checks and first-aim prediction
errors must remain separate. Residual interpolation worsened 4/8 supported
endpoints and was not adopted.

## Next physical step

Establish current camera geometry, observe an interior spot with Dave present,
screen center/four insets and a center revisit, then independently qualify
boundaries before binding. Refit if measured errors or domain coverage require it.
The gameplay requalification marker must remain until that review is complete.
No automatic rebinding, relighting or model learning is enabled.

The older full03 failure, unobserved settlement and prediction-policy investigation
remain in [the November 23 historical checkpoint](LaserMovementHistory20261123.md).
Those poses and “no completed calibration” statements are superseded.
