# SGFPlayerClean

Native macOS SGF player with shared 2D/3D board state, OGS live play, and KataGo analysis.
The application project is `SGFPlayerClean/SGFPlayerClean.xcodeproj` and its scheme is `SGFPlayerClean`.
The older `davemarvit/SGFPlayer` repository is a separate implementation.

An initial iPad target now lives in `iPad/QuietGo-iPad.xcodeproj`, sharing the game
engine and SceneKit sources. It supports local play, SGF review/import/export,
session recovery, embedded offline KataGo CPU analysis, and an OGS interface for
login, challenges, live play, scoring, chat, and reconnecting. Start with
[`iPad/README.md`](iPad/README.md) and `iPad/Run iPad Simulator.command`;
the iOS `.app` cannot be launched directly as a Mac app. See
[`iPad/Validation.txt`](iPad/Validation.txt) for tested scope and remaining work.

## Pass announcements and recorded results — November 1, 2026

Both board views show a translucent circular “Black passes” / “White passes”
announcement: 150 ms fade-in, 650 ms hold, 1.2 s fade-out. It overlays the board
without changing its layout or intercepting clicks. Automatic playback gives
passes at least two seconds, including at fast speeds; manual steps stay immediate.
Local play and review now use the existing spoken “Pass” clip, with the normal
voice/master volume and mute settings. Online passes retain their existing audio
and show the circle once for optimistic moves and received opponent moves;
duplicate server events do not repeat it. Scrubbing remains silent.

Imported review games show a prominent final result at the original main-line
end, including point margins, resignation, timeout, forfeit, draws, void and
missing results. Moving away from that position hides it. Alternate/edited
continuations do not inherit the recorded outcome. This uses SGF RE, never an
analysis estimate. The existing completed-game banner remains available for games
finished in the app. Recorded dame moves remain intact at the selected speed.

The native saver and preview use the same pass labels, fade timing and result
formatting. The saver stays silent, briefly draws at 30 fps while fading, and
returns to its normal update interval afterward. The final result remains for
its seven-second ending pause; loading another game clears both announcements.

Validation: `PassPresentationTests`, `Screensaver/test.py`, the signed saver
preview's `--test` mode, and the production `PassPlayback`, `PassOnline`, and
`FinalMoveStability` probes cover timing, score formatting, consecutive passes,
audio/mute, duplicate events, navigation, rendering and fixed board geometry.

## Board coordinates — October 27, 2026

Settings → Playback → Show Board Coordinates adds letters along the top and
bottom and numbers along both sides of the 2D and 3D boards. It defaults off,
updates immediately, and saves across launches. Coordinates follow GTP: A–T,
skipping I, left to right; 1–19 bottom to top (A1 at lower left). Smaller boards
use the corresponding subset. The 2D grid reserves margin space while the
setting is enabled, and stone placement and analysis overlays use that same grid.
3D labels remain attached when rotating the board or switching environments.

`Tests/MainRelease/BoardCoordinates.swift` verifies 9/13/19 boards, labels,
preference writes, live 2D appearance/restoration, 3D rebuild/removal, and settings.
Convention: https://www.lysator.liu.se/~gunnar/gtp/gtp2-spec-draft2/gtp2-spec.html#SECTION000211000000000000000

## Variation tree context menu — October 27, 2026

Right-click (or Control-click) a tree node for Add pass here, Delete Node, and
Undo Delete. Nodes with children are labeled Delete Node and Continuation, since
deleting a move removes its descendants too. The menu targets the clicked node
without changing selection when opened; its target stays fixed if the focus lens
moves before the action runs. Deletion selects the parent, preserves sibling
lines, saves the edited review, and can be undone with the whole branch restored.
The starting position is protected, and live online contexts cannot edit nodes.
The toolbar's existing delete and undo controls remain available.

`Tests/MainRelease/TreeContextMenu.swift` exercises native menus, unselected targets,
lens changes, leaf/branch deletion, undo, persistence, root/online guards, original
SGF preservation and the existing Add pass action.

## Stone landing wobble — October 27, 2026

Animated placements on the macOS 3D board now finish with a 280 ms damped rock:
a roughly five-degree peak tilt at contact, a weaker return, then exact rest.
The tilt uses board coordinates so shell rotation cannot cancel the motion. The stone center,
natural landing offset, shell orientation and board markers stay fixed. A minute
height correction keeps the tilted surface above the board without adding a hop.
The effect follows both normal and slow space-station drops, does not repeat on
board refresh, and is skipped for instant placement, scrubbing, AI preview frames,
and Reduce Motion. Disabling motion mid-settle removes any residual tilt.

`Tests/MainRelease/StoneWobble.swift` samples rendered frames for contact timing,
small damped tilts, stable position/appearance, surface clearance, exact rest,
repeated updates and cancellation, on 9×9/19×19 boards and both drop speeds.
The existing ghost-glide and stone-arrival probes cover the placement handoff.

## Floating stone glide — October 27, 2026

The macOS 3D placement ghost glides between intersections in 80 ms with a gentle
slowdown, while the red landing dot snaps immediately. Redirecting the pointer
starts from the currently rendered position; repeated hover updates do not
restart the motion. The stone keeps its shell pattern and orientation while
hovering and after placement. Clicking mid-glide still plays at the pointer's
intersection, and the solid stone drops from the visible ghost position into
its natural landing offset. Leaving the board cancels the glide; Reduce Motion
uses instant positioning. Playback and moves without a hover retain their usual
arrival above the destination.

`Tests/MainRelease/GhostGlide.swift` samples rendered frames on 9×9 and 19×19
boards in both colors, checks reversals and cancellation, and exercises the real
3D click handler during motion. `FloatingGhost`, `StoneArrival`, `GhostStone`,
and `GhostOnline` cover the existing placement, cursor and online turn behavior.

## Automatic SGF saving — October 27, 2026

Finished local and online games save automatically with names such as
`Black Player vs White Player - 2026-10-27.sgf`. The first automatic save offers
a folder chooser, initially Documents/Quiet Go Games; Cancel accepts that default.
Settings → Saved Games changes the destination for new saves. A successful manual
Save SGF remembers its selected folder too. This is separate from the game-library
folder. Missing metadata uses Black, White, or Undated; Unicode names are retained
and filename components are sanitized and bounded.

Review edits, deletion, and undo automatically update one canonical `-review.sgf`
file per game. For finished games it is saved beside the original, retaining any
collision suffix from the original name. Existing reviews continue updating their
assigned location, including across relaunches; an explicit Save SGF assigns the
chosen file as the canonical review. Originals remain separate. Same-day games
with identical player names receive numbered filenames instead of overwriting.
The finished-game banner links to the saved original or reports a failure with a
retry button. Review-export failures retain the private recovery draft.

Collapsed variation trees now hide their saved-variation ghost stones in both 2D
and 3D. Expanding the tree restores the available continuations.

Validation: GameSaving checks actual saved SGFs, collisions, canonical review
updates, folder persistence, and save failures/retry. BackgroundReview checks
online completion saving; VariationGhosts checks collapse/expand and real clicks
in both board views. All runtime probes use disposable save destinations.

## Focus lens and return to main line — October 27, 2026

The variation tree enlarges the selected row and nearby moves, smoothly reducing
node size and vertical spacing farther away. Horizontal lanes stay fixed, and
clicks, tooltips, context menus, and selection centering follow the same lens.
The selected tree node keeps its cyan ring and the path to it stays yellow.
On the board, saved variations use translucent ghost stones alone in both 2D and
3D; the cyan outlines around those ghosts have been removed. Clicking a ghost
still opens its saved continuation.

Command–Left returns from any variation, including nested variations, to the
main-line node where that variation originally branched. The tree toolbar offers
the same action. It leaves an already selected main-line node unchanged; Right
then continues along the main line. Control–Left/Right still switch alternatives.
Editable text fields keep their usual Command–Left behavior.

`ReviewTreeTests`, `ReviewNavigation.swift`, and `VariationTree.swift` cover nested
forks, comments/passes, branch preservation, actual keyboard/mouse events, and
lens centering/hit testing across long games.

## Dynamic score axis — October 27, 2026

The performance graph now labels estimated point lead on its vertical axis,
with zero centered and symmetric limits at the largest absolute valid score in
the game. Positive scores favor Black and negative scores favor White. The dashed
score line uses those actual values without the previous ±50-point clipping.
Win probability keeps its full-height 0–100% mapping and its 50% midpoint. Bounds
update with incoming analysis; an empty or all-zero series uses ±1 point.

## Continuous move-loss colors — October 27, 2026

Suggestion ranking and the blue best-move outline now follow KataGo's `order`
instead of raw winrate, which can favor barely explored outliers. Older caches
without order fall back to visit count. Fill colors continue to represent only
estimated point loss, regardless of winrate or visit count. Historical hints keep
their measured before/after loss and retain the engine's recommendation metadata.
`AIMovePresentationTests` and `PlayedMoveMarker` cover optimistic one-visit
outliers, legacy caches, preserved historical colors, and both board renderers.

Board candidate fills, played-move badges, recent-stone rings and graph mistake
markers now share a continuous color scale based on estimated points lost.
The ramp interpolates KaTrain's normal palette at 0 (green), 0.5 (lime),
1.5 (yellow), 3 (orange), 6 (red), and 12 (purple) points; larger losses stay
purple. Favorable estimates clamp to green, and invalid values use neutral gray.
Blue outlines identify the best suggestion; dashed borders identify the next
recorded move. Opaque, unlit badges keep the scale stable across board woods and room lighting; dark badges use white text. The AI panel includes a color
scale and marker key; the existing textual summary counts retain their grading
rules and no longer display discrete color swatches.

Palette and anchor references: https://github.com/sanderland/katrain/blob/master/katrain/gui/theme.py
and https://github.com/sanderland/katrain/blob/master/katrain/config.json.
The existing played-marker rendering probe covers intermediate losses, both
board views, blue outlines and the purple endpoint.

## Hover previews during continuous analysis — October 27, 2026

“Keep analyzing” now yields its running search when an uncached hover continuation
needs the engine. KataGo query priority does not interrupt an already running
search, so previously those previews could wait until they timed out. Completed
analysis stays available; continuous analysis resumes automatically after the
hover completes, fails, or is cancelled. Cached previews need no interruption.
The engine regression and `ContinuousAnalysis.swift` check request ordering,
periodic refreshes, numbered playback, automatic resumption, and unchanged history.

## Adjustable analysis panel — October 20, 2026

Drag the left edge of the variations/AI panel to set its width. The choice is
saved across launches and clamped to fit the current window; double-click the
edge to return to automatic sizing. The board's usable area follows the divider.
Black variation nodes have brighter, heavier outlines, and the recenter button
uses a bullseye symbol. `AnalysisPanelResize.swift` checks actual drag events,
persistence, width limits, automatic reset, and unchanged game state.

## Reuse analysis when reviewing variations — October 20, 2026

Opening or extending a review variation now reuses saved results from the original
game and the previously active line. Every candidate position is checked against
the selected line's full move history, setup, rules, and komi before publication;
engine/model/config compatibility remains required. Matching positions retain the
deepest saved result, while changed positions still receive fresh analysis. The
merged result is saved under the variation's own key for subsequent launches.
`KataGoEngineTests` covers shared prefixes, branch extension, restart, unchanged
original-line results, and rejection of incompatible settings.

## Readable analysis and text size — October 20, 2026

Analysis, settings, and game-panel text now use a larger shared type hierarchy.
Settings has a persistent **Text size** slider (100–160%); text also grows with
window width, up to another 40%. The current position's point lead and win
probability appear above the graph in bold 32-point numerals before scaling,
with the leading color explicitly labeled. The two metrics stack when needed.
Chart labels scale too, and the move-quality table can scroll horizontally in
narrow panels. `Tests/MainRelease/ReadableAnalysis.swift` checks rendered values,
labels, their size hierarchy, narrow layouts, and preference persistence.

