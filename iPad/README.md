# Quiet Go for iPad — development prototype

The iPad target references the authoritative shared Swift sources under
`../SGFPlayerClean`. It does not copy the Mac application or replace the installed
Mac app. Open `QuietGo-iPad.xcodeproj`, or double-click **Run iPad Simulator.command**
to build, install and launch inside Apple's iPad Simulator. The resulting iOS
`.app` cannot be opened directly in Finder as a macOS application.

## Working scope

- Local 9×9, 13×13 and 19×19 games, captures, pass and navigation.
- SGF import through Files/Open In; export preserves variations and properties.
- Add continuations at earlier positions without deleting existing branches.
- Session recovery with atomic saves. Opening a different game or starting a new
  one archives the previous game in Documents/Saved Games, accessible through Files.
- Shared SceneKit board and environments; native 2D board over the shared tatami artwork.
- Portrait, landscape and narrow window layouts, direct touch/Pencil placement,
  two-finger drag or twist to orbit, pinch zoom, three-finger pan and recenter.
- Manual dead-group/neutral-area scoring using the existing scoring engine.
- Embedded, offline KataGo CPU analysis with complete history for ko. No subprocess,
  Homebrew installation, network service or downloaded executable is needed on iPad.
- OGS username/password login with app-scoped session restoration, challenge lobby,
  challenge creation/acceptance/cancellation, your active games and direct game links.
- Online 2D/3D direct tap placement, pass/resign confirmation,
  live clocks, captures, undo requests, game chat, dead-group marking, score acceptance,
  resume play, results and download of finished games into SGF review.
- Server-confirmed moves; duplicate/gap handling and complete history reconciliation
  after suspension or connection loss. Unconfirmed moves are never automatically resent.
- Backgrounding stops playback/rendering, cancels analysis, queues release of the
  model's memory and saves the session. Memory warnings also release analysis memory.

The tablet adapts the shared desktop board and review model to touch. Review tools
include a tappable variation tree, timed playback, a saved-game browser, persistent
on-device analysis, whole-game coverage, a win-chance graph and mistake navigation.
Desktop hover previews and unrestricted continuous searches remain desktop-specific. Scoring is provisional
manual counting; it does not adjudicate life and death. The screensaver is Mac-only.

## Online play

Tap **Online play**, sign in with your Online-Go.com username/password, and select
an active game, open a game number/link, accept a listed challenge, or create one.
Accepting a challenge starts a real game; the interface confirms before sending.
**Local play** restores the exact local position and variations you left. Leaving
the board does not resign or stop the server clock. Keep the app foregrounded for
live games and while waiting for an opponent to accept your challenge.

The tablet reuses `Services/OGSClient.swift`, its socket/HTTP transports, chat model,
clock handling, scoring protocol and the shared engine's history reconciler. The
iPad coordinator and SwiftUI screens are in `Sources/TabletOnline*.swift`. The local
session is never overwritten by online game snapshots. Local navigation/import and
analysis controls are unavailable on the online board; AI also stays disabled in
local mode while the connected account is known to have ongoing games.

When the app returns from the background it validates the saved session,
reauthenticates the socket, rejoins the game and reads a fresh history. Placement
remains disabled until reconciliation succeeds. A delayed move echo triggers a
read after ten seconds; it never triggers a repeat move submission. The **Refresh
connection** control offers recovery from server or network errors.

Credentials use the existing OGS password flow; third-party browser/social sign-in
is not implemented. Passwords are not persisted. Session cookies are saved in the
app's private Application Support directory; sign-out removes the saved session.
No Mac login or account credentials are copied into the iPad app.

The online implementation is covered by an in-process OGS fixture and the existing
shared networking tests. A live authenticated game and physical-device reconnect
behavior still require user/device validation. Test fixtures use an injected HTTP
protocol and fake socket; they cannot create games or send chat on the real service.
`--online-ui-testing` selects them only in a Debug build. Release builds contain no fixture implementation.

## Building

Requires Xcode with an iOS SDK and simulator runtime, an Apple Silicon Mac, CMake,
and Eigen 3 headers. The currently tested Eigen headers are Homebrew 3.4.0.

