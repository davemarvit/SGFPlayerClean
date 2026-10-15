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
Tests use a temporary Python subprocess and fixture model file; they do not run the installed
KataGo executable, use the GPU, or touch the working app's analysis caches.

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
- The fake subprocess validates process/pipe behavior, not model compatibility, GPU startup,
  or performance of the installed KataGo engine. Live OGS and real-engine acceptance remain deferred.

## Local playback repairs

Local snapshots retain the viewed move index, initial player, state version, and capture counts.
Returning from online mode reconstructs that saved position and keeps the remaining moves
available for playback. Clearing the board clears the last-move/turn state. Negative setup
coordinates, group/territory positions, and playback indices are checked before array access.
These changes use the existing move/capture implementation; they do not change Go rules.

## Capture lids

Lids and sidebar capture counters now use the same replayed board position. They count stones
actually captured during play, not additional dead stones included in end-of-game scoring.
Undo and history navigation recalculate those counts. Queued server counters no longer overwrite
them. Black's lid contains captured white stones; White's contains captured black stones.

The 2D lid no longer stops drawing at 35 captures. The 3D lid retains its stones when rebuilt or
resized, uses a fixed stone size independent of board size, and spaces simultaneous captures to
avoid starting with intersecting physics bodies. Both views show an exact numeric count, since
stones in a pile can obscure each other. Offline tests inspect actual SceneKit nodes for color,
count, size, spacing, resize, undo, and reset; the offscreen preview checks a 40-stone pile on 9x9:

```sh
python3 Tests/Preview/render_captures.py /private/tmp/sgfplayer-captures-preview.png
```

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

The 139 automated tests cover disconnect, failed receives/sends, retry cancellation and bounds,
stale callbacks, connection/heartbeat timeouts, observer reentrancy, complete pagination,
HTTP errors, rate-limit cooldowns, cancellation, event payload shapes, challenge failure/busy-state
handling, queued notification invalidation, scoring transitions/confirmation/timeout,
server score parsing, local playback restoration/bounds, credential races, ordered move reconciliation,
undo/handicap snapshots, capture lids, rules/komi propagation, and KataGo subprocess/cache isolation. They use fake sockets,
a controllable scheduler, and URLProtocol HTTP fixtures. Client tests exercise the production
OGSClient with an ephemeral session and no shared cookies; every HTTP request is intercepted,
and socket creation is injected. No production OGS connection is made by these tests. The loopback test compiles the production WebSocket transport
and runs against a localhost-only Python standard-library fixture, exercising real text/binary
delivery, sending, abrupt connection loss, reconnect, ping/pong, and disconnect. Neither suite
uses OGS credentials or creates games.

Keep the draft isolated while collecting these repairs. One combined acceptance session before
merging or replacing the working app should verify local playback, login, challenge creation,
reconnection during an active game, and return to local mode in the built app. KataGo requires
an installed executable (default `/opt/homebrew/bin/katago`); its model is included in the preserved resources.

## Recovery without disturbing another checkout

Create a fresh checkout of the preservation branch:

```sh
git fetch origin
git worktree add ../SGFPlayerClean-preserved origin/codex/preserve-local-work-2026-10-14
```

Open its Xcode project to build the pre-refactor app. Keep the preservation branch and full local
archive until the refactored version has passed live acceptance testing.