## Opening games and navigating variations — October 19, 2026

Opening an SGF or selecting a library game pauses at the final position of its
main line. Saved review edits are retained, but their old branch selection does
not redirect the newly opened game. Relaunching still restores the exact last
position and branch.

Left/Right move backward/forward along the selected line, including when the
variations panel has focus. Returning through a fork follows that same line.
Control–Left/Right select the previous/next alternative at the nearest fork;
Control-click on the playback arrows does the same. Shift–Left/Right or
Shift-click still move ten moves. The tree's explicit branch buttons remain
available, and Up/Down in the tree visit parent/child nodes, including comments.
The path already taken is yellow up to the current node, which keeps its blue ring.

`OpenMainLine.swift` covers file/library opening and saved drafts;
`ReviewNavigation.swift` sends real keyboard events to both the board shortcuts
and the focused tree, checking branch retention and explicit branch changes.

## Restore the last board at launch — October 19, 2026

Local Play and Review save their current game and position after navigation settles
and flush the latest position synchronously when quitting. Review restoration
includes the selected branch, edits, setup stones, rules, and captures, and opens
paused. The saved SGF is independent of the original file, so moved files and
unavailable folders do not prevent restoration. A deliberately blank board stays
blank. Missing or invalid saved state falls back to a blank board.

The games folder loads separately at startup and never selects its first game or
replaces the restored board. Existing online startup behavior remains separate.
The first launch after upgrading may be blank because older versions did not save
an exact board position. Subsequent local/review navigation is saved automatically.

New stones now receive their complete starting pose before entering the rendered
scene. An enclosing animation transaction cannot move them from the scene origin;
only the explicit drop above the destination intersection animates.
`Tests/MainRelease/LaunchPosition.swift` checks restoration across fresh app models,
library loading, edited branches, removed source files, local games, and invalid
state. `StoneArrival.swift` measures every frame of the drop under an enclosing
animation transaction and reproduces the old origin-to-intersection flicker.

## AI camera reframing — October 19, 2026

Toggling AI eases the 3D optical center and camera field of view together over
0.75 seconds. Reversing the toggle starts from the current framing; the scene and
manual orbit/pan settings stay intact. Reduce Motion uses an immediate transition.
`AnalysisReframing.swift` samples real window projections and lens values through
both directions and rapid reversal.

## Territory contrast — October 19, 2026

Settled territory now reaches 50% shading opacity (previously 24%) in both 2D
and 3D. Confidence still controls its strength. The regional evidence threshold,
soft edges, and stone shadows remain in place.

## Review display refinements — October 19, 2026

The active variation stays at the vertical midpoint of the tree, including the
first and final positions. Advancing one move shifts the tree by one row. Manual
scrolling remains untouched by redraws; selecting another move resumes tracking.

Ownership regions now require stronger evidence (ownership magnitude minus search
disagreement above 0.65) and support from at least two neighboring intersections
of the same color. An isolated strongly owned point surrounded by weak influence
no longer creates a territory patch. Both board views share feathered boundaries
and lighter shading. The 3D overlay receives lighting and stone shadows.

Analysis badges and numbers do not cast shadows. During a stone's placement
animation, values stay hidden and return once all placements finish; new analysis
reports cannot reveal them mid-flight. Turning AI off keeps them cleared.

The camera regression now checks visible centering, deliberate pan, stable repeated
updates, and unchanged physics bodies across board sizes. The capture regression
allows natural overflow while checking nearby containment, floor support, capture
counts, and removal on rewind. Ownership tests cover thresholding, regional
support, and feathering; Release probes check rendered shadows, centered tree
navigation and picking, and annotation visibility through normal and slow landings.

## Stable hover previews and continuous analysis — October 19, 2026

Hover preview captions reserve a stable status row above the playback controls, so
the 3D board no longer shifts or changes scale when a hypothetical stone lands.
Each preview stone and its number are committed together without implicit animation;
earlier numbers remain attached as the continuation advances or AI results refresh.
The dotted ring around the next recorded move now matches that move's actual stone
color in both 2D and 3D, including games whose first recorded move is White.

**Ownership & dead stones** is visible by default in AI Review and can be toggled
off in the AI panel. Translucent black/white regions show expected ownership,
including beneath occupied points. Groups strongly expected to be lost fade and
receive an X whose size and opacity increase with the evidence. The overlay uses
KataGo's side-to-move ownership and, when available, search disagreement; it does
not claim a calibrated death probability. Neutral ownership is not marked dead,
and every stone in a connected group uses its weakest evidence. The overlay hides
during hover continuations, scrubbing, scoring, and when AI is unavailable. It
never changes game history, captures, or scoring decisions. Ownership data is now
retained in the analysis cache; older caches can acquire it without losing depth.

In Review, the AI panel now includes **Keep analyzing**. It continuously deepens the
selected position and shows its visit count, follows move/variation navigation, and
pauses during playback or scrubbing. Turning it off retains the deepest results and
resumes ordinary analysis. Opening another game, leaving Review, or disabling AI
clears the toggle. Hover previews retain priority over this search. Results stream
every quarter second and use the existing persistent cache; late reports after
cancellation cannot overwrite results. A healthy search can continue beyond two
minutes, while a stalled engine still times out.

`Tests/MainRelease/HoverBoardStability.swift` measures rendered board corners and
camera projection through dwell, landing, playback, restoration, and status changes
at two window sizes with panels open and closed. `ContinuousAnalysis.swift` checks
native toggle clicks, the visible depth count, navigation, cancellation, and mode
restrictions. Engine tests cover streaming, timeout renewal, stale replies, and cache
persistence; rendering tests check number retention and cleanup.
`OwnershipEstimateTests` and `Tests/MainRelease/OwnershipOverlay.swift` cover
perspective, connected groups, uncertainty, invalid/legacy data, shading beneath
occupied points, 2D/3D appearance, and the overlay lifecycle.

## SGF files, folders and sorting — October 19, 2026

“Load SGFs” and File → Open SGF Game or Folder accept either a single SGF or a
folder. Select a folder and click Open to load its games (including subfolders),
or navigate inside and select one SGF to review only that game. A single game
opens paused; an older folder scan cannot replace a newer selection. Settings’
Choose Folder continues to select the remembered collection folder.

The review library has a full-width “Sort by” menu: collection order, Black player
(A–Z), White player (A–Z), newest date and oldest date. Dates come from the SGF’s
recorded game date. Missing metadata sorts last, ties retain collection order,
and changing the sort preserves the current game and move. The choice is remembered.

`Tests/MainRelease/LibraryLoading.swift` checks the native picker configuration,
file and folder import, failed opens, overlapping imports, sort order and persistence,
review preservation, and visible controls at a 320-point sidebar width against the
compiled Release app using an isolated test identity with networking denied.

## Observe and Review — October 18, 2026

The Observe mode control opens the live-game browser on every click, including
when already selected. Review opens the game currently on the board and preserves
an existing review when clicked again. In Review, “Choose game…” reveals the
collection sidebar, where a game can be selected or another SGF folder loaded.
`Tests/MainRelease/ModeActions.swift` checks these mode-control clicks in the full
3D window (and in 2D with `MODE_ACTIONS_VIEW=2D`), using fake network transports
and an isolated application identity. The oversized 3D rendering view is bounded
for both drawing and hit testing so it cannot intercept the toolbar's clicks.

## Arrival in 3D — October 17, 2026

The upper-left controls are Settings, Full screen, and the 2D/3D toggle. In 3D,
a fourth viewfinder button glides back to the playing view over 1.1 seconds,
resetting orbit, pan and zoom without replaying arrival or changing the game. It replaces
the former red diagnostic button.

Every switch into 3D, and each environment change while in 3D, opens with a view
composed for that setting, holds it for one second, then takes a broad seven-second sideways survey before gently descending to a playing
position over five seconds. Each environment has its own survey direction; the thirteen-second
sequence turns through 37–57 degrees, depending on the room, and eases position, orientation and lens together without a final snap. Recentring has no opening pause. The seat
accounts for the board's wooden margins; the existing viewport fitting preserves
readability in narrow windows. The 3D viewport centers the seated board in the
unobscured play area, accounting for both the game sidebar and analysis panel
instead of applying a fixed leftward offset. Drag, pan and zoom remain available after arrival.
Entering 3D again returns to the seated position, regardless of the previous orbit.
The playing view is now 12.5% closer and pitched about 62° toward the board
(previously 41°), enlarging the grid and reducing near/far perspective distortion.

Clicking anywhere in the game window during arrival jumps directly to the seat.
That press, drag and release are consumed so the skip cannot place a stone or
activate an overlay control. Reduce Motion bypasses both camera animations. Leaving 3D cancels
the clock; board, analysis and settings refreshes cannot reset an ongoing descent.
Changing the environment during arrival replaces the old path with the new setting's opening.

Each opening uses an explicit level horizon. Rotation now interpolates from that
composed opening to the exact final camera orientation on the same eased clock as
translation and zoom, avoiding accumulated roll and a last-frame rotational snap.
Continuity checks compare projected board corners immediately before and after
handoff across every environment and board size, including skipped-frame playback.

The Japanese garden and Moon use dedicated 4096×4096 color and normal scans
around the board, replacing enlarged panorama pixels. World-fixed planar UVs
keep their scale stable during camera movement; detail blends into the distant
panorama between radii 55 and 125. The Moon material desaturates a terrestrial
rock-and-soil scan as a visual analogue for regolith. The cave bedrock and monastery
planks also use 4K maps. Mipmaps and 16× anisotropic filtering preserve oblique detail.
CC0 sources and download hashes are recorded in
`SGFPlayerClean/Assets/Environments/environment-quality-sources.json`.

Yūgen-no-ma now has a flat, rectangular pale blue-green rug with its own 4K
carpet detail, surrounded by straight, physically sized tatami and dark woven
borders. These edges are geometry rather than a radial projection of the room
photograph. The existing 3K tatami weave is shared with the garden room.
The Nihon Ki-in room photographs linked in the source record inform the layout.

The visible cave lamp stays on its low stalagmite within the seated frame. Its
separate warm light is elevated and aimed at the playing surface so every board
quadrant receives highlights and shadows while the distant cave stays dark.
The flame has an anchored wick and a visibly bending, breathing silhouette;
its motion follows the flicker switch and Reduce Motion. Brightness variations
remain subtle. `Tests/MainRelease/CaveGardenLighting.swift` checks actual flame
pixel changes, stopped motion, shadows across all four board quadrants and
light-responsive gravel relief. `PlayingEnvironments.swift` checks live playback
and the flicker toggle.

The Japanese garden has loose pale 4K gravel, physically raised rake ridges,
two partially buried scanned stones and six sparse Japanese maple leaf cutouts.
Rake normals and shadows use the actual garden sun. The ground crests meet the
board feet; the grooves sweep gently around the left stone. CC0 scan provenance
and generated-leaf details are in `Assets/Environments/zen-garden-sources.json`.
The monastery's dry floor has chipped board edges, irregular recessed joints,
fine scrapes and deeper gouges with pale worn lips; roughness stays above 0.84.
`Tests/Preview/EnvironmentQualityPreview.swift` renders all eleven environments.

Beneath the tree now uses a dedicated 4096×4096 forest-floor color and normal
scan at the seated position, with actual fallen leaves, moss and twigs. Its
world-fixed detail blends into the distant panorama between radii 55 and 125;
the low-resolution panorama no longer supplies the foreground's leaf shapes.
Nearby vegetation uses four scanned fern meshes sharing 2K color, normal,
roughness and cutout-opacity maps, with varied size and orientation. The plants
remain grounded, batched and shadow-casting. CC0 sources and hashes are in
`SGFPlayerClean/Assets/Environments/woodland-quality-sources.json`.
`Tests/Preview/BakeWoodlandFerns.swift` converts the source meshes and opacity;
`WoodlandQualityPreview.swift` renders opening, survey and final seated views.
`Tests/MainRelease/WoodlandQuality.swift` checks the bundled assets, leaf cutouts
and compiled floor shader; `WoodlandShadows.swift` verifies visible ground shadows.

