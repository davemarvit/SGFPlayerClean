# Testing Checklist - SGFPlayerClean

**Purpose**: Systematic testing at every stage to catch issues early
**Rule**: Don't proceed to next step until ALL tests pass

---

## Testing Philosophy

### The Golden Rule
**NEVER build on broken code!**

After EVERY code change:
1. ✅ Does it compile?
2. ✅ Does it run without crashing?
3. ✅ Does the new feature work?
4. ✅ Did we break existing features?

If ANY answer is NO, stop and fix before proceeding.

---

## Phase 1: Foundation - LOCAL PLAYBACK

### Step 1.1: BoardViewModel Tests

#### Unit Tests (Mental/Manual)
```swift
// Test 1: ViewModel initialization
- [ ] Create BoardViewModel instance
- [ ] Verify initial state (currentMoveIndex = 0)
- [ ] Verify empty stone dictionary

// Test 2: Load game
- [ ] Load a simple 9x9 game (5 moves)
- [ ] Verify currentMoveIndex = 0
- [ ] Verify stones dictionary is populated

// Test 3: Navigate forward
- [ ] nextMove()
- [ ] Verify currentMoveIndex increments
- [ ] Verify stones dictionary updates

// Test 4: Navigate backward
- [ ] previousMove()
- [ ] Verify currentMoveIndex decrements
- [ ] Verify stones removed correctly

// Test 5: Seek to move
- [ ] seekToMove(3)
- [ ] Verify currentMoveIndex = 3
- [ ] Verify correct stones on board
```

**Stop Condition**: If any test fails, debug before proceeding

---

### Step 1.2: BoardView2D Tests

#### Visual Tests (Launch & Verify)
```
- [ ] App compiles
- [ ] App launches without crash
- [ ] Window appears
- [ ] Board grid renders (19x19 lines)
- [ ] Grid is properly aligned
- [ ] Board is centered in window
- [ ] Resizing window doesn't crash
```

#### Board Rendering Tests
```
Load a game with 10 moves:
- [ ] Stones appear on correct intersections
- [ ] Black stones are black
- [ ] White stones are white
- [ ] Stones are the right size
- [ ] No overlap/misalignment
```

**Stop Condition**: If board doesn't render correctly, fix before adding features

---

### Step 1.3: Local Game Playback Tests

#### Critical Functionality Tests

**Test Game Setup**:
Use a known game (e.g., "test-game.sgf" with 20 moves, known positions)

**Test 1: Load Game**
```
- [ ] Select game from list
- [ ] Initial position (move 0) shows empty board
- [ ] No crash
- [ ] No errors in console
```

**Test 2: Forward Navigation**
```
- [ ] Click "Next" button
- [ ] Move counter shows "1"
- [ ] First stone appears at correct position
- [ ] Click "Next" again
- [ ] Move counter shows "2"
- [ ] Second stone appears
- [ ] Continue to move 10
- [ ] All 10 stones positioned correctly
```

**Test 3: Backward Navigation**
```
From move 10:
- [ ] Click "Previous"
- [ ] Move counter shows "9"
- [ ] Last stone disappears
- [ ] Click "Previous" 5 more times
- [ ] Move counter shows "4"
- [ ] Only first 4 stones visible
- [ ] Go back to move 0
- [ ] Board is empty again
```

**Test 4: Jump to Move**
```
- [ ] Seek to move 15
- [ ] All 15 stones appear instantly
- [ ] Correct positions
- [ ] Seek back to move 5
- [ ] Only 5 stones visible
```

**Test 5: Auto-Play**
```
- [ ] Start at move 0
- [ ] Click "Play" button
- [ ] Moves advance automatically (1 per second)
- [ ] Stones appear in sequence
- [ ] Pause auto-play
- [ ] Verify stopped at current move
- [ ] Resume auto-play
- [ ] Continues from where it stopped
- [ ] Reaches end of game
- [ ] Auto-play stops at final move
```

**Test 6: Edge Cases**
```
- [ ] Try to go previous at move 0 (should do nothing gracefully)
- [ ] Try to go next at final move (should do nothing gracefully)
- [ ] Seek to move -1 (should handle gracefully)
- [ ] Seek to move 999 (should cap at final move)
```

**Stop Condition**: If ANY test fails, fix before Step 1.4

---

### Step 1.4: Game Selection Tests

**Test 1: Game List Display**
```
Load folder with 5 test games:
- [ ] All 5 games appear in list
- [ ] Game names display correctly
- [ ] Player names visible
- [ ] Dates visible (if available)
```

