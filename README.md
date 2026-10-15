# SGFPlayerClean

Native macOS SGF player with shared 2D/3D board state, OGS live play, and KataGo analysis.
The application project is `SGFPlayerClean/SGFPlayerClean.xcodeproj` and its scheme is `SGFPlayerClean`.
The older `davemarvit/SGFPlayer` repository is a separate implementation.

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
(for example, “Alice White wins by 6.5 points”). Equal totals show “Draw”; missing numeric scores
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
- The SGF loader is a playback loader, not a full editor: it does not faithfully represent all
  variations, midgame setup/removal edits, or turn-changing properties. This pass does not rewrite
  imported records or certify arbitrary recorded histories as legal.

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

The 160 automated tests cover disconnect, failed receives/sends, retry cancellation and bounds,
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