```sh
cd /Users/Dave/SGFPlayerClean
./iPad/KataGo/build.sh iphonesimulator
python3 iPad/generate_project.py
xcodebuild -project iPad/QuietGo-iPad.xcodeproj -scheme QuietGo-iPad \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath iPad/DerivedData CODE_SIGNING_ALLOWED=NO build
```

`generate_project.py` is deterministic and uses relative file references. Run it
when adding source files. The generated project and shared test scheme are retained.
The app targets iPadOS 17 or newer, arm64. Minimum-OS runtime compatibility still
needs testing. Simulator validation does not establish real-device performance.

For physical hardware, first run `./iPad/KataGo/build.sh iphoneos`, then choose the
iPad destination and a development signing team in Xcode. To preserve a local team
through project regeneration, put `DEVELOPMENT_TEAM = YOUR_TEAM_ID` in
`iPad/Signing.local.xcconfig` (ignored by Git); the generator automatically includes it. An unsigned device build
can be generated with `-sdk iphoneos -destination 'generic/platform=iOS'` and
`CODE_SIGNING_ALLOWED=NO`; it cannot be installed until signed/provisioned.

## KataGo implementation

The build downloads upstream **v1.16.4**, pinned to commit
`4b8de63bea2bd8790db96cd6f8daf86dc87be6f7`, into the ignored `.build/KataGo` directory.
This conservative baseline is compatible with the app's existing `kata1-b18.bin.gz`
model; it is not a claim to be the latest KataGo release. Engine source is unmodified.
The adapter, CMake source list and C interface are in `KataGo/`.

The Eigen CPU backend runs in-process on a serial worker queue, with one search
thread, one evaluator thread, a modest evaluation cache, and a limit of 16 visits
or eight seconds of search. Initial model loading and an in-flight neural-net
inference can extend elapsed time beyond that search limit. Results use **Black's
perspective** and are discarded when the selected position changes. The UI only
shows completed results for the current position. Boards over 19 and unsupported
custom rule overrides are rejected explicitly.

KataGo uses its stop flag for both cancellation and ordinary completion. The bridge
therefore tracks user cancellation separately from the engine's stop flag.
The evaluator is explicitly unloaded on suspension; its process-lifetime owner
avoids C++ global-destruction ordering problems with worker threads.

GPU/Metal/Core ML acceleration is a separate next step. Upstream documents its
Metal backend for macOS; this port currently uses Eigen on iPadOS. Real iPad
measurements are needed for strength per second, memory, thermals and battery use.

