# Physical Go failure reports

The user has authorized this response whenever they report that the app is stuck,
misreading the board, failing setup, or otherwise malfunctioning:

1. First stop diagnostic image saving and silence warning feedback. Run
   `osascript PhysicalGo/Tools/pause_recording_for_diagnosis.applescript`.
   Verify success; if the UI changed, inspect it and perform the same controls.
   Stop both continuous and automatic recordings and cancel next-game arming.
   Do not alter game history, timestamps, clock balances, or camera calibration
   as part of this diagnostic pause.
2. Inspect the relevant recording and logs. Trim a clearly repetitive tail without
   asking again, keeping at least 30 seconds after the last meaningful event and
   the final image. Use `PhysicalGo/Tools/trim_recording_tail.py` with a reviewed
   `--after-frame` and `--apply`; it preserves metadata and an audit. Do not guess
   from elapsed time alone or delete images still needed to understand a hand,
   stone cleanup, delayed capture removal, or camera gap. If no tail is redundant,
   keep it and say so.
3. Leave image saving and warnings off during investigation. Re-enable them when
   the user asks to test again. Prefer arming continuous recording for the next
   game's Start button to accumulating irrelevant setup images.

Use “recording” for camera images. Preserve unrelated working-tree changes.
Keep AUSDOM AF660 calibration separate from older zoomed iPhone 11 Pro Max data.
