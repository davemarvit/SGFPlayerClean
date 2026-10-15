# SGFPlayerClean

Native macOS SGF player with shared 2D/3D board state, OGS live play, and KataGo analysis.
The application project is `SGFPlayerClean/SGFPlayerClean.xcodeproj` and its scheme is `SGFPlayerClean`.
The older `davemarvit/SGFPlayer` repository is a separate implementation.

## Current review — October 15, 2026

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
rows, retry is explicit, and refresh/logout fence late replies. Data shape follows the
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
