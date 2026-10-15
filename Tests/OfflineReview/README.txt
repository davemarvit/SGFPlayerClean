OFFLINE REVIEW PACKAGING

Build on this Mac with:
    python3 Tests/OfflineReview/build_review.py

Output: ../Offline Review/SGF Player Offline Review.app
Double-click the app in Finder. No Xcode or Terminal is needed to use it.

This is a local review package, not a release build. SGF_OFFLINE_REVIEW is set
only by the packaging command; the normal Xcode target keeps its behavior.

Isolation:
- Separate bundle ID: com.davemarvit.SGFPlayerClean.offline-review
- Separate standard preferences, saved window state, and AI cache.
- No working-app preferences, login cookies, or saved library are imported.
- OGS startup lookup/connect are disabled and Online is removed from the picker.
- HTTP session is ephemeral and has no cookie store.
- The native guard is called before AppModel construction, checks the bundle ID,
  and installs a macOS network-deny sandbox inherited by child processes.
  It also denies writes to the working checkout and its known data locations.
- The guard is linked directly into the review executable: it applies to both
  Finder launches and launching the executable directly, with no wrapper bypass.
- The review cannot link without the guard. A wrong identity or sandbox setup
  failure exits before AppModel creation. The macOS sandbox API used here is
  deprecated; this local helper must be rechecked on future macOS versions.
- KataGo uses the bundled review model and its own analysis/tuning directories.
  The existing Homebrew executable is read/run without modifying it.
- Sample games are bundled; auto-play on selection and auto-advance are disabled
  so a test position remains on screen. Explicit Play still works.
- The review's Open SGF File menu loads directly; the ordinary app's legacy
  notification-based menu is not changed by this packaging task.

Checks:
The build script validates signing and runs the actual packaged app with
SGF_REVIEW_CHECK=1. That mode probes only loopback and requires a kernel denial,
then exits before creating the application model. It never contacts OGS.
Run python3 Tests/OfflineReview/check_samples.py to validate the bundled
examples against the production parser and rule engine.
The banner's Scoring review button opens a display-only sheet with sample
final scores. It uses the production scoring panel, has no OGS client or game
model, and is compiled only into offline builds. It does not simulate the
scoring agreement or calculate a score for the current board.
Run python3 Tests/UI/check_capture_rewind.py ScoringDisplay.swift after a build
to render that sheet and check the panel's visible winner text, score precision,
draw/missing-score states, long names, and earlier-position notice using OCR.
The existing KataGo integration script can run under the generated sandbox:
    sandbox-exec -f '../Offline Review/network-and-file-protection.sb' \
      python3 Tests/Integration/run_katago.py

The produced bundle is intended for this user's Mac. Protected paths are
embedded when building; rebuild instead of distributing it to another user.
