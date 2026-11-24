# AI play clock layout

The AI play view follows the local two-player layout: two large clock cards,
move totals below them and a prominent central Pause/Resume button. Each card
names the stone color and You or KataGo. Clock options can switch display sides
or open a larger clock sheet. These are presentation settings only.

Board coordinates appear on all four sides, using the existing shared Go label
generator (including skipped I) and the same display rotation as the stones.
The human/local board already used that generator; camera pixels and calibration
are unaffected.

The clocks explicitly show **elapsed practice time**, counting up. Their values
and highlighted side come directly from `PhysicalAITiming`; they do not infer a
turn from the screen marker or pending physical placement. Human move acceptance
and AI decision receipt remain the only player-switching events. The existing
capture-cleanup pause policy and all saved time values remain unchanged.

Placement and capture instructions remain visible. Connection/laser status and
camera warnings remain in the primary play view. Timing explanations, laser
centering hints and test/practice controls are grouped below the board. The board
uses the same viewport-derived height budget as local play.

Sources:
- `Sources/PhysicalAIClockView.swift` owns clock layout and calls existing game
  pause/resume actions.
- `Sources/PhysicalAIClockFace.swift` renders supplied clock values only.
- `Sources/PhysicalAIView.swift` embeds the panel and groups secondary controls.

This is an offline UI candidate, separate from the camera-delivery repair. No
application has been installed or relaunched by this work, and no live game,
camera or controller has been accessed. Light/dark clock-card previews are stored
outside Git in `work/ai-play-clock-layout-20261124` in the integration workspace.
They are rendering checks, not a live gameplay acceptance test.

Offline verification: 278 AI laser lifecycle/clock/dark-frame checks, 133
guidance-fault continuity checks and 680 four-edge label checks passed. The
final shared-runtime identity is
`313863f995b27b5118f3c66fa805c93d9e06982e412387207846c7dbd553e9dc`.
Offscreen full-play previews use an isolated paused synthetic game and verify
0°/90° rotation and a compact board height; no live app was controlled.

## First-light stone click

The existing first-confirmed-illumination event still plays at most one click
per AI move. Refinement, retries of the same pending move and centering hints do
not replay it. The UI now exposes a dedicated enable switch, volume slider and
**Test click** in AI settings and the play view's timing/sound options. Testing
the sound does not activate the laser or alter the game.

`PhysicalAIMoveClick` owns a separate persisted preference. On first use it
preserves the prior clock-audio volume, then subsequent clock-volume or warning
feedback changes cannot mute the move cue. `StonePlacementAudio` continues to
prepare/play on its background queue and now reports missing-asset/playback
failures. Optional latency tracing records cue requests and playback results.
A successful playback-start result does not prove the user heard it: macOS's
selected output, system volume and connected headphones still control routing.

The focused `--ai-move-click-test` checks preference migration, warning
independence, mute controls, preview and asset-failure reporting with injected
audio only. No sound is played by this test. Installation and audible physical
validation remain deferred to the integration owner.

Audio follow-up verification passed 13 dedicated preference/audio checks, 278
laser lifecycle checks, 133 guidance continuity checks and eight build-registry
checks. The final control also compiled and rendered offscreen after removing
dense volume-slider tick marks. Test/preview audio was injected; no sound was
played and no live app was installed or restarted.
