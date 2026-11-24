# Experimental fast-test idle engine reuse

This isolated candidate is based on narrow 0.256 source `347eb84`. It is separate
from the ambiguity fix and is not installed or physically validated.

The November 23 test session measured 0.793 seconds between human-move acceptance
and the next verified board, then 8.253 seconds until the AI answer after a
pause/resume. The next uninterrupted move took 0.796 seconds for the board check
and 0.378 seconds from thinking to answer. Both searches completed eight visits.
Source inspection showed that both Pause and Resume discarded the test engine;
cold model/process startup plausibly explains the difference. Existing evidence
does not separately measure startup, inference, and result delivery.

The candidate retains a completed, idle fast-test worker during ordinary Pause,
Resume, or camera Freeze. It never starts a search while paused. The model remains
in memory during the pause; idle retention does not make a promise about memory
size or operating-system scheduling. First use and an interrupted search still
require a fresh worker.

An active search is always stopped on Pause. Each worker request has an identity;
late success or failure cannot commit a move, clear a replacement request, or stop
a replacement engine. Concurrent search activation is rejected. PhysicalAI still
cancels its task, replaces its generation, invalidates camera/laser evidence, and
performs the existing board verification before advancing. History, decision
receipt timestamps, and clock transitions are unchanged.

Changing fast-test mode, starting/ending a game, failure, switching away from AI
play, or camera/app shutdown releases the process, including when already paused.
Before a retained worker is used, the backend checks current executable/model
preferences and the launch-time file signature: resolved path, size, modification
time, and file identity for executable, model, and config. This uses the existing
engine identity cache's metadata convention; it does not rehash a large model on
each move and cannot detect an in-place rewrite that preserves all those metadata.
An observed change, unavailable file, dead process, pending request, or engine error
prevents reuse and causes replacement before the next search. Search failure keeps
the existing paused/failed-game behavior.

`python3 PhysicalGo/build.py --ai-idle-reuse-test` exercises deterministic fake
engines and real controller lifecycle, including cancellation-ignoring old results,
request overlap, idle replacement, history/clocks, and cleanup. Independent review
adds adversarial scheduling cases and a temporary fake executable to exercise the
real metadata guard; it does not run KataGo or touch application caches/defaults.
Validation completed: the targeted executable compiled against the full app
source and passed 42 checks, including 23 independent review checks; the build
registry passed eight checks. There are no elapsed-time assertions or hardware
tests. The standard eight-visit search setting is unchanged.

Rollback is simply to omit this candidate commit. It changes no saved-game schema,
user preference, camera calibration, or active laser binding.
