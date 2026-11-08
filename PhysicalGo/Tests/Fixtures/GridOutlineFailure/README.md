# Clear-board grid detection failure

`frame.png` and `sample.json` are unchanged copies of Dave’s saved sample,
`Grid detection failure Physical Go Sample 2026-11-01 11-28-05`.
The board is empty, fully visible and has no manually selected calibration.
Physical Go 0.4 returned no grid; its Vision pass proposed zero rectangles.

`screenshot-camera.png` is the camera region of the preceding user screenshot,
cropped at (22, 367), size 1606 × 904, with no resizing or image enhancement.
That frame produced only a small interior rectangle with 0.4’s detector.

`expected.json` contains independently hand-estimated playable corner landmarks,
in pixels, ordered TL/TR/BR/BL. The tolerance allows annotation and lens error;
it is not a measurement of general detector accuracy. Tests also use deterministic
brightness, translation, rotation and resolution variants derived from these frames.