The lamplit cave now uses subdued ivory, ochre, rust and cool gray mineral colors
in a revised panorama inspired by Lechuguilla. Its nearby floor has scanned
water-worn bedrock with cracks and mineral inclusions, independently mapped color,
normals and roughness. The lamp rests on a tapered stalagmite, with an irregular flared foot,
flowstone ribs, muted calcite layers, and a narrow worn crown. Its low foot uses
the floor's exact texture projection, tint and roughness before blending into
calcite. Cave fill and photographic background illumination are subdued,
especially on the right, leaving the oil lamp as the primary light. Sources and the image-generation prompt are in
`SGFPlayerClean/Assets/Environments/cave-minerals-sources.json`.
`Tests/Preview/CaveMineralsPreview.swift` checks the stalagmite, lamp footing,
texture loading and visible GPU rendering at opening, survey and seated positions.

The monastery has a dedicated dark timber floor: individually laid, batched
horizontal planks with varied widths, narrow joints and staggered ends. Scanned
wood grain follows each plank, with a dry matte finish and uneven abraded
roughness. Its surrounding panorama is also wood throughout. Two softly stuffed
indigo zabuton face each other across the board, with sewn rims, cloth detail and
slightly compressed centers; they remain fixed on the floor during camera moves.
The saved `tatami` environment identifier is retained for preference compatibility.
References, texture provenance, and the built-in image-generation prompt are in
`SGFPlayerClean/Assets/Environments/monastery-floor-sources.json`.
`Tests/Preview/MonasteryPreview.swift` renders arrival, seated and wider views.

Validation: `CameraArrivalTests` checks all seven environments and 9/13/19 boards,
descent clearance, stationary scenery, update isolation, skipping and Reduce Motion.
`Tests/MainRelease/CameraArrival.swift` checks the actual view lifecycle, native
click interception, playing-view framing, manual controls and timer cleanup.
`Tests/Preview/CameraArrivalPreview.swift` renders five points along each arrival.

## Matching 3D bowls and wood — October 17, 2026

`GoEquipment3D` builds two hollow, turned wooden bowls with rounded rims and
individual black or white stones. A shared walnut material supplies grain only;
SceneKit lights the bowl and lid surfaces as the camera moves. The supply piles
are packed once against the interior and other stones, avoiding an additional
live physics workload. They are decorative supplies; capture counts and physics
remain with the lids. Rebuilding lids or resizing the board retains exactly one
pair of bowls and reapplies the matching material.

`Tests/Preview/GoEquipmentPreview.swift` renders the equipment and exports a
self-contained `GoEquipment.scn`. `Tests/MainRelease/GoEquipment.swift` validates
the materials, supply colors, lifecycle and model export against the Release app.

## Open tatami 3D setting — October 17, 2026

The 3D board now sits on an open tatami floor using the same woven texture and
physical texture scale as the 2D view. Dark fabric borders separate 90 × 180 cm
mats, and the floor fades into a muted background at a distance. The board,
capture lids and floor share fixed world coordinates; orbiting, translating and
zooming move the camera. The capture lids rest at floor height, and the camera
stays above the floor even when panned at close zoom. The floor supports spilled capture stones without changing board picking.

Drag to rotate, Shift-drag to pan, and scroll (or Control-Shift-drag) to zoom.
The existing viewport preferences retain these changes. Tall viewports show the
floor to their full height while preserving the board's previous framing.

Validation: `CaptureLidTests` covers capture physics and camera transforms;
`Tests/MainRelease/OpenTatami.swift` checks the bundled texture, rendered camera
poses, board picking, resizing, actual gesture bindings, pan direction, saved
viewport and tall-window coverage against the Release build with networking denied.

## Curved capture lids — October 17, 2026

The 3D lids use a shallow, rounded dish with the same mesh for the visible wood
and static collisions. Captured stones have size-matched flattened collision
shapes, settle against the curved interior and rounded rim, and start near
supported positions when loading a large pile. A full lid can naturally spill
stones onto the tatami; the floor and board catch them. Capture counts include
spilled stones, and rewind/reset removes them too. Camera changes leave the
physics world fixed. The 2D rendering and global lighting are unchanged by this
physics update.

`CaptureLidTests` checks sliding down the inner slope, contact with the visible
surface, landing on the tatami and board, large piles across board sizes and
camera changes, and capture/rewind/reset behavior.

## Quiet review after playing — October 17, 2026

Local and online games now prepare an AI review in the background. All evaluations,
hints, hover continuations and mistake navigation remain hidden until the result is
final. Confirming a local score or receiving an online final result opens the entire
game in Review automatically, retaining its analysis, player names and result. Online
phase-only completion fetches the final history before opening Review. The completed
game room and chat panel stay open so players can exchange thanks while reviewing. Chat is docked beneath the review
controls so it does not cover Save SGF or the analysis panel.
Close game chat, choose another game, or change modes to leave that room. Scoring,
resuming play, disconnects and observed games do not trigger an early reveal.

Settings includes **Analyze quietly during play** and **Pause background analysis on
battery**, both enabled by default. macOS Low Power Mode, elevated thermal state,
memory pressure, high CPU usage and delayed interface callbacks pause automatic
analysis. Battery saving prevents even loading the AI model until work is allowed.
Disabling realtime analysis still opens Review after the game; cached results remain
readable while automatic computation is paused.

The adaptive worker covers positions before progressively deepening them beyond the
old 500-visit ceiling. It submits one search at a time, limits searches to 0.5–12 seconds,
and rests for at least the search duration (three times as long under moderate load).
KataGo runs at background priority with one search thread and a small inference batch.
Actual search termination, stale-response fencing and deeper-result retention protect
against resource pressure, mode changes, undo, failed searches and interrupted upgrades.
These are conservative resource limits, not a guarantee of zero performance impact.

Validation fixtures: `Tests/Networking/KataGoEngineTests.swift` and
`Tests/MainRelease/BackgroundReview.swift`; the latter exercises the compiled Release
app with fake transports and an isolated analysis engine/cache.

## Collapsible settings — October 18, 2026

All six settings sections have full-width chevron headers and remember their
expanded state. Initially only 3D environment is open. The upper-left glass panel
fits the visible content and scrolls when it exceeds the window height; the rest
of the scene stays undimmed during environment changes. Clicking outside still
closes settings. Disclosure animations respect Reduce Motion.

`Tests/MainRelease/CollapsibleSettings.swift` exercises the rendered section
buttons, saved expansion state, panel height, exposed background pixels, and
scrolling after window resizing against the Release app.

## Current working copy

Keep `/Users/Dave/SGFPlayerClean` as the single active source checkout, on `main`.
Run the installed application at `/Users/Dave/Applications/SGFPlayerClean.app`.
The native Quiet Go screensaver is built and bundled with this app; it no longer
needs a separate prototype checkout. See `Screensaver/README.md` for its settings.

The obsolete SGFPlayer project, phase-1.3 backup, screensaver prototype and review
checkout were retired during the October 16 cleanup. Verified source archives and
a Git bundle preserving all local branches are under
`~/Documents/SGF PLayer/Source Archives`. Previous application/rollback backups stay
under `~/Documents/SGF PLayer/Main App Update`. None of those archives is required
to build or run the current app. See `Documentation/Source-cleanup-2026-10-16.md`.

## Lobby filtering and acceptance — October 16, 2026