**Test 2: Switch Games**
```
- [ ] Load Game A
- [ ] Navigate to move 10 of Game A
- [ ] Switch to Game B
- [ ] Game B starts at move 0
- [ ] Correct board for Game B
- [ ] Switch back to Game A
- [ ] Game A shows move 10 (state preserved)
```

**Test 3: Game Metadata**
```
- [ ] Select game
- [ ] Black player name displays
- [ ] White player name displays
- [ ] Date displays
- [ ] Result displays (if available)
- [ ] Komi displays
- [ ] Handicap displays (if applicable)
```

**Stop Condition**: If game switching is broken, fix before Phase 2

---

### Phase 1 Final Validation

Before declaring Phase 1 complete, run this full regression test:

**Regression Test Suite**
```
Test with 3 different games (9x9, 13x13, 19x19):

For EACH game:
- [ ] Load game
- [ ] Navigate forward to mid-game
- [ ] Navigate backward to beginning
- [ ] Jump to random move
- [ ] Auto-play from start to finish
- [ ] Switch to different game
- [ ] Switch back
- [ ] No crashes
- [ ] No visual glitches
- [ ] Performance acceptable

Edge cases:
- [ ] Load very small game (5 moves)
- [ ] Load very large game (300+ moves)
- [ ] Rapid clicking (stress test)
- [ ] Resize window during playback
- [ ] All still works
```

**Phase 1 COMPLETE only if**: All tests pass with 0 failures

---

## Phase 2: Layout & Responsiveness

### Step 2.1: LayoutViewModel Tests

```
Test 1: Layout Calculation
- [ ] Small window (800x600)
- [ ] Board scales appropriately
- [ ] Large window (1920x1080)
- [ ] Board scales appropriately
- [ ] Ultra-wide window
- [ ] Board doesn't distort

Test 2: Bowl Positioning
- [ ] Upper bowl appears
- [ ] Lower bowl appears
- [ ] Bowls positioned relative to board
- [ ] Resizing window → bowls reposition
```

### Step 2.2: Responsive Layout Tests

```
Window Size Tests:
- [ ] Minimum size (600x400) → everything visible
- [ ] Medium size (1200x800) → proportions good
- [ ] Maximum size (2560x1440) → no pixelation
- [ ] Portrait orientation → graceful degradation
- [ ] Landscape orientation → optimal layout

Dynamic Resize Tests:
- [ ] Play game at small size
- [ ] Enlarge window during playback
- [ ] Stones stay positioned correctly
- [ ] Shrink window
- [ ] Everything still works
```

### Step 2.3: Bowl Display Tests

```
Captured Stones Tests:
- [ ] Play through game with captures
- [ ] Black captures white → stones appear in upper bowl
- [ ] White captures black → stones appear in lower bowl
- [ ] Correct count in each bowl
- [ ] Random positions (not overlapping)
- [ ] Navigate backward → captures decrease
- [ ] Navigate forward → captures increase
- [ ] Counts always accurate
```

**Phase 2 COMPLETE only if**: All layout tests pass

---

## Phase 3: OGS Integration

### CRITICAL: OGS Tests (Run After EVERY OGS Change)

**Test Setup**:
- Have two browser tabs ready (OGS web interface)
- Or use two devices
- Test account + opponent account

### Test 3.1: OGS Connection

```
- [ ] Launch app
- [ ] Enter OGS username/password
- [ ] Click "Connect"
- [ ] Connection succeeds
- [ ] No errors in console
- [ ] Status shows "Connected"
```

### Test 3.2: Create Challenge

```
- [ ] Click "Create Challenge"
- [ ] Set parameters:
      - Board size: 9x9
      - Handicap: 2 stones
      - Time: 5 min + 10 sec/move
      - Ranked: No
- [ ] Click "Create"
- [ ] Challenge appears in OGS web interface
- [ ] Challenge shows correct parameters
```

### Test 3.3: Accept Challenge (CRITICAL)

```
From opponent's browser/device:
- [ ] See challenge in OGS web interface
- [ ] Accept challenge
- [ ] Game starts

In our app:
- [ ] Game starts automatically
- [ ] **HANDICAP STONES APPEAR IMMEDIATELY** ← CRITICAL
- [ ] Handicap stones at correct positions (D4, Q16 for 9x9)
- [ ] Board shows "Black to play" or "White to play"
- [ ] Our color is correct
```

**STOP**: If handicap stones DON'T appear, this is the bug we had before. Fix immediately.

### Test 3.4: Opponent Places Stone

```
From opponent's browser:
- [ ] Place stone at D3

In our app (within 1 second):
- [ ] Stone appears at D3
- [ ] Stone is correct color
- [ ] Move counter increments
- [ ] It's our turn now
```