Sources: [KataGo](https://github.com/lightvector/KataGo),
[upstream compilation instructions](https://github.com/lightvector/KataGo/blob/master/Compiling.md).
Dependency notices are in `KataGo/Licenses` and included in the app bundle. Existing
model/artwork provenance remains the same as the Mac app; this prototype does not
constitute a distribution audit or an App Store submission.

## Shared-source compatibility changes

Only portability edits were made here: conditional AppKit/UIKit imports, native
UIImage adapters for texture builders, bitmap-to-image initialization, explicit
SceneKit scalar conversion (macOS uses CGFloat where iOS uses Float), and platform
bookmark flags. The iPad grid has a slightly larger depth separation to prevent
flickering, and the tablet view uses 4× antialiasing. iOS graphics adapters live exclusively in `Sources/UIKitGraphics.swift`.
The Mac target continues using AppKit. Environment appearance work belongs to the
separate environment conversation. A pre-edit source backup is retained at
`/Users/Dave/Documents/SGF PLayer/Main App Update/2026-10-18-iPad/Before`.

The Mac board-rendering regression helper now identifies `board-stone` nodes
explicitly, so decorative bowl stones are not mistaken for played stones.

## Validation

`Tests/TabletTests.swift` exercises captures/rewind, SGF branch round trips, invalid
import preservation, scoring isolation, session restore/archive, real native KataGo
inference and cancellation. `UITests/TabletUITests.swift` exercises touch placement,
navigation, switching to 3D and both orientations with screenshot attachments.
`Tests/TabletOnlineTests.swift` covers login, game switching, confirmed move dispatch,
duplicate/gap/undo reconciliation, suspension recovery, scoring, spectator restrictions
and local-session preservation. The online UI test signs into the fixture, joins,
places a stone directly, exchanges fixture chat, backgrounds/reactivates and returns to local
play. It does not sign into a real OGS account.

```sh
xcodebuild -project iPad/QuietGo-iPad.xcodeproj -scheme QuietGo-iPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath iPad/DerivedData CODE_SIGNING_ALLOWED=NO test
swift test --filter 'SGFParserTests|GoRulesTests|ReviewTreeTests|LocalScoringTests|BoardStoneRenderingTests'
```

Build outputs, logs and test-result bundles live in ignored `.build`, `DerivedData`
and `DeviceBuild` directories. See `Validation.txt` for the completed run's results.

## iPad touch update (build 2)

A single completed tap now plays a legal move in both views; the Place button is
removed. Occupied/illegal points and out-of-turn or unconfirmed online moves remain
blocked. In scoring mode a tap still marks the group instead of playing a stone.

The two-finger orbit no longer waits for the three-finger pan recognizer to fail.
Pan, pinch and twist recognizers may run together, with handlers restricted to
the appropriate finger count; taps wait for camera gestures to fail. Twisting two
fingers also rotates around the board. This follows UIKit's simultaneous-gesture
pattern: https://developer.apple.com/documentation/uikit/allowing-the-simultaneous-recognition-of-multiple-gestures

The 2D canvas draws the existing shared tatami image at the shared physical scale,
with mirrored repeats. No shared textures or environment materials were edited.


## Adaptive 2D equipment (build 3)

The iPad now reuses the shared bowl artwork and capture-pile positions. Bowls show
remaining supplies, and lids hold captured stones; both update during play, SGF
review and rewind. Portrait puts equipment above and below the board; landscape
puts it beside the board. Equipment cannot intercept board taps or cover the grid.

Local portrait play uses a compact turn/move/Analyze/Details strip to leave more
space for the board. Details opens the existing review, analysis and scoring tools.
Online and scoring controls remain visible in their panels. Narrow windows allow
the compact strip to wrap. Shared environment artwork and 3D staging are unchanged.

## 3D camera tours (build 4)

Entering 3D and changing environments now use the shared Mac arrival animation:
a wide establishing view, a slow survey, then a descent to the playing position.
An environment selected in Board settings waits until the sheet closes before its
tour starts. Recenter glides from the current camera pose back to the playing seat.

A scene touch skips either animation immediately. A dedicated recognizer consumes
the entire touch sequence, including a held touch, so lifting cannot place a stone
or initiate an orbit. Subsequent taps and camera gestures work normally. Reduce
Motion skips animation. Leaving 3D or backgrounding finishes and stops the tour;
returning from background does not replay it. Routine board updates preserve the
current camera path. Camera paths and environment artwork remain shared with Mac.

## 2D lid fit (build 5)

Each lid now uses its own artwork calibration instead of sharing the bowl's image
frame. The approximate raised seating-ring diameters (760 and 800 pixels in the
1024-pixel lid images) are fitted just inside the bowl's opening, with 2% clearance.
The resulting visible lids are both about 87% of the bowl body's diameter. This
reduces the two lid image frames by approximately 5% and 10%, accounting for their
different transparent margins. Board, bowl and captured-stone sizes are preserved;
the smaller lids remain centered in the existing portrait/landscape equipment slots.

## Board proportions and landscape layout (build 6)

The 2D grid uses the Mac board's rectangular cells: row spacing is 1.0773 times
column spacing. Stones remain round, and touch mapping follows the rectangular
grid. Supply bowls no longer display remaining-stone counts; capture counts remain.

Landscape places the title, mode and environment controls, game details, navigation
and Pass in the right panel, leaving the board the full available height. Portrait
keeps its compact controls. Rotation preserves the 3D scene and camera animation.

The 3D playing lens fits the board's top surface to the viewport with a small
margin, giving a larger final playing view. Manual camera adjustments are preserved
when resizing. A visible Environment menu switches settings directly and starts
the existing touch-skippable tour. Shared environment artwork is unchanged.

## Observe games (build 7)

Tap Observe in the portrait header or landscape right panel. Sign in to OGS if
needed, then select an ongoing game. The browser reuses the shared OGS live list,
including ranks, board size, moves, time controls, pagination and refresh. It
refreshes every 15 seconds while visible and active. A game link or number also
works. The Play/Observe selector switches the browser without leaving the current
board; selecting a game determines whether it opens for play or observation.

Observe explicitly disables player actions even when viewing the account's own
game. Live moves and reconnection use the existing online reconciliation path.
Pass, resign, undo and scoring actions are hidden from spectators. Chat can be
read; Observe does not send chat. Local play restores the saved local position.

## Compact mode controls (build 8)

Play Online, Local Play, Observe and Review stay visible with the selected mode
highlighted. Portrait uses one compact top bar and one bottom control strip.
Landscape uses a 260-point panel; Hide controls collapses it to a 112-point strip
while preserving the full board height and all four mode choices. Show controls
restores the detailed panel. The game title is in Details instead of a large header.

Review uses the current local game and exposes Choose game for SGF import. Imported
SGFs select Review; new games select Local Play. The local selection is saved with
the session and survives online play. Choose game in online modes opens the matching
browser. Settings, 2D/3D, Environment and Recenter share a compact icon row (or grid
in the collapsed strip). Details retains analysis, scoring and online game actions
when the full panel is hidden. All controls retain at least 44-point tap heights.

## Player information and browser cleanup (build 9)

The online popup follows the main Play Online/Observe selection; it has no second
mode toggle. Choose game is the single game-browser action on the board. Selecting
the already-active mode does not reopen it. The popup's explicit Open link or
number action remains available for a pasted OGS reference.

Player names and ranks are shown in the portrait status strip, expanded landscape
panel, and collapsed landscape strip. The detailed view also includes clocks. Rank
labels reuse the shared OGS rank formatter, including ratings and professional
ranks; same-game browser data supplies ranks when the game snapshot omits them.
Missing or provisional ranks say Rank unavailable. Previous-game identities are
hidden while joining a different game. Capture labels explicitly say, for example,
Black captured 1 white stone and White captured 3 black stones.

## Mac changes adapted to iPad (build 10, October 22, 2026)

- Regenerated shared-source/resource references to include current Mac environments,
  boards, lighting, equipment and artwork. Fixed SceneKit scalar conversions in
  the latest cave lamp staging so shared code compiles for iOS.
- Review displays the shared branch layout in a scrollable, tappable variation
  tree; saved branch ghosts appear in both 2D and 3D.
- Play/Pause and 1/2/5-second playback preserve existing branches. Import stays
  paused. Choose game opens Saved Games with an Import from Files action.
- Board settings includes the persisted analysis master switch. Turning it off
  cancels work, releases the engine, hides results and preserves saved analysis.
- Completed position analysis is saved atomically and reused after navigation or
  relaunch. Keys include model/bridge identity, board size, complete move/setup
  history, side to move and canonically encoded rules/komi. Desktop subprocess
  caches are intentionally independent from the iPad CPU engine.
- Analyze full game covers the active branch from opening through final position
  using an isolated player. Importing a new review record starts this sweep when
  analysis is allowed. Navigation, mode changes, suspension and the master switch
  cancel it. It never changes the visible board or edits the SGF.
- Deepen position requests up to 128 visits with the existing eight-second search
  cap. This is a bounded mobile search, not the desktop's indefinite search loop.
- A Black-perspective win-chance graph shows available results, leaving gaps where
  analysis is missing. Previous/Next mistake uses adjacent analyzed positions and
  2/5/10-point thresholds, stopping before the played move. These CPU estimates can
  be noisy; missing positions are never treated as zero-loss moves.
- Finished OGS downloads retain the server-supplied filename, including Unicode.

The iPad remains an in-process CPU app; Mac subprocess management, mouse hover,
Mac folder bookmarks and screensaver installation do not apply. Background analysis
during live play remains disabled. Real-device thermal, memory and reconnect
validation is still needed. No live OGS actions were performed for this update.
