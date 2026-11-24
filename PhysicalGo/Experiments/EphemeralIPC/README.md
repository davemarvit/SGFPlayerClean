# Ephemeral bridge IPC — November 24 candidate

This candidate keeps complete-file atomic visibility for live camera PNGs,
`latest.json`, and laser `request.json`, while removing crash-durability work
from those replaceable IPC files. It does not change saved-game, calibration,
settings, recording, or other durable writes. Source implementation and offline
tests are separate from installation and live physical validation.

`EphemeralAtomicFile` creates an exclusive same-directory temporary with mode
0600, loops through partial writes/EINTR, checks close, and atomically renames it
onto the destination. It never calls fsync. Failures preserve the prior destination
and remove the temporary. A crash can lose the live IPC files; their consumers
already reject stale/missing state. Original capture times and request lease
expiry bytes are unchanged. This is an explicit ephemeral-file contract, not a
general replacement for Foundation atomic writes.

The broker scans old protocol PNGs once per instance, retains a queue-owned list,
and removes old images before adding another, keeping at most four protocol
images after publication. It ignores unrelated files. A failed manifest write
removes its newly written orphan PNG. Epoch reset during encoding or pixel IO
cannot pair an old image with a new verdict. No freshness limit or motor behavior
changes in this candidate.

Optional bounded `PhysicalLatencyTrace` events now distinguish:

- `laser_frame_encoding`: preparation encode duration.
- `laser_frame_published`: frame/epoch, prepared-pixel reuse, encode, initial
  directory work, pruning, pixel write, manifest encode/write, total publication
  duration and capture age.
- `laser_frame_publication_failed`: stage and elapsed publication time.

The candidate's value is reduced repeated metadata work and actual publication
stage visibility. **The private benchmarks did not demonstrate a write speedup.**
They used a 3,113,749-byte representative PNG, 60 measured alternating pairs after
four warmup pairs, in a private Application Support directory on the same
filesystem. All emitted contents were checked; no real bridge file was touched.

| PNG + manifest + request | Foundation atomic median / p95 | Ephemeral atomic median / p95 |
|---|---:|---:|
| Private benchmark | 3.58 / 26.01 ms | 4.00 / 24.64 ms |
| With concurrent private readers | 3.22 / 7.93 ms | 3.13 / 9.28 ms |

These runs did not reproduce the live 223–269 ms request-write stalls. Removing
fsync alone therefore cannot be called the demonstrated fix for the interruption.

A separate lossless PNG experiment placed `kCGImagePropertyPNGCompressionFilter`
inside `kCGImagePropertyPNGDictionary`, where ImageIO honored it: emitted bytes
and sizes changed, while all decoded pixels matched baseline. Median times were
default 77.2 ms, None 93.3, Sub 89.5, Up 77.5, Average 103.2, Paeth 104.6. The default
encoder was retained. A previously ignored top-level property is not evidence
that this nested option is ineffective; the honored options simply did not help
this photograph.

## Offline validation

The writer's 43 assertions pass, covering short writes, EINTR, zero-length data,
create/write/zero-progress/close/rename errors, temporary cleanup, old-file
visibility during a deliberately blocked partial write, and unchanged bytes.
The actual asynchronous exchange checks and 283 AI laser lifecycle checks pass.
An initial broker-retention assertion failed because its test compared normalized
file URLs to an unnormalized URL for the unrelated image. The preserved test
folder had exactly four protocol PNGs plus that unrelated file. The test now
compares basenames. Its rerun is pending until the root's attended physical test
releases the CPU-intensive testing window.

No candidate app was built or installed by this agent. The live driver, camera,
game, clocks and calibration were not changed.

```sh
python3 PhysicalGo/build.py --ephemeral-io-test
python3 PhysicalGo/build.py --broker-epoch-test --ai-laser-test --bridge-io-test --debug-tests
xcrun swiftc -swift-version 5 -O PhysicalGo/Sources/EphemeralAtomicFile.swift PhysicalGo/Tools/benchmark_ephemeral_ipc.swift -o /tmp/physicalgo-ipc-benchmark
/tmp/physicalgo-ipc-benchmark /absolute/path/to/representative.png
/tmp/physicalgo-ipc-benchmark /absolute/path/to/representative.png --readers
```

The benchmark makes and removes its own `PhysicalGoIPC-Benchmark-UUID` directory.
It does not accept an output directory and cannot target `LaserBridge` through
its command-line arguments.