**STOP**: If opponent's stone doesn't appear, fix immediately.

### Test 3.5: We Place Stone

```
In our app:
- [ ] Click intersection Q3
- [ ] Stone appears at Q3
- [ ] Stone is correct color
- [ ] Move counter increments

In opponent's browser (within 1 second):
- [ ] Our stone appears at Q3
- [ ] Correct color
- [ ] It's opponent's turn
```

**STOP**: If our move doesn't sync, fix immediately.

### Test 3.6: Move Exchange (30 moves)

```
Play 30 moves alternating:
- [ ] Every opponent move appears
- [ ] Every our move sends
- [ ] No desync
- [ ] Move counter accurate
- [ ] Board state matches web interface exactly
- [ ] No mysterious stone disappearances
```

**STOP**: If ANY move fails to sync, debug before proceeding.

### Test 3.7: Captures in OGS Game

```
Create capture situation:
- [ ] Opponent captures our stone
- [ ] Our stone disappears from board
- [ ] Stone appears in opponent's bowl
- [ ] Capture count updates

- [ ] We capture opponent's stone
- [ ] Opponent's stone disappears
- [ ] Stone appears in our bowl
- [ ] Capture count updates

In opponent's browser:
- [ ] Captures match exactly
```

### Test 3.8: OGS Controls

```
Pass:
- [ ] Click "Pass" button
- [ ] Pass registers in web interface
- [ ] Opponent sees pass notification

Undo Request:
- [ ] Click "Undo"
- [ ] Opponent sees undo request
- [ ] Opponent accepts
- [ ] Move is undone in both places
- [ ] Board state correct

Resign:
- [ ] Click "Resign"
- [ ] Confirmation dialog appears
- [ ] Confirm resignation
- [ ] Game ends
- [ ] Result shows correctly
```

### Test 3.9: Time Controls

```
- [ ] Time remaining shows
- [ ] Time counts down during our turn
- [ ] Time stops during opponent's turn
- [ ] Time increments after move (if using Fischer)
- [ ] Low time warning (< 30 sec)
- [ ] Time runs out → loss on time
```

### Test 3.10: Connection Stability

```
- [ ] Start game
- [ ] Disable wifi briefly
- [ ] Re-enable wifi
- [ ] Connection recovers
- [ ] Game state syncs
- [ ] Can continue playing
```

**Phase 3 COMPLETE only if**: Can play full OGS game without ANY sync issues

---

## Phase 4: Chat Feature

### Test 4.1: Chat Display

```
- [ ] Start OGS game
- [ ] Chat panel visible
- [ ] Initially empty (no messages)
```

### Test 4.2: Send Message

```
- [ ] Type "Hello!" in chat input
- [ ] Press Enter
- [ ] Message appears in our chat
- [ ] Message shows our username
- [ ] Timestamp shows

In opponent's browser:
- [ ] Message appears in web chat
- [ ] Correct sender name
- [ ] Correct message text
```

### Test 4.3: Receive Message

```
In opponent's browser:
- [ ] Type "Good game!"
- [ ] Send message

In our app:
- [ ] Message appears within 1 second
- [ ] Correct sender name
- [ ] Correct message text
- [ ] Timestamp shows
```

### Test 4.4: Chat During Game

```
Play 10 moves, sending chat every 3 moves:
- [ ] Move 3: "Nice opening"
- [ ] Move 6: "Interesting move"
- [ ] Move 9: "Good game so far"
- [ ] All messages appear in order
- [ ] No messages lost
- [ ] Chat history persists
```

### Test 4.5: Chat Edge Cases

```
- [ ] Send empty message (should block or show error)
- [ ] Send very long message (200 chars)
- [ ] Send special characters: "!@#$%^&*()"
- [ ] Send emoji: "👍 🎮"
- [ ] All display correctly
```

**Phase 4 COMPLETE only if**: Chat works reliably in live games

---

## Phase 5: 3D Mode

### Test 5.1: 3D Board Rendering

```
- [ ] Switch to 3D mode
- [ ] 3D board appears
- [ ] Stones are 3D spheres
- [ ] Bowls are 3D models
- [ ] Camera positioned correctly
```

### Test 5.2: 3D Playback (Same as Phase 1)

```
Run ALL Phase 1 tests in 3D mode:
- [ ] Load game
- [ ] Navigate moves
- [ ] Auto-play
- [ ] Switch games
- [ ] All works identically to 2D
```

### Test 5.3: 3D OGS (Same as Phase 3)

```
Run ALL Phase 3 OGS tests in 3D mode:
- [ ] Create challenge
- [ ] Handicap stones appear
- [ ] Opponent moves sync
- [ ] Our moves send
- [ ] All works identically to 2D
```

