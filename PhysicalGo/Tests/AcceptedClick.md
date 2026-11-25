# Accepted-target stone click

November 25, 2026. PG26b candidate based on installed app source `0f9ac75`
(0.264). Installation and physical status remain in the authoritative issue
register; this note records offline implementation evidence only.

The native move click now requires a current matching hardware `adequate` status
with `laserOn` and `illuminationConfirmed`. An acquisition flash (`approaching`)
or correction (`refining`) no longer consumes the move's cue. Existing revision,
freshness, session, intent, cancellation and once-per-move guards remain intact.
Capture and centering indications remain silent. A retry after a never-accepted
attempt can receive its first click; a retry after acceptance remains deduplicated.

The memory-only dedup key remains source/session/moveNumber. App restart can reset
that history; this patch does not add persistence. The existing diagnostic source
string `first_light` is retained for compatibility, but cue eligibility is now
accepted illumination. No audio-output preferences or playback implementation
changed. AirPod Pro3 remains untouched.

Validation:

```sh
python3 PhysicalGo/build.py --accepted-click-test --debug-tests
```

The 16-source, no-audio test subset fails the unmodified baseline at
`Acquisition flash announced replacement before optical acceptance` and passes
all 28 checks with the candidate. Coverage includes both wire schemas, repeated
adequate receipts, same-move retries, different moves/sessions, cancellation,
superseded revision, wrong producer/session, stale/future timestamps, absent
illumination confirmation, darkness, simulation and special-purpose intents.

The existing broader AI-laser suite's cue expectations and injected blocked-audio
trigger were updated to adequate semantics; root owns its combined integration
run. No app build, installation, audio playback, camera, serial or physical test
was performed for this candidate. Actual audible timing still needs attended
verification: status acknowledgement and playback dispatch are not measured
speaker/headphone onset. Host double-beep policy is a separate change.
