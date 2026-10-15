Capture/rewind UI regression

After building the offline review app, run:
    python3 Tests/UI/check_capture_rewind.py

The check links the real compiled app models and views (without the app entry
point) into a temporary test bundle. It has a separate preferences domain and
runs under the review network-deny sandbox. KataGo is disabled in this test.
A temporary 800x650 window appears for several seconds, then closes.

The check adds legal moves to the supplied handicap game and captures two black
stones. In 3D, it checks engine/view-model counts, actual and presented lid
nodes, labels, settling near the center, rewind, and replay. In 2D it keeps
the view mounted across a rewind and compares the lid's rendered pixels with
a freshly mounted zero-capture view. This failed on the old build because
ContentView2D read nested counts without observing them.

Screenshots are written to /private/tmp/sgf-ui-{captured,rewound,fresh-start}.png.
The 3D rewind was already passing on the previous build; the observed 3D fixes
are central drop placement and restoring the placement click on capture moves.
This check does not assert that audible output reaches the Mac's speakers.