### Test 5.4: 3D ↔ 2D Mode Switch

```
- [ ] Start game in 2D at move 10
- [ ] Switch to 3D
- [ ] Still at move 10
- [ ] Stones positioned correctly in 3D
- [ ] Navigate to move 15 in 3D
- [ ] Switch back to 2D
- [ ] Still at move 15
- [ ] Stones positioned correctly in 2D
- [ ] State is preserved
```

**Phase 5 COMPLETE only if**: 3D mode has feature parity with 2D

---

## Final Integration Tests

### Before Merging to Main Project

**Day 1: Extensive Local Testing**
```
- [ ] Load 20 different games
- [ ] Play through each completely
- [ ] Test all game sizes (9x9, 13x13, 19x19)
- [ ] Test handicap games
- [ ] Test tournament games
- [ ] No crashes
- [ ] No slowdowns
```

**Day 2: OGS Testing**
```
- [ ] Play 5 complete OGS games
- [ ] Different board sizes
- [ ] Different time controls
- [ ] Different opponents
- [ ] All games sync perfectly
- [ ] Chat works in all games
```

**Day 3: Stress Testing**
```
- [ ] Run app for 2 hours continuously
- [ ] Switch between 10+ games
- [ ] Play multiple OGS games
- [ ] Resize window frequently
- [ ] Toggle 2D/3D repeatedly
- [ ] No memory leaks
- [ ] No crashes
- [ ] Performance still good
```

**Day 4: Comparison Testing**
```
Run old and new versions side-by-side:
- [ ] Load same game in both
- [ ] Navigate to same move
- [ ] Visual comparison identical
- [ ] Feature parity confirmed
- [ ] New version feels responsive
- [ ] You prefer using new version
```

**Day 5: User Acceptance**
```
- [ ] Use ONLY new version for one day
- [ ] Play your usual games
- [ ] Use all features naturally
- [ ] Note any frustrations
- [ ] Fix any annoyances
- [ ] Final approval to merge
```

---

## Test Failure Protocol

### When a Test Fails

**Step 1: STOP**
- Don't proceed to next step
- Don't write more code
- Don't ignore the failure

**Step 2: Document**
```
- What test failed?
- What was expected?
- What actually happened?
- Can you reproduce it?
```

**Step 3: Debug**
```
- Add print statements
- Check state values
- Verify assumptions
- Find root cause
```

**Step 4: Fix**
```
- Fix the bug
- Re-run the failed test
- Verify it now passes
- Re-run previous tests (regression check)
```

**Step 5: Proceed**
- Only after ALL tests pass
- Continue to next step

---

## Test Data Setup

### Required Test Games

Create/find these test games:

```
test-games/
├── simple-9x9.sgf         # 20 moves, no captures
├── captures-9x9.sgf       # 30 moves, multiple captures
├── handicap-9x9.sgf       # 2 stone handicap
├── simple-13x13.sgf       # 50 moves
├── simple-19x19.sgf       # 100 moves
├── long-game.sgf          # 300+ moves (performance test)
└── edge-cases.sgf         # Unusual positions
```

### OGS Test Account

```
Create test accounts:
- Username: sgftest1
- Username: sgftest2
- Use for OGS integration testing
- Can play against yourself
```

---

## Success Metrics

### Phase 1 Success
✅ Can load ANY local SGF file
✅ Can navigate through entire game
✅ Can switch between games
✅ Auto-play works smoothly
✅ **0 test failures**

### Phase 3 Success
✅ Can create OGS challenges
✅ Handicap stones ALWAYS appear
✅ Opponent moves ALWAYS sync
✅ Our moves ALWAYS send
✅ **0 sync issues in 10 games**

### Phase 4 Success
✅ Can send chat messages
✅ Can receive chat messages
✅ Message order preserved
✅ **0 lost messages**

### Final Success
✅ **ALL tests pass**
✅ **0 known bugs**
✅ You use it daily
✅ You're happy with it

---

## Testing Schedule

### After Each Code Session

**Before taking a break:**
1. Run relevant test suite
2. Fix any failures
3. Commit working code
4. Document progress

**Never end a session with:**
- Failing tests
- Untested code
- Known bugs
- Broken builds

### Weekly Regression

**Every Sunday:**
- Run FULL test suite
- Document any new issues
- Fix critical bugs
- Plan week ahead

---

## Ready to Build

With this testing framework:
- ✅ Catch issues immediately
- ✅ Never build on broken code
- ✅ Systematic progress
- ✅ Confidence in quality
- ✅ Ship working software

**Start Phase 1 when ready!**