Lobby speed filtering recognizes both OGS speed-tag locations. Its fallback now
matches [OGS's classification](https://github.com/online-go/online-go.com/blob/main/src/components/TimeControl/util.ts):
under 10 seconds per move is Blitz, 10 through 3600 is Live, and zero (untimed)
or above 3600 is Correspondence. Unknown tags fall back to the time estimate.

Checking Ineligible reveals rank-restricted challenges with a disabled, red-outlined
LOCKED button and the required rank. Eligible challenges retain green ACCEPT;
your own challenges retain yellow CANCEL. Acceptance shows progress, prevents
duplicate clicks, preserves the board on failure, and presents an alert naming
the signed-in account and OGS's rejection reason when supplied. A forbidden
response does not remove the challenge; a confirmed missing challenge does.

The reported CHJ listing was revealed by Ineligible, and its acceptance attempts
received HTTP 403. The browser and app were signed into different accounts, so
this was not evidence that the speed bug caused that particular disappearance.
Its old rejection body was not retained; the precise server reason is unknown.
The CHJ clock used in regression tests is reconstructed, not a captured payload.

Validation: 282 unit tests plus the network-denied Modes and LobbyControls probes
passed against the signed Release build. The probes check all five speed filters,
visible rank restrictions, actual LOCKED/ACCEPT clicks, duplicate-click suppression,
and the rejection alert. No live challenge was accepted during verification.

## Main app update — October 15, 2026

The reviewed changes are promoted to the regular `SGFPlayerClean.app`, installed in
`~/Applications`, with the original `com.davemarvit.SGFPlayerClean` identity and existing
preferences. Login persistence and direct SGF opening now use the same paths as the
tested review app. Main and review logins remain separate; sign in once in the main app
if needed. The retired OGS and offline review apps are archived in the local backup;
the regular app is now the only active installation.

The normal optimized Release build passed 227 unit tests and seven network-denied
runtime/UI suites covering private persistent login, restart/tab restoration,
mode switching and lobby filters, play controls, scoring, 2D/3D local scoring, and sound.
The user confirmed live play, scoring, restart recovery, and undo from both accounts
including captures. A local pre-update backup preserves the original source (including
uncommitted work) and app data. Release/rollback records are beside the review checkout
in `Main App Update`; they are local and contain no data intended for GitHub.

Build without installing: `python3 Tests/MainRelease/build_release.py --output /path/to/output`.
Check that build with `Tests/OGSReview/check_review.py --main-build-info /path/to/output/build-info.json`;
pass a specific fixture such as `StartupAndResult.swift`. Probes use a disposable identity
and block networking; the main app executable is not launched by these checks.

## AI cache and hover review update

AI analysis now survives toggling AI and is saved periodically and on normal quit.
Compatible retired-review caches are imported from verified copies; engine/model/
configuration changes cannot silently reuse incompatible results. In Review, pause
for half a second over an analyzed candidate to preview up to twelve numbered
continuation moves in 2D or 3D. Moving away restores the actual position; previews
do not change game history, prisoners, lids or sound.

Hover now also computes missing continuations for any legal intersection after the
same dwell. A waiting status appears while KataGo works. Completed continuations
are saved beside the game's AI cache and reused after restart; moving away cancels
unfinished work. Focused results do not alter the whole-game evaluation graph.
This addition passed 241 unit tests, three offline Release UI probes and 15 real
KataGo smoke queries. Original backups and SGFs remain intact.

Previous cache/preview increment: 236 unit tests, three migration tests, and eight network-denied
Release probes passed, including reuse of actual saved analysis without starting
KataGo. The original backup is retained, with a separate backup for this update.
For main-checkout probes, pass `--protection-profile /path/to/network-and-file-protection.sb`
in addition to `--main-build-info` so the working app and its data remain protected.

## Review changes — October 15, 2026

The selected mode now survives restart; the OGS review app defaults to Play Online
instead of forcing Observe. Resignation, timeout and other non-point endings no
longer show estimated territory, dead-stone shading or a cached numeric score.
Normal scoring and scored results retain their markers.

Scoring tables now hide components that do not apply to the game's rules,
respecting explicit OGS scoring overrides. Handicap adjustments are labeled
“Handicap compensation” and omitted when zero. Server totals are unchanged.

The Play Online lobby now processes challenge deletions and starts consistently,
removes confirmed accepted challenges immediately, and requests a fresh subscription
when reopened. Challenge IDs are kept separate from game IDs; late deleted rows
are suppressed instead of reappearing after a finished game.

The AI overlay can now extend further over the lids, with a leftward 3D viewport
adjustment to keep the larger board clear. Spoken countdowns use the updated clock
value and round upward, matching OGS: “3” begins near three seconds remaining,
not at 3.9. Displayed time and server time allowances are unchanged.

Observe now has one “Select a Game” heading and no duplicate account controls.
Reconnect appears beneath the username only when the signed-in connection is down.
The picker refreshes every ten seconds while visible, preserving loaded depth and
cached clock details. AI can overlap the capture lids to give the board more room;
the playable board and playback controls stay clear.

The shared app target now includes a Go-board icon with black and white stones, packaged
at all ten standard macOS icon sizes. Only the separate OGS review app was installed;
the working app remains untouched. Artwork and generation prompts are in `Design/AppIcon`.

The 3D workspace now uses the same dark backdrop as the SceneKit scene, including viewport
margins and analysis/sidebar areas; tatami remains exclusive to 2D. A speaker beside the
account controls mutes all app audio on click and opens a master-volume popover on hold or
right-click. Master volume preserves the stone/voice balance and persists independently
in each app's settings. Mute immediately stops active clips and cancels pending 3D sounds.
This follow-up passed 215 unit tests plus four network-denied UI/audio suites.

Observe follow-up: removed the duplicate signed-in label; visible list rows now read full
time controls through separate, bounded REST requests because the actual live-list payload
contains only an estimated `time_per_move`. Game-over messages include the winner's color.
AI has a persistent right-hand column in 2D and 3D, with less empty space to the left of the
board and room below the graph. On wide windows the game panel gets its own space; on
narrower windows it may cover the AI column until dismissed. AI never moves below the board.
The 3D viewport fits the board and capture lids without rewriting camera preferences.
This follow-up passed 215 unit tests and nine network-denied UI suites.


The overnight review adds guarded online game actions, adjacent Pass/Resign controls,
game-specific resignation confirmation, a live-position return button, visible connection
and export errors, and preservation of the active panel during disconnection. New-game
transitions clear stale clocks/players/undo requests. Chat keeps unsent disconnected drafts;
login submission and challenge forms fence repeated or stale callbacks. Challenge settings
are validated before submission; forbidden cancellation no longer hides an open challenge.
Replacing an existing local game requires confirmation. Leaving 3D detaches its renderer
and interaction closure. Rendering frequency and the 5 fps slider preview are unchanged.
Verification includes 211 passing unit tests, 16 UI/integration runs, 14 real KataGo
queries, and the localhost WebSocket test. See [the overnight review record](Documentation/Review-2026-10-15.md) for test coverage,
remaining live acceptance checks, and the separate review-app launch location.

Observe now loads a continuous scrolling list in bounded batches, requests server rank
ordering and sorts loaded games by the stronger player's rank. Rows show player ranks,
move count (including passes), board size and time control; internal game IDs and page
buttons are omitted. Missing metadata is identified, never guessed. Counts are snapshots
at fetch time; Refresh starts a fresh list. Duplicate IDs merge, timeouts retain prior
rows, retry is explicit, and refresh/logout fence late replies. Optional snapshot parsing also supports the
[OGS GameList](https://github.com/online-go/online-go.com/blob/main/src/components/GameList/GameList.tsx)
and rating conversion follows its `rank_utils.ts`.
Challenge Cancel now has a visible standard button and Escape shortcut; Cancel remains
left, green Issue right, following macOS conventions. The upper 2D lid moves down only,
with its visible top halfway between the board edge and grid (accounting for asset inset).
Offline checks: 202 unit tests, plus `ObserveList.swift` scrolls a real SwiftUI list through
20+20+13 simulated games and verifies metadata, end-of-list stopping and action order.
The existing modes/lobby integration checks also pass. No live game was initiated.

Dave authorized Play Online in the isolated OGS review app and has two accounts for
controlled live tests. This app is no longer restricted to observation. The original
working app, checkout, and settings must still remain untouched. Build with
`python3 Tests/OfflineReview/build_review.py --ogs-review` (`--ogs-observer` remains
an alias). The same separate bundle ID, session file, and native file-write guard remain.
Only the OGS review package was rebuilt; the installed offline review was not changed.

The shared UI now has four modes in one top control: Play Online (existing challenge
lobby and its size/speed/ranked/eligibility filters), Local Play, Observe, and Review.
Account username, socket status, and Log Out remain visible independently of mode.
Observe retains the live-game browser and its cancellable Browse games sheet. Play Online
enables challenge/game actions; Observe continues to block mutations, even for one's own game.

`AppModel.mode` controls the displayed activity; connection lifetime is separate. Moving
away from an online board unsubscribes that board without closing the socket or signing
out, retains a return-to-game ID, and fences late game updates. Local Play and Review
have separate in-memory board snapshots, including position, rules/komi, capture counts,
selection/source variation tree, and local scoring state. Selecting an SGF enters Review;
Review does not add moves. “Continue this position in Local Play” makes a local copy.
“Review this game” copies a local/online position into Review. These are session snapshots,
not new SGF exports or a promise to save unsaved local games across application restarts.

AI analysis is an independent, initially-off toggle. It is available for Local Play,
Review, and observing other players once game identity is known. It is disabled in Play
Online and whenever the signed-in account has a known ongoing game, across all modes.
Actual account participation is separate from the read-only interaction flag. Leaving a
board preserves ongoing-game tracking; finished-game events release it. Toggle/mode
changes cancel analysis sweeps and invalidate pending results, with permission checked
again inside the analysis loop. Local scoring temporarily disables AI as before.

Offline verification: 197 unit tests; `Tests/OGSReview/Modes.swift` exercises actual
AppModel transitions, challenge acceptance via fixture HTTP, AI permission, independent
boards, stale moves, unchanged socket/login, rendered username/controls, and restored
lobby filtering. `ObservationWindow.swift` clicks Cancel, Escape, manual Observe, and a
fixture game row in real SwiftUI windows. All app UI checks deny network and inject fake
transports where needed. No live moves or challenges were initiated by this work.
The next user test is a private/unranked game between the two accounts, with one account
in this review app and the other in the browser. Live play remains an acceptance test.

## Earlier continuation handoff — October 14, 2026

**The offline review and normal online-capable app use the same application sources and
Xcode target.** Continue development on
[`codex/ogs-connection-reliability`](https://github.com/davemarvit/SGFPlayerClean/tree/codex/ogs-connection-reliability)
in `/Users/Dave/Documents/SGF PLayer/SGFPlayerClean-review`.
The integration review is [draft PR #1](https://github.com/davemarvit/SGFPlayerClean/pull/1).
This branch contains the preserved local work as well as the subsequent repairs; do not
reconstruct changes from chat history or copy individual files back into the original checkout.

The initial completed local-scoring checkpoint is `0b54b7feb5749dd0cabff366418705a62edbc070`
(`Add local scoring review with dead groups and soft territory markers`). It was verified
on GitHub as well as locally. The packaged offline review identifies its source commit
in `../Offline Review/build-info.json`. Consult that file for the current packaged commit.
Subsequent shared formatting changes put the winner color in brackets, for example
“Alice [White] wins by 7 points”. Documentation-only commits do not require rebuilding the app.

The subsequent SGF playback repair retains the complete imported variation tree in
`SGFGame.sourceTree`; default playback follows its first-child main line. Nested OGS exports
previously stopped at their first subtree (one move in the reported 132-move game). Alternatives,
comments, markup, and unknown properties now remain available for future navigation/editing;
there is no variation-selection UI or SGF writer yet. The expanded automated suite has 180 tests.

Slider scrubbing now publishes completed board states in common run-loop modes, including
AppKit event tracking. Default-mode delivery previously left board rendering queued until
mouse-up while the directly observed 2D capture lids changed. Drag requests retain only the
latest target and preview at most 5 times per second (reduced for M1 rendering load); release commits the exact target.
Preview seeks are silent, avoid new 3D drop animations, and defer new analysis requests until
release. KataGo analysis is enabled only on the AI tab; opening an SGF selects Local.

Stone jitter now reconstructs missing layouts from the recorded move sequence instead of
re-seeding existing stones when a preceding display frame is absent. Arrow stepping, seeking,
and revisiting cached positions therefore agree. Collision processing has a stable order,
retains the existing local wake-up behavior, and invalidates changed history after the shared
prefix. A private replay engine builds layout frames without UI/audio/AI observers. Loading a
game also honors the saved jitter setting. This repair expands the unit suite to 185 tests;
an external-game app-model check verified the reported 92–93 transition and distant-stone stability.
The shared 2D/3D playback back/forward buttons now honor Shift-click for ten moves,
matching the existing keyboard shortcuts; an ordinary click still advances one move.

The offline package now installs to `~/Applications/SGF Player Offline Review.app`,
outside the privacy-protected Documents folder. Bundled examples and engine resources
therefore no longer require Documents access at startup. Local ad-hoc signing changes
the designated code requirement on rebuild, so earlier privacy consent may not carry
over; the packaging fix avoids this unnecessary access without changing TCC permissions.
User-selected protected libraries can still require permission. Reports and exported
samples remain in `../Offline Review`; test harnesses use its `build-info.json` app path.
Use the Applications copy instead of any older Documents copy. The existing signed app
can be copied there without rebuilding or resetting its separate review settings.

Dave confirmed the Applications launch no longer prompts for Documents access and the
offline AI interaction works. The next authorized stage is a **separate OGS observation
review**, prepared with `python3 Tests/OfflineReview/build_review.py --ogs-observer`.
Launch `~/Applications/SGF Player OGS Review.app` (blue banner); its bundle ID is
`com.davemarvit.SGFPlayerClean.ogs-review`. Login and direct game-link/ID observation
use the shared OGS client and reconciliation code. There is no challenge-accepting lobby
in this build. Client guards block challenge REST mutations and all socket actions except
authentication, subscriptions, game observation, and heartbeat/latency messages. Even a
game involving the logged-in account is treated as observation only. Game/chat input is
hidden or disabled, and AI stays unavailable during live games.

OGS review preferences and KataGo data are separate from both existing apps. HTTP and
WebSocket sessions share a private review cookie jar. After a verified login, OGS cookies
are saved to `~/Library/Application Support/com.davemarvit.SGFPlayerClean.ogs-review/SessionCookies.plist`
with owner-only access (0700 directory, 0600 file). Passwords and the config JWT are not
saved. Restart restores the cookies and asks OGS to validate the session; an expired or
revoked session requires signing in again. Log Out in the blue banner or observation
browser disconnects, clears identity and cookies, and deletes the saved session. A late
response cannot restore it. Temporary network failures retain the saved session.
This update needs one fresh login because earlier builds kept cookies only in memory.
Its native startup guard verifies the new bundle ID and denies
writes to known working-app and offline-review paths, while allowing networking. The
packaging probe checks a disposable protected sentinel and a loopback listener before
AppModel creation. It does not contact OGS. `Tests/OGSReview/check_review.py` checks
the compiled review policy and login/observation UI with all networking denied.
The 195-test suite includes mutation blocking, private cookie stores, persisted-session
restart/logout/expiry/permission checks using fake credentials, and game-link
validation. The real WebSocket loopback test can also compile the OGS-review transport
with `python3 Tests/Integration/run_loopback.py --ogs-review`.
Reports and launch instructions are in `../OGS Review`; the offline package remains
unchanged. Automated checks do not establish live OGS compatibility.

Dave has since confirmed live login and observation work. Clock fine-tuning is deferred
because the review and web displays now look close enough. He has a second OGS account
for future controlled gameplay tests; this package remains observation-only. Persistent
login is tested offline with fixture responses; a real quit/relaunch check remains for Dave.

The observation browser now has a Cancel button and Escape shortcut in its sheet;
neither action changes the observed game or dismisses the main window. The sidebar
does not receive a sheet-dismiss action. Live games load when the browser becomes
connected, with both player names/colors, board size, an Observe button per row,
Refresh, and Previous/Next controls (20 games per page). Direct game-link/ID entry
remains available. There is no periodic background list polling.

Discovery uses the read-only `gamelist/query` request and `size`/`results` response
documented by the [OGS observation browser](https://github.com/online-go/online-go.com/blob/5c88f56577cd21b6dd8ca9ec65fff4eeebb04d48/src/components/ObserveGamesComponent/ObserveGamesComponent.tsx#L224).
On our existing Socket.IO connection, the acknowledgement ID is encoded before the
JSON payload, following the [Socket.IO protocol](https://github.com/socketio/socket.io-protocol#acknowledgement).
Only this read-only action was added to the review allowlist. New requests supersede
older pages; disconnect/logout discard pending queries and rows. Queries time out
after 12 seconds with a retry message, and errors preserve the previously loaded page.
Offline fixture tests cover request framing, pagination, rows, timeout/error recovery,
and stale replies. The real-window test also clicks Cancel and a fixture game row,
and sends Escape while editing. Actual live list compatibility awaits Dave's test.

Dave's four byo-yomi screenshots show consistent values: review 4.6/2.6/8.4/1.3
seconds correspond to browser 5/3/9/2, with matching inactive clocks, period labels,
and capture counts. They do not establish behavior at expiration. No urgent clock
repair was indicated by these images; improving the last-period warning is deferred.

First live observation follow-up: Dave signed in, but clicking Observe hid the app window.
The process remained alive and its local log showed accepted game data. The review browser
had called SwiftUI's environment dismiss action from both its sidebar and sheet contexts;
from the sidebar that could close the main window. It now uses an explicit completion
callback supplied only by the sheet presenter. The default sidebar callback does nothing.
`python3 Tests/OGSReview/check_review.py ObservationWindow.swift` presses the actual buttons
in a SwiftUI WindowGroup under a network-deny sandbox, checking the main window survives
both paths and only the sheet closes. Test-check failures exit normally rather than trapping
and producing macOS crash dialogs. Rebuilt-app live observation still needs another user try;
no additional OGS connection was initiated during this repair.

Dave subsequently confirmed observation works, but reported the clocks looking 1.5–2 seconds
lower than the browser. His screenshot shows both clocks exactly one displayed second lower,
including the inactive player. `GameClockView` truncated fractional seconds; it now follows
[OGS's clock display rounding](https://github.com/online-go/online-go.com/blob/5c88f56577cd21b6dd8ca9ec65fff4eeebb04d48/src/components/Clock/Clock.tsx#L241)
(round up with the same 1 ms boundary tolerance). This affects main-time and byoyomi labels,
not the underlying time values or timeout decisions. Run
`python3 Tests/OGSReview/check_review.py ClockDisplay.swift` for fractional/boundary checks
and actual rendered clock labels. Exact live synchronization is not established by this fix.
Before enabling play, verify snapshot anchoring, pauses, and overtime transitions.
Server drift/latency fine-tuning is deferred at Dave's request. The current client still uses its
older expiration-based calculation, fixed reported latency, and decrementing timer;
it does not yet implement the web client's full timestamp/relative-latency calculation.
Keep this package observation-only while those behaviors remain unverified.

At Dave's request, clocks now show tenths below one minute in main time and each
byo-yomi period, including the secondary period label (for example `0:43.4` and
`+ 0:30.0 (5)`). At one minute or more, the existing minutes/seconds display remains.
Fractional positive values round up to the displayed tenth, keeping a positive remainder
from appearing as zero; the minute boundary is normalized. This is display precision,
not a change to timekeeping or a claim of tenth-second synchronization with OGS.

Changes included in both builds:

- OGS connection lifecycle, authentication, stale-event protection, move/undo/handicap
  reconciliation, and server-scoring display/action guards.
- KataGo process/cache reliability and rules, komi, handicap, and initial-player handling.
- Go rules and ko handling, soft red ko markers, and correct colors on reused 3D stones.
- Capture counts/lids, rewind/replay updates, 3D lid placement/physics, playback delay,
  and placement/capture audio.
- Local Pass controls and end-of-game local scoring: dead-group marking, neutral-region
  adjustment, soft black/white territory markers in 2D and 3D, rule-aware totals,
  confirmation/resumption, and named winner text.

`SGF_OFFLINE_REVIEW` supplies the separate bundle/settings/cache identity, mandatory network
and original-file protection, disabled OGS entry points, bundled examples, review banner and
score-example sheet, and review-specific startup/file-opening behavior. These are intentionally
review-only. Ordinary fixes above are shared; there is no second implementation to port later.
Local scoring applies to local games in either build. Live OGS scoring still follows the server's
scoring state and protocol; the local manual scoring session does not override a live result.

Validation at this checkpoint: 172 Swift tests, all six packaged sample games, the offline app
build/signature/network-block probe, and compiled-app UI checks for capture rewind, playback
audio, Pass, winner display, and local scoring passed. These checks use no live OGS connection.
The review's `../Offline Review/verification.json` records the results; the 325 protected
original source/settings/cache files matched their baseline. The test scripts and substantive
implementation notes are versioned here; generated app bundles and local reports are not
the source of truth.

The ordinary Debug app also compiled successfully from this checkpoint, without
`SGF_OFFLINE_REVIEW`, into `/private/tmp/sgf-normal-check-pyk3p6i_/DerivedData`.
It was not launched or installed as the working app, and its temporary Launch Services
registration was removed after compilation. The protected original files still matched.

**The original working app, original checkout, and GitHub `main` have not been upgraded.**
Keep them and their settings untouched. Do not launch an ordinary build, connect to live OGS,
merge this review, or replace the working app until Dave requests that next stage. Building
the ordinary target into a separate temporary DerivedData directory is safe; compilation alone
does not establish live OGS reliability.

Remaining acceptance work: first test login and observing an existing game in the separate
OGS review app. Later, arrange a separately requested playing session covering challenges,
reconnect, move/undo/handicap reconciliation, server scoring, and return to local playback.
Scoring requires manual life/death and neutral/seki agreement;
marks/results currently remain in memory and do not rewrite SGFs. Broader rules limitations
are documented below. Before eventual integration, compare any new original-checkout edits
against the preservation snapshot and integrate the complete review branch without losing them.
Update this handoff whenever the checkpoint, validation, constraints, or remaining work changes.

## Preserved baseline — October 14, 2026

GitHub `main` was at `c30c12e` when this review began. The local app had substantial uncommitted
changes, including KataGo integration, a new model, and two analysis views.

Those runtime changes and required resources are preserved in commit `4a290e4` on
[`codex/preserve-local-work-2026-10-14`](https://github.com/davemarvit/SGFPlayerClean/tree/codex/preserve-local-work-2026-10-14).
That snapshot built successfully before the connection refactor. It is a recovery point,
not a claim that live gameplay has passed acceptance testing.

A separately verified local archive includes the entire original working directory, Git history,
untracked files, logs, and local documentation. Its location is
`/Users/Dave/Documents/SGF PLayer/recovery/2026-10-14/SGFPlayerClean-before-refactor.tar.gz`.
The adjacent `backup-verification.json` records its SHA-256 and 994 verified files.
Logs, editor state, unrelated personal files, and duplicate assets were not added to the GitHub snapshot.

The original checkout at `/Users/Dave/SGFPlayerClean` remains on `main` with its pre-existing working changes.
Development is isolated in `/Users/Dave/Documents/SGF PLayer/SGFPlayerClean-review`.
Neither `main` nor the preservation branch should be used for ongoing refactoring.

## Networking architecture

`OGSClient` continues to own OGS message encoding, authentication flow, game rules, clocks,
and lobby policy. Socket lifecycle and HTTP reads delegate to independently testable components:

- `Services/Networking/OGSConnectionController.swift`: one connection attempt and receive loop,
  generation checks for stale callbacks, cancellable exponential retries (1–30 seconds), a
  15-second connection deadline, and WebSocket ping/pong liveness checks.
- `Services/Networking/OGSURLSessionSocket.swift`: the production URLSession adapter, including
  text/binary decoding and forwarding of close, receive, and send failures.
- `Services/Networking/OGSHTTPTransport.swift`: cancellable URLSession GET requests with
  main-queue completion and explicit HTTP status validation.
- `Services/Networking/OGSPaginatedReader.swift`: one complete lobby snapshot at a time,
  cancellation across every page, same-origin pagination limits, and cooldowns for HTTP 429/503.
- `Services/Networking/OGSJSONReader.swift`: latest-request-wins identity and game reads,
  completing cancelled callers once and discarding late responses.
- `Services/Networking/OGSSocketEvent.swift`: checked event-envelope decoding that preserves
  both array batches and dictionary updates without indexing a missing payload.

The controller serializes state and observer callbacks on the main queue. Intentional disconnect
cancels retry and heartbeat work. A new socket resets authentication/subscription/room flags so
the existing handshake can restore subscriptions. Send failures trigger recovery but never replay
game commands, whose server acceptance may be unknown. Authentication tokens are redacted from
outgoing diagnostic history.

A failed or malformed lobby page now discards the whole refresh; it cannot prune challenges
using a partial list. Polls cannot overlap, and a server `Retry-After` cooldown survives reconnects.
Lobby reads stop when entering a game or disconnecting. Replaced game reads and identity reads
cancel their previous tasks; logout also invalidates pending login/config responses. HTTP errors
cannot masquerade as successful JSON snapshots. Existing empty-lobby and 15-second grace-period
safeguards remain in place.

Queued socket updates carry connection/game generations, so they cannot restore authentication
after disconnect or apply scoring/clock data after changing games. Game packets are filtered
before updating the state-version counter. Challenge creation/acceptance validates HTTP status,
rejects overlapping POSTs, releases busy state on failure, and invalidates pending callbacks when
cancelled or disconnected. No mutation is automatically retried. Failed accepts only remove a
challenge on HTTP 404; cancellation, authentication errors, and timeouts leave the listing intact.
SGF downloads also validate HTTP status before passing bytes to the file loader.

The existing Socket.IO endpoint and outgoing game protocol are retained. Authentication
confirmation/ACK handling still needs live compatibility verification.
Game notifications now carry connection/game context through AppModel and chat queues; stale
notifications are rejected at consumption, including after switching away and back to the same game. Local tests do not establish live
OGS login, challenge, or gameplay compatibility.

## End-of-game scoring and UI

Scoring consumes standalone phase events, full removal lists, removal/revival deltas, seki-mode
updates, and acceptance events. Accepting sends the current server-derived marks/seki mode and
shows a pending state until a matching confirmation arrives. Mark edits and resume requests also
wait for server updates; a 15-second timeout releases pending controls without replaying actions.
Disconnecting, switching games, changing marks, or changing seki mode invalidates acceptance.
Resume sends only `game/removed_stones/reject`; it no longer also requests an undo.

The client and board reject scoring edits for spectators, disconnected sessions, finished games,
and historical board positions. Finished snapshots preserve omitted marks while respecting an
explicit empty list. Full REST/socket snapshots update scoring only after their board history
passes reconciliation. Standalone scoring events do not require a new move. `score_stones` is
not interpreted as dead-stone coordinates.

The panel displays OGS-supplied totals and components (territory, stones, prisoners, komi,
handicap), without recalculating totals or inventing missing components. Valid server scoring
positions take precedence over the local overlay in both board views. The local flood fill is
only an estimate; it is not a complete Japanese/seki/rules-aware scoring engine. Manual neutral
point editing and a seki-mode toggle remain unimplemented; the server's seki mode is displayed
and preserved on acceptance. Historical boards omit end-position overlays, and candidate-move
hints are hidden during scoring. Dismissing the result overlay no longer destroys result state.
Spectator outcomes and draws are not presented as personal losses.

The protocol fixtures follow the [OGS real-time API](https://ogs.readme.io/docs/real-time-api)
and the official Goban client at commit `d7eb38eb4e9e1c48ace12befb98d9f3c821ec2f3`:
[server events](https://github.com/online-go/goban/blob/d7eb38eb4e9e1c48ace12befb98d9f3c821ec2f3/src/engine/protocol/ServerToClient.ts),
[scoring commands](https://github.com/online-go/goban/blob/d7eb38eb4e9e1c48ace12befb98d9f3c821ec2f3/src/Goban/OGSConnectivity.ts).
These are source/fixture checks, not live compatibility testing.

Render the actual SwiftUI component with sample states, without starting the app or contacting OGS:

```sh
python3 Tests/Preview/render_scoring.py /private/tmp/sgfplayer-scoring-preview.png
```

## Authentication, move reconciliation, and KataGo

Login now completes only after the configuration read returns a positive account ID and a
nonempty JWT. A new login disconnects the previous account's socket and clears identity; logout
or a superseding request invalidates pending credential reads. Anonymous/unauthorized responses
clear credentials, while transient refresh failures preserve the existing identity. Socket auth
waits for the namespace handshake and sends once per connection, with a visible confirmation
timeout instead of retrying credentials every two seconds. The existing legacy readiness events
and wire framing are retained pending live compatibility verification.

Move reconciliation compares sequence number, color, and coordinates against the complete move
history, including optimistic moves and passes. Duplicate events do not append moves, toggle
turns, or add captures twice. Gaps/conflicts trigger a coalesced snapshot read, never a move replay.
Snapshots crossing a newer move are discarded and refreshed; queued recovery snapshots are
checked again before consumption. New moves received while reviewing history are applied to the
live position and preserve the viewed index. Disconnected, spectator, and historical-board input
cannot apply optimistic online moves or passes.

Full snapshots distinguish state revisions from move numbers. A shorter or conflicting history
without a newer revision triggers a fresh read; it is not automatically treated as undo. Undo
acceptance also requests the complete state, covering numeric, string, and object event payloads.
Moves, passes, score edits, and undo requests are blocked during reconciliation. Fixed handicap
setup and free handicap placement have separate turn handling; setup stones do not add move
numbers or captures. Unsupported rectangular boards, truncated histories, and edited moves are
rejected before altering the board. Snapshot metadata, clocks, and scoring are applied only after
the history is accepted.

KataGo process callbacks are fenced by generation, both output readers own their pipe lifetime,
and pending restarts are cancellable. Unique request IDs reject results from another game,
replaced process, superseded same-turn request, or unexpected turn. Input writes run on a serial
queue instead of blocking the UI. Analysis requests validate coordinates and coalesce pending
work; game switches cancel the background sweep. Cache snapshots are captured on the main queue
and written atomically on a serial queue, using fixed-length hashed filenames. Versioned `v3-`
caches leave older caches untouched; the first analysis after this update may need recomputation.
All cached positions are checked against the loaded game's history and settings before display,
including after undo. Position fingerprints prevent reuse when a requested position differs.
The analysis configuration explicitly uses `SIDETOMOVE`, matching the UI, and move-quality
comparisons handle consecutive moves by the same color.

SGF and OGS rules, komi (including zero), and initial player now reach every analysis request.
OGS Chinese rules use KataGo's `chinese-ogs` preset; explicit OGS handicap compensation settings
are passed through. Changing settings invalidates old results and pending replies. Unsupported
rules or invalid komi pause analysis with an explanation. Missing metadata keeps the existing
Chinese/6.5 defaults but labels that assumption in the analysis panel.

These checks follow KataGo's official [analysis protocol](https://github.com/lightvector/KataGo/blob/master/docs/Analysis_Engine.md)
and [configuration example](https://github.com/lightvector/KataGo/blob/master/cpp/configs/analysis_example.cfg).
The unit tests use a temporary Python subprocess and fixture model file; they do not run the
installed KataGo executable or touch the working app's analysis caches. A separate opt-in offline
smoke test now exercises the installed Metal engine using the review model, production config,
and a temporary directory for logs and engine data. On this machine, KataGo 1.16.4 completed 14
queries across eight rule presets, ko, self-capture, and handicap positions. It excludes the ko
recapture from candidate moves but tolerates illegal moves in supplied history; it must not be
used as the app's move-legality validator.

Query errors, warnings, and two-minute timeouts are visible while KataGo remains running. Failed
positions are not automatically resubmitted until retry or a changed context; stale replies are
ignored. Invalid numeric results are discarded. Background sweeps wait for pending work instead
of filling the subprocess queue. Cached analyses retain rules warnings, and missing caches still
update the metadata notice. Explicit custom legality/scoring settings that differ from a preset
pause analysis instead of silently using that preset.

The final-score header includes the winning name, color, and difference between OGS totals
(for example, “Alice [White] wins by 6.5 points”). Equal totals show “Draw”; missing numeric scores
do not produce a fabricated margin.

### Remaining investigation boundaries

- Socket authentication still accepts legacy readiness events after credentials are sent;
  replacing that with explicit ACK verification requires confirming the deployed protocol.
  Socket.IO ACK framing and the existing move-command sequence field remain unchanged.
- Undo, handicap, and reconnect behavior still needs combined live acceptance testing before
  release. Ambiguous snapshot conflicts require a successful fresh read; recovery failures leave
  game input blocked with an error instead of guessing the position. Rectangular boards,
  truncated histories, and edited online moves remain unsupported.
- KataGo cache loading and validation remain synchronous. Rules presets are the engine's
  approximations of their respective rule sets, not a replacement for OGS's final score.
- The installed engine passed a small offline Metal/model smoke test, not prolonged analysis or
  performance testing. Cache loading remains synchronous, and caches do not yet distinguish model
  or executable replacements. Full app interaction and live OGS acceptance remain deferred.

## Local playback repairs

Local snapshots retain the viewed move index, initial player, state version, and capture counts.
Returning from online mode reconstructs that saved position and keeps the remaining moves
available for playback. Clearing the board clears the last-move/turn state. Negative setup
coordinates, group/territory positions, and playback indices are checked before array access.
Replay and new-input validation now share one capture simulation. Saved records and
server-confirmed history remain replayable; the new legality checks apply to user input.

## Rules and ko

New moves check bounds, occupied points, turn, self-capture, simple ko, and superko. Repetition
history includes the initial position and is rebuilt on seek, restore, and undo. Passes do not
increment capture lids or fail superko checks; passing during unfinished handicap placement is
blocked. Historical-board clicks cannot append a move to a different live position. A forbidden
ko recapture has a visible marker in both 2D and 3D; other rejected moves have explanatory text.
Illegal hover moves no longer show a playable ghost stone.

| Rule selection | Local repetition check | Self-capture | Analysis/scoring handling |
| --- | --- | --- | --- |
| Japanese / Korean | Simple ko | Forbidden | Territory/seki preset; OGS final score |
| OGS Chinese / Chinese-OGS / Chinese-KGS | Positional superko | Forbidden | Area preset; OGS handicap adjustment |
| AGA / BGA | Situational superko | Forbidden | Area preset; OGS final score |
| NZ / New Zealand | Situational superko | Allowed | New Zealand preset approximation |
| Tromp-Taylor | Positional superko | Allowed | Tromp-Taylor preset |
| Stone-scoring | Simple ko | Forbidden | KataGo group-tax preset approximation |
| Ing / unknown names | Unavailable, visibly indicated | Not locally adjudicated | Analysis disabled |

Local SGF `Chinese` follows KataGo's `chinese` preset (simple ko); OGS Chinese uses positional
superko. Missing metadata keeps the previously documented Chinese/6.5 assumptions. Explicit OGS
self-capture and repetition flags override the named policy. These checks follow the official
[Goban rule defaults](https://github.com/online-go/goban/blob/d7eb38eb4e9e1c48ace12befb98d9f3c821ec2f3/src/engine/GobanEngine.ts)
and [KataGo preset definitions](https://github.com/lightvector/KataGo/blob/master/docs/GTP_Extensions.md).

This is not a complete local referee or scoring engine. In particular:

- Online scoring remains server-controlled. Local scoring now opens after two passes and
  requires manual dead-group agreement and confirmation. Its neutral-area tool excludes
  Japanese/Korean seki eyes; it cannot prove life/death or resolve bent-four/corner disputes.
- Local Japanese/Korean totals count territory, captures, marked-dead prisoners and komi.
  Chinese variants, AGA/BGA, New Zealand and Tromp-Taylor use area counting, so prisoners/pass
  stones are not added again. Handicap compensation is N for Chinese variants, N−1 for AGA/BGA,
  and zero for Japanese/Korean/NZ/TT, with explicit supported compensation overrides honored.
  White-last/pass-stone procedures are not simulated. Lids count actual removed stones;
  scoring adjustments are shown separately. Stone-scoring taxes, button rules and unknown
  custom scoring require an explicit supported scoring-rule choice instead of a silent fallback.
- Japanese/Korean long-cycle no-result adjudication, Ing rules, and unusual custom repetition
  schemes are not implemented locally. KataGo presets approximate national rules; in particular,
  OGS self-capture handling and KataGo's multi-stone-suicide rule are not identical in every case.
- The SGF loader preserves every branch and property of the first game tree, following the
  first child at each fork for default playback, as described by the
  [SGF variation examples](https://red-bean.com/sgf/var.html). It uses iterative traversal/storage
  so deeply nested exports do not exhaust a recursive stack. Comments/escaped brackets do not
  affect tree structure; malformed unfinished trees produce an error instead of a partial game.
  `SGFGame.sourceTree` retains the imported record separately from local playback additions.
  Selecting/editing variations, writing SGFs, additional games in collections, and faithful
  playback of midgame setup/removal or turn-changing properties remain future work. This does
  not rewrite imported records or certify arbitrary recorded histories as legal.

The rules tests include ko threats, pass/repetition differences, snapback, multi-group captures,
self-capture, fixed/free handicap, and undo/seek restoration. Render a sample ko position offline:

```sh
python3 Tests/Preview/render_captures.py /private/tmp/sgfplayer-ko-preview.png ko
```

## Capture lids

Lids and sidebar capture counters now use the same replayed board position. They count stones
actually captured during play, not additional dead stones included in end-of-game scoring.
Undo and history navigation recalculate those counts. Queued server counters no longer overwrite
them. Black's lid contains captured white stones; White's contains captured black stones.

The 2D lid no longer stops drawing at 35 captures. The 3D lid retains its stones when rebuilt or
resized, uses a fixed stone size independent of board size, and spaces simultaneous captures to
avoid starting with intersecting physics bodies. The collision floor and walls are simplified,
visual scaling is separated from the physics body, and new stones drop above the existing pile.
Camera orbit/pan now moves the camera using an equivalent inverse transform instead of moving
physics bodies; the original viewpoint is checked numerically. Both views show an exact numeric count, since
stones in a pile can obscure each other. Offline tests inspect actual SceneKit nodes for color,
count, size, spacing, resize, undo, and reset; the offscreen preview checks a 40-stone pile on 9x9:

```sh
python3 Tests/Preview/render_captures.py /private/tmp/sgfplayer-captures-preview.png
```

The preview freezes the initial layout and omits invisible collision meshes. The unit suite also advances the real SceneKit simulation: 80 stones through three board sizes,
then camera orbit/pan and an increase to 100 captures, checking that stones remain inside the lids.
Interactive app acceptance remains deferred.

## Build and automated validation

Run from the repository root:

```sh
xcodebuild -project SGFPlayerClean/SGFPlayerClean.xcodeproj \
  -scheme SGFPlayerClean -configuration Debug \
  -derivedDataPath /private/tmp/SGFPlayerCleanReview build
swift test
python3 Tests/Integration/run_loopback.py
```

The root Swift package compiles the networking sources, OGSClient, shared models/settings,
playback engine, SceneKit board scene, KataGo service, and chat view model used by Xcode. It is an offline test harness, not a replacement app target. The original local, untracked nested Swift package
was a Hello World executable and is not used here.

The 185 automated tests cover navigation-independent stone jitter, SGF main-line/variation parsing, disconnect, failed receives/sends, retry cancellation and bounds,
stale callbacks, connection/heartbeat timeouts, observer reentrancy, complete pagination,
HTTP errors, rate-limit cooldowns, cancellation, event payload shapes, challenge failure/busy-state
handling, queued notification invalidation, scoring transitions/confirmation/timeout,
server score parsing, local playback restoration/bounds, credential races, ordered move reconciliation,
undo/handicap snapshots, ko/superko/self-capture, capture-lid physics, rules/komi propagation, and KataGo subprocess/cache isolation. They use fake sockets,
a controllable scheduler, and URLProtocol HTTP fixtures. Client tests exercise the production
OGSClient with an ephemeral session and no shared cookies; every HTTP request is intercepted,
and socket creation is injected. No production OGS connection is made by these tests. The loopback test compiles the production WebSocket transport
and runs against a localhost-only Python standard-library fixture, exercising real text/binary
delivery, sending, abrupt connection loss, reconnect, ping/pong, and disconnect. Neither suite
uses OGS credentials or creates games. To explicitly run the installed KataGo smoke test (uses
Metal/GPU but no network, and keeps engine data in a temporary directory):

```sh
python3 Tests/Integration/run_katago.py --report /private/tmp/katago-offline-report.json
```

Keep the draft isolated while collecting these repairs. One combined acceptance session before
merging or replacing the working app should verify local playback, login, challenge creation,
reconnection during an active game, and return to local mode in the built app. KataGo requires
an installed executable (default `/opt/homebrew/bin/katago`); its model is included in the preserved resources.

The isolated app also supports offline checks against the compiled app model and views:

```sh
python3 Tests/OfflineReview/build_review.py
python3 Tests/UI/check_capture_rewind.py
python3 Tests/UI/check_capture_rewind.py PlaybackAudio.swift
python3 Tests/UI/check_capture_rewind.py ScoringDisplay.swift
python3 Tests/UI/check_capture_rewind.py LocalPass.swift
python3 Tests/UI/check_capture_rewind.py LocalScoring.swift
python3 Tests/UI/check_capture_rewind.py SGFPlayback.swift
python3 Tests/UI/check_capture_rewind.py SliderScrubbing.swift
python3 Tests/UI/check_capture_rewind.py StoneJitter.swift
```

The first UI check briefly displays a test window to verify captured-stone lids through
capture, rewind, and replay. The audio check plays single/multiple capture clips at zero
volume, checking actual AVAudioPlayer progress through automatic 2D/3D playback and silence
on rewind. Both use a separate probe preferences domain and the review's network-deny
sandbox. Speaker audibility remains a manual check. Playback timing tests in `swift test`
cover the saved Move Delay, speed changes while playing, pause/resume, and end-of-game stop.
The scoring check renders the production panel and uses OCR to verify visible winner text,
fractional totals, draws, absent scores, long names, and the earlier-position notice. The
offline app's banner opens these scoring examples without changing the current game.
The local Pass check hosts both board views and verifies visible controls/status, turn changes,
unchanged stones/captures, ko and rewind/replay behavior, and input guards. The local scoring
check exercises both full board views, open/closed sidebars, group/neutral marking, live totals,
both territory colors, confirmation, frozen results, rewind/replay, resumption and game changes.
The SGF playback check loads a nested 132-move game, verifies visible counters in both board
views, and checks forward steps, seeking, end, rewind/replay, and retention of the imported tree.
Set `SGF_PLAYBACK_TEST_FILE` and `SGF_PLAYBACK_EXPECTED_MOVES` to check an external SGF read-only;
no personal game contents are included in the committed regression fixtures.
The scrubbing check reproduces the default-mode stall, then exercises preview updates under
AppKit's event-tracking run-loop mode with both hosted board views. It checks board/lid agreement,
burst coalescing, rate limiting, duplicate suppression, silence, exact release, and cancellation
when loading another game. Physical mouse-drag feel remains a manual acceptance check.
The jitter check compares offsets at moves 92 and 93 reached by the same step-forward/backward
methods as the arrow keys, fresh sequential play, and seeks. `SGF_JITTER_TEST_FILE` optionally
selects an external SGF to inspect read-only; the default is an anonymous regression fixture.
Unit tests also cover retained neighbor movement, unchanged distant stones, replacement history,
passes/captures, appending moves, board/setup changes, and changing the jitter setting.

Scoring marks/results are in-memory review data, never edits to the source SGF. Unknown rules
and missing/invalid komi block confirmation until explicitly selected/entered. Manual agreement
is essential: the territory flood fill is not a life/death solver. The counting distinctions follow
the [BGA rules comparison](https://www.britgo.org/rules/compare.html), and handicap defaults match
[KataGo's documented presets](https://github.com/lightvector/KataGo/blob/master/docs/rules.html).

## Recovery without disturbing another checkout

Create a fresh checkout of the preservation branch:

```sh
git fetch origin
git worktree add ../SGFPlayerClean-preserved origin/codex/preserve-local-work-2026-10-14
```

Open its Xcode project to build the pre-refactor app. Keep the preservation branch and full local
archive until the refactored version has passed live acceptance testing.

## Variation trees in Review

The compact vertical tree works with **AI analysis switched off** in both 2D and 3D.
AI information sits below it; toggling AI preserves the tree viewport. The chevron
beside Variations collapses the tree. Small unnumbered nodes use a left-hand move
ruler every five moves; hover a node for its exact move/color. Click a
node to visit its position, then play on the board to add a continuation. Right-click
a node and choose Add pass here for a pass variation. The bottom Pass button is
reserved for Local Play; Play Online retains Pass beside Resign.
Playing from an earlier position creates an alternative and preserves the original
line. Playing an existing next move follows that branch without duplicating it.

Use the tree's up/down arrows for parent/child and left/right arrows for alternatives;
Up/Down keys also visit parent/child nodes when the tree has focus. Left/Right
keys and ordinary playback controls follow the selected branch; Control–Left/Right
switch alternatives. A yellow line traces the path from the root to the current
node, stopping at that node; its cyan ring remains visible. Orange dots mark
comments, which appear below the tree when selected.

**Save SGF…** writes all branches and retained SGF properties. Explicit edits are also
saved as recoverable drafts, separate from your original SGF and AI cache. Reopening
the unchanged original restores its draft. Export an SGF for a portable copy. Hovered
AI continuations remain temporary and never become saved branches automatically.

Imported setup/rule changes after play has begun are retained on export but currently
stop playback at that point; selecting those nodes explains the limitation. Branch
promotion/collapse, comment editing, and adding a complete AI PV are later
increments. Select a node and use the trash button to delete it and its descendants;
Undo Delete restores the complete branch and selection. The root is protected, and
deletions are saved in the recoverable draft. See `Tests/MainRelease/VariationTree.swift` and
`Tests/Networking/ReviewTreeTests.swift` for offline coverage.


## 3D environments and kaya floor board

Settings → 3D environment offers Garden-view room, Japanese garden, Moon,
Beneath the tree, Lamplit cave, Buddhist monastery, Yūgen-no-ma, Neighborhood
coffee shop, World of Tomorrow, The Inventor’s Laboratory, and Space station. The selected setting and lamp
flicker preference persist across launches. Switching preserves the game, camera,
bowl supplies, and captured-stone physics. The cave's shadow-casting lamp
updates its gentle flicker eight times per second; it stops when disabled, when
Reduce Motion is enabled, or when the scene leaves view.

The seven original settings use a traditional thick kaya floor board with carved feet. The playing
surface remains at the existing game-coordinate height; the floor, bowls, and
lids sit lower. Primitive collision supports keep captures on the visible board
and floor. Camera drags must still begin outside the wooden board.

Neighborhood coffee shop uses a thinner, footless tabletop goban on a worn walnut
table, with two mismatched chairs and ceramic coffee cups. Café bowls and lids sit
closer to the goban, with the near bowl pulled back to fit ordinary windows. The
large mugs represent about 9 cm diameter × 10 cm height against a 42 cm goban.
They sit directly on the table and carry Lawrence Marvit’s original “But First…
Coffee” drawings: Monster on the far-side mug and Asteroid on the near-side mug;
source details are in `marvit-mug-source.json` and `marvit-asteroid-source.json`. Faint
particle steam drifts above the coffee, pausing in inactive scenes and respecting
Reduce Motion. The table, cups, chairs,
board and equipment are real shadow-casting geometry. The table has a collision
surface; switching between table and floor settings preserves settled captured
stones in their lids. Its opening view shows the café counter, books, plants and
community furnishings before descending to the board. The generated surroundings
and tabletop texture are bundled as `coffee-shop-panorama.png` and
`coffee-table-wood.png`; built-in imagegen prompts are saved alongside them in
`SGFPlayerClean/Assets/Environments/coffee-shop-prompts.txt`.

World of Tomorrow adds an Art Deco skyport, a teal table, a brass navigation radio,
and a small finned rocket. The Inventor’s Laboratory surrounds a scarred workbench
with nearby glass apparatus, coils, gauges, books, and old machinery. Both use the
compact tabletop board/equipment layout and physical supports. Their tailored
opening views pause before descending to play, like the other settings.

Space station is a crowded orbital workshop with a broad observation window onto
stars, unfinished ring sections, cranes and construction gantries. A footless tabletop
goban sits on a graphite metal workstation with flush engineering displays, cyan and
amber status strips, raised switch banks, equipment cases and service cables. The
nearby controls are decorative geometry and leave the board and bowls clear. Station
surfaces use scratched graphite and chipped ivory paint textures, with physical-scale
UVs, dirt at panel rims, varied roughness and subdued, stained display glass. Texture
artwork and built-in imagegen prompts are saved in `station-wear-provenance.json`.
The central charcoal pad boosts the pale scuffs independently of its dark base.
Display indicators complete a circuit over two minutes, with only four-percent
telemetry variation. Their layouts and glass remain stationary; the clock pauses
with Reduce Motion, inactive views and environment changes, retaining its phase.
Station
placement animations take two seconds (ten times the normal duration), and captured
stones use one percent of normal gravity with gentler impulses. Other environments
restore normal gravity. Disabling Drop Stone Animation or loading a history position
still places board stones immediately. The new setting shares the existing camera,
board-size and screensaver paths. Its built-in imagegen artwork and exact prompt are
stored in `SGFPlayerClean/Assets/Environments/space-station-provenance.json`.
`SpaceStationTests` verifies slow placement, history jumps, gravity reset, actual
capture settling and table support; `Tests/MainRelease/SpaceStation.swift` checks
packaged artwork and board picking across all three sizes.

The woodland and monastery panoramas now frame much closer surroundings; nearby
ferns, mossy rocks, and an incense stand add foreground depth. Tree and Yūgen stone
shadows have stronger contrast. Yūgen furniture has rubbed wood and faded brocade;
the monastery has round, pleated and repaired zafu cushions. Its incense sticks are
partially burned with ash tips, two gently smoking embers and one spent stick.
Smoke pauses when the view leaves, the environment changes or Reduce Motion is
enabled. Floorboards have stronger relief, irregular rubbed patches, sparse
grain-aligned scratches and varied roughness. Goban feet use wider
traditional gardenia shoulders, approximately 10.7 cm high by 7.6 cm wide, with
recess shading retained beneath the slab. The compact upper body, narrow waist and
rounded lower fruit follow Maekawa and Yoshida reference photographs. Camera movement is swept against the
padded wooden slab to prevent zooming or panning inside it. Café mugs now have
rounded lower walls, recessed clay foot rings and contact shadows; only the print
is turned toward the seated player, preserving handle placement.

New artwork was made with built-in imagegen. Asset filenames and exact prompts
are recorded in `SGFPlayerClean/Assets/Environments/immersive-worlds-prompts.json`;
visual reference sources are recorded in `immersive-worlds-references.json`.
`CameraCollisionTests` covers floor/table boards, three board sizes, zoom, pan,
tilt, recentering, crossing the slab and recovering an invalid camera position.
A rendered geometry regression also keeps new tabletop props outside the board.

`CoffeeShopTests` covers table support, all board sizes and captured-stone stability
across scene changes. `Tests/MainRelease/CoffeeShop.swift` checks bundled assets,
board hit testing and rendered views. `EquipmentShadows.swift` compares renders
with each equipment/stone group's shadows enabled and disabled in all ten spaces.

Distant scenery uses generated photographic panoramas, with the nearby ground
projected onto a real floor mesh and contact shadows baked into a small texture.
This keeps camera rendering inexpensive but provides limited distant parallax;
large translations can reveal the panoramic projection. Shoji screens, the
houseplant, board, stones, bowls, lids, and lamp are actual geometry. Assets are
bundled and cached, with no runtime downloads. Asset prompts and scanned-material
sources are in `SGFPlayerClean/Assets/Environments/generated-assets.json` and
`sources.json`.

Regression coverage: `PlayingEnvironmentTests`, `ShojiEnvironmentTests`,
`BowlSupplyTests`, and `CaptureLidTests`; Release UI probes:
`Tests/MainRelease/PlayingEnvironments.swift`, `CameraInteraction.swift`, and
`FloatingGhost.swift`. `EnvironmentBenchmark.swift` measures a warmed offscreen
960×640 camera sweep (not live display FPS); `EnvironmentPreview.swift` renders
all settings from multiple viewpoints.


### Bowl packing — October 20, 2026

Supply bowls now use a lower-friction offline simulation: stone sliding friction
is 0.30 (previously 0.55), rolling friction 0.015 (previously 0.12), bowl friction
0.35 (previously 0.65), and sleep thresholds are reduced to let stones finish
settling into gaps. The collision margin remains 0.002 model units. Black and
white stones have separate baked layouts using the same dimensions as their
visible meshes; white stones previously reused black-stone positions. Both 2D
and 3D now use the 21.9/22.2 white-to-black diameter ratio.

`Tests/Preview/BakeBowlLayout.swift` regenerates all 182 black and 181 white fill
states in version 2 of `BowlLayouts.json`; `BakeBowls2D.swift` renders the matching
sprites. Runtime bowls still need no physics. Supply tests check packing height,
colour-specific layouts, physical size, counting, rewind and interrupted animation.

### 2D stone supply bowls

The 2D presentation uses a shared physical scale (`GoEquipmentDimensions2D`):
a 424.2 × 454.5 mm board, 22 × 23.7 mm grid spacing, 22.2 mm black stones,
and 21.9 mm white stones. These follow the Japanese equipment dimensions in the
[Nihon Ki-in guide](https://www.nihonkiin.or.jp/teach/lesson/school/knowledge.html).
At that scale the existing bowl mesh is 159.6 mm across, its stones are approximately
10.8 mm thick, and the matching lids are 138.75 mm across. The bowl renderer's
185 mm image span includes its transparent margins; board/lid stone artwork and
both lids instead normalize their visible body bounds. All five clam variants
therefore have the same diameter. Window resizing scales the complete equipment
set together. 9×9 and 13×13 retain larger playable stones while off-board equipment
keeps the 19×19 scale, intentionally.

`Tests/MainRelease/EquipmentScale2D.swift` measures actual rendered stone artwork,
checks the physical layout, renders wide/narrow 19/13/9 boards, and exercises
capture rewind/replay and native clicks at the outer intersections. The bowl
baker's `--calibration` option renders an isolated horizontal stone using the same
camera and geometry as the supply sprites, allowing its pixel diameter to be
checked against the board scale without pile tilt or occlusion.

The 2D board shows White’s bowl upper-left and Black’s bowl lower-right, opposite
those players’ capture lids. Both presentations use `GoEquipment3D.supplyCounts`
so setup stones and played stones deplete the supply; passes do not, prisoners
stay spent, and rewind/new-game navigation restores it. The 2D supply bowls have
no visible remaining-count badges; counts remain available to VoiceOver. White
bowl sprites use softer, lighter cast shadows and increased fill light.

`Tests/Preview/BakeBowls2D.swift` renders the existing 3D bowls and their baked
settled poses offline into `Assets/Environments/Bowls2D`: 182 black and 181 white
transparent 512-pixel PNGs, including empty bowls. The 2D view displays one image
per bowl with an eight-frame cache; it runs no SceneKit renderer or physics.
`Tests/MainRelease/Bowls2D.swift` checks live bowl pixels and counts, placement at two
window sizes, and all bundled image states against the Release app.


## Rooms and lighting — October 17, 2026

Open tatami is now a dark Buddhist monastery; its saved preference remains compatible.
Yūgen-no-ma is an additional setting inspired by [photographs of the Nihon Ki-in special match room](https://igoseka.jp/2685/), with its calligraphy alcove, shoji, indoor stone garden and pale carpet. It is an approximation, not a measured architectural reconstruction. The source photographs are reference-only and are not bundled. Generated panorama prompts and provenance are in `SGFPlayerClean/Assets/Environments/rooms-lighting-provenance.json`.

The Moon uses a higher summit panorama with Earth close to the horizon. Photographic surroundings and ground now share the same orientation. Long-side kaya grain follows the slab horizontally; player-facing end grain remains vertical. Both diffuse and fill lighting use the same mesh coordinates.

Beneath the tree uses one lightweight canopy mesh to cast broad shade with small sunlight openings. Daylight is split between sunlight through that canopy and a soft overhead fill whose shadow frustum begins below the leaves. This preserves equipment and stone shadows even inside canopy shade. The two lights retain the previous total intensity, and the extra light is removed outside the tree setting. The cave’s weak fill also casts soft equipment shadows, including captured stones already shaded from the lamp. Cave flicker moves its existing shadow-casting lamp slightly at eight updates per second, with interpolation; turning flicker off, leaving 3D, or Reduce Motion stops it and restores the light position. HDR highlight compression in the cave preserves white-stone shading. The 2D bowl sequence was rebaked with the light above-left to match the board.

### October 18 environment finishing

The monastery incense sits forward on the right of the board, with room for its
sticks and smoke at a moderate seated-view zoom. A hollow bronze vessel exposes
a granular gray ash bed; the former solid vessel cap had hidden the ash.
Black stones in bowls, on the board and in capture lids share the same material,
with no artificial gray emission. Material identity survives board resizing and
finish-setting changes.

The café’s near-side mug uses Lawrence Marvit’s original Asteroid design; the
far-side mug retains Monster. The artwork source and hash are recorded beside
the bundled image in `Assets/Environments/marvit-asteroid-source.json`.

`Tests/Preview/AshStonesPreview.swift` and the matching main-release probe render
all ten environments, both mug designs and the extended opening, and verify
visible ash plus incense framing through a 20% seated-distance reduction.

## Post-game review controls — October 18, 2026

Online SGF saves use the filename supplied by OGS's download response, including
Unicode player names. The automatic post-game Review export uses that same name
while preserving the locally edited variations. The previous generic Game-review
name is no longer used for the just-finished online game.

Next/previous mistake stops immediately before the played move. A dashed circle
marks that intersection in 2D and 3D; its color and displayed cost use the same
before/after evaluation as mistake filtering. Alternatives remain visible for the
player who made the mistake. Missing candidate analysis is no longer displayed as
an invented zero-loss move. The filter panel identifies the upcoming move and loss,
including passes, which have no intersection to circle.


### Aged temple board — October 18, 2026

Only the 3D Buddhist monastery uses the approved dark reddish-brown aged wood.
The 2D board always retains its original kaya texture and grid. Mechanical dings,
scrapes, and rubbed edges are in the texture; the original slab, feet, grid
coordinates, and collision geometry are retained. Other rooms keep their
existing board finish. Room changes and board resizing select the matching wood.

Grid ink is drawn independently over the wood, without baked-in or distressed
lines. The monastery uses 2.8% cell-width black lines in 3D. The 2D grid keeps
its original 1-point lines at 80% black. Generation prompts and texture hashes are recorded
in `SGFPlayerClean/Assets/Environments/temple-aged-board-provenance.json`.

The Release rendering probe checks 19/13/9 grids, star points, unchanged slab
geometry, room switching, and small/large 2D previews. All 11 environment tests
and 7 capture tests pass. The older camera-transform capture test has 22 numeric
assertion failures, reproduced identically using the pre-change source.


### Limestone cave board — October 18, 2026

Only the 3D lamplit cave uses the approved warm gray limestone board. Its top,
sides and carved feet use matte nonmetallic stone materials, with the existing
slab dimensions, feet, grid coordinates and collision geometry preserved. The
monastery retains aged wood; every 2D board retains the original kaya texture.

The stone texture contains no baked grid. Continuous black lines remain separate
and use the same strengthened width as the monastery. Room changes select the
correct finish; resizing retains the cave's subdued lighting. The generated maps
and exact prompts are recorded in
`SGFPlayerClean/Assets/Environments/cave-limestone-board-provenance.json`.

### Analysis switch and woodland plants — October 18, 2026

Settings → AI Engine → Enable analysis is a saved master switch, enabled by
default for existing installations. Turning it off hides AI results, cancels
hover/full-game/background searches and stops KataGo, while preserving completed
analysis on disk. Mode changes and postgame Review cannot override it. Turning it
back on reloads compatible cached results and resumes eligible analysis. The
separate variation tree and normal game controls remain available.

Nearby woodland plants now have curved stems, uneven frond lengths and spacing,
staggered leaflets, occasional gaps, asymmetric notched edges, curled tips and a
muted green/ochre/brown palette. Their geometry remains deterministically batched.
Every geometry child in the flattened grove participates in shadow casting,
including unnamed children previously excluded by the environment's name policy.
The plants use the existing canopy/daylight lights, with reduced artificial fill.

`Tests/MainRelease/AnalysisSwitch.swift` checks shutdown, saved preference, mode
and postgame transitions, and cache restoration using a fixture engine.
`CollapsibleSettings.swift` checks the rendered toggle and its on/off layouts.
`WoodlandShadows.swift` compares shadow-on/off renders and checks visible ground
shadows during opening, survey and seated views.

### Whole-game postgame review — October 21, 2026

Finished local and online games now use the foreground Review sweep, just like
imported SGFs. It fills positions from the opening through the final board and
then deepens the whole game, reusing compatible results. The resource-throttled
worker remains responsible for hidden analysis during play; its battery/load
pauses no longer suppress visible postgame review.

The AI panel's “Analyze full game” button stops selected-position continuous
analysis and starts the whole-game sweep without moving the board or changing
history. “Game coverage” reports positions with actual results, including the
empty opening. The existing “Keep analyzing” switch still deepens the selected
position. Both paths respect the saved master switch and live-play restrictions.

`Tests/MainRelease/FullGameReview.swift` uses a fixture engine and fake OGS
transport to check automatic local/online coverage, the rendered full-game button,
opening-to-end request order, position/history preservation, and analysis gates.

Physical Go 0.87 reconciles a uniquely determined nearby relocation among uncommitted moves after five clear views over at least 0.8 seconds. It can remove up to two nearby unlocked phantom/duplicate hypotheses, preserves settled identities and the saved SGF, excludes captures, and requires fresh confirmation before saving. Revisions include old/new sequences in the observation journal; camera gaps reset the evidence. `python3 PhysicalGo/build.py --repositioning-test` replays the November 6 duplicate-white-stone classifications and safety controls.

Physical Go 0.88 maintains a separate physical geometry track for established stones in both play modes. It reuses current independent camera outlines off the UI thread, scans at most twice per second, and updates centers after three consistent views over at least one second. Fresh one-to-one outline evidence can quarantine duplicate detections immediately; stored history never supplies missing stones or overrides clear empty observations. Coherent multi-stone motion requests existing grid recovery. Captures, new games, manual correction sessions, calibration/orientation changes, lighting failures, and camera gaps invalidate applicable tracks. Diagnostics show the tracked count and unclear outlines; image archives retain raw classifications and separately annotated physical tracks/assignments, never automatic training labels. Run `python3 PhysicalGo/build.py --stone-tracking-test` and `--stone-tracking-ui-test`.
