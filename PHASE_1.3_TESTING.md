# Phase 1.3 Testing Guide

**Date**: 2025-11-19
**Goal**: Test local SGF playback with handicap stones, captures, and ko rules

---

## What We Built

### Files Copied from Old Codebase:
1. **Models/SGFKit.swift** - SGF parser, SGFGame, SGFParser
2. **Models/SGFPlayerEngine.swift** - SGFPlayer engine with capture logic
3. **Models/BoardSnapshot.swift** - Board state representation
4. **Models/SGFGameWrapper.swift** - Game metadata wrapper

### Files Updated:
5. **ViewModels/BoardViewModel.swift** - Now wired to real SGFPlayer
6. **Views/ContentView2D.swift** - Added minimal AppModel with game loading
7. **SGFPlayerCleanApp.swift** - Simple test application

---

## Architecture

```
ContentView2D
  ↓
BoardViewModel (wrapper/adapter)
  ↓ (observes via Combine)
SGFPlayer (game engine)
  ↓
SGFGame (parsed from SGF file)
```

**Key Design**:
- BoardViewModel wraps SGFPlayer to provide clean ViewModel interface
- Uses Combine to observe SGFPlayer's @Published properties
- Automatic state synchronization (no manual updates needed!)
- SGFPlayer handles ALL game logic (captures, ko, handicap)

---

## How to Test

### Step 1: Create Xcode Project

```bash
cd /Users/Dave/SGFPlayerClean

# Create Xcode project
xed -c .
```

In Xcode:
1. **File → New → Project**
2. Choose **macOS → App**
3. Product Name: **SGFPlayerClean**
4. Interface: **SwiftUI**
5. Life Cycle: **SwiftUI App**
6. Save to `/Users/Dave/SGFPlayerClean/`

### Step 2: Add Files to Project

Add these folders/files to the project:
- `Models/` (all .swift files)
- `ViewModels/` (all .swift files)
- `Views/` (all .swift files)
- `SGFPlayerCleanApp.swift`

**Important**: Replace the auto-generated `SGFPlayerCleanApp.swift` with ours!

### Step 3: Build and Run

1. **Cmd+B** to build
2. Fix any import/compilation errors
3. **Cmd+R** to run

### Step 4: Select SGF Folder

When app launches:
1. Click "Open SGF Folder..." or **Cmd+O**
2. Navigate to folder with .sgf files
3. Select folder with games that have:
   - Handicap stones (H2, H3, H4, etc.)
   - Captures
   - Ko situations (if available)

---

## Critical Tests

### ✅ Test 1: Handicap Stones

**Goal**: Verify handicap stones appear at start of game

**Steps**:
1. Load a game with handicap (H2, H3, H4, H5, H6, H7, H8, H9)
2. Check that black stones appear at correct star points
3. Verify count matches handicap value

**Expected Results**:
- H2: Stones at (15,3) and (3,15) on 19x19 board
- H3: Add center stone at (9,9)
- H4: Stones at all four corners (3,3), (15,3), (3,15), (15,15)
- H5-H9: Additional stones at specific positions

**How to Verify**:
- Handicap stones should be visible immediately when game loads
- Move counter should start at 0
- First move should be White (since Black got handicap)

### ✅ Test 2: Stone Captures

**Goal**: Verify captured stones are counted correctly

**Steps**:
1. Load any game with captures
2. Navigate through moves
3. Watch bowl displays (upper = white captured, lower = black captured)
4. Check counts increment when stones are captured

**Expected Results**:
- When a group is surrounded and loses all liberties, it disappears
- Captured stones appear in opponent's bowl
- Capture count increments correctly
- Bowls show random stone placement (not physics-based)

**Example Game to Test**:
- Find a game with ladder captures
- Find a game with snapback captures
- Find a game with large group captures

### ✅ Test 3: Ko Rule

**Goal**: Verify ko situations don't break the game

**Steps**:
1. Load a game with a ko fight (if available)
2. Navigate through the ko sequence
3. Verify stones appear/disappear correctly
4. Check that capture counting works

**Expected Results**:
- Ko capture: Stone captured, then immediately recaptured
- Capture counts alternate +1, -1, +1, -1
- No crashes
- Board state updates correctly

**Note**: SGFPlayer doesn't enforce ko rule (it just plays back moves), but we need to verify playback works correctly.

### ✅ Test 4: Navigation

**Goal**: Verify move navigation works

**Steps**:
1. Load any game
2. Use playback controls:
   - ⏮ Go to start
   - ⏪ Previous move
   - ⏯ Play/Pause (auto-play)
   - ⏩ Next move
   - ⏭ Go to end

**Expected Results**:
- Stones appear/disappear correctly
- Last move indicator shows on current stone
- Capture counts update as you navigate
- Auto-play advances at ~0.75 seconds per move
- No crashes when reaching start/end

### ✅ Test 5: Game Switching

**Goal**: Verify switching between games works

**Steps**:
1. Load folder with multiple games
2. Switch between games (Phase 1.4 - not yet implemented)
3. Verify board clears and new game loads

**Expected Results** (Phase 1.4):
- Old game stones disappear
- New game loads from start
- Handicap stones appear if applicable
- Capture counts reset to 0

---

## Known Limitations (Phase 1.3)

### Not Yet Implemented:
- ❌ Game selection/switching (Phase 1.4)
- ❌ Settings panel (Phase 5)
- ❌ Sound effects (Phase 5)
- ❌ OGS live games (Phase 3)
- ❌ Chat (Phase 4)
- ❌ 3D mode (Phase 5)

### Simplified Features:
- ⚠️ Bowls use random stone placement (not physics)
- ⚠️ No search/filter (Phase 2)
- ⚠️ Minimal UI (will be polished in Phase 5)

---

## Debugging Tips

### Stones Don't Appear:
1. Check console for "📖 BoardViewModel: Loading game" message
2. Verify SGF file parsed correctly
3. Check that `player.board.grid` has stones
4. Verify Combine observers are firing

### Captures Don't Count:
1. Check SGFPlayer's capture logic (lines 201-228 in SGFPlayerEngine.swift)
2. Verify `blackCaptured` and `whiteCaptured` update in SGFPlayer
3. Check that BoardViewModel observers receive updates
4. Print capture counts in console

### Auto-Play Doesn't Work:
1. Check that `player.togglePlay()` is called
2. Verify timer is created in SGFPlayer
3. Check that `stepForward()` is being called
4. Look for `isPlaying` state changes

### Handicap Stones Missing:
1. Check that SGF has "AB" property
2. Verify `game.setup` array is populated
3. Check that SGFPlayer's `reset()` applies setup stones (lines 91-103)
4. Verify `updateStones(from:)` converts grid to dictionary correctly

---

## Success Criteria

**Phase 1.3 is successful if**:

✅ Can load SGF files from folder
✅ Handicap stones appear correctly at game start
✅ Can navigate through moves
✅ Stones appear/disappear correctly
✅ Captures count correctly (bowls update)
✅ Ko situations don't crash
✅ Auto-play works
✅ Last move indicator shows
✅ No crashes during normal use

**If all tests pass**: Move to Phase 1.4 (Game Selection)

---

## Next Steps (Phase 1.4)

After Phase 1.3 tests pass:

1. Add game list panel to right side
2. Implement game switching
3. Add search/filter (Phase 2)
4. Test switching between games with different board sizes
5. Test switching between games with/without handicap

---

## Console Output Examples

### Successful Game Load:
```
📖 BoardViewModel: Loading game: Lee Sedol vs AlphaGo
✅ Loaded: 2016-03-09-lee-sedol-vs-alphago.sgf
📚 Loaded 1 games
🔄 BoardViewModel: Updated 0 stones on board
📖 BoardViewModel: Game loaded - 280 moves, board size 19
```

### Handicap Game Load:
```
📖 BoardViewModel: Loading game: Handicap Game H4
🔄 BoardViewModel: Updated 4 stones on board
📖 BoardViewModel: Game loaded - 150 moves, board size 19
```

### Move Navigation:
```
🔍 BoardViewModel: Seeking to move 10
🔄 BoardViewModel: Updated 10 stones on board
```

### Capture:
```
🔍 APPLY: Move 45: black at (3, 4)
🔍 APPLY: Captured 2 white stones
🔄 BoardViewModel: Updated 8 stones on board
```

---

## File Structure After Phase 1.3

```
SGFPlayerClean/
├─ Models/
│   ├─ SGFKit.swift                  ✅ Copied from old code
│   ├─ SGFPlayerEngine.swift         ✅ Copied from old code
│   ├─ BoardSnapshot.swift           ✅ Created
│   └─ SGFGameWrapper.swift          ✅ Created
│
├─ ViewModels/
│   ├─ BoardViewModel.swift          ✅ Wired to SGFPlayer
│   ├─ LayoutViewModel.swift         ✅ From Phase 1.1
│   └─ BoardViewModel_old.swift      ⚠️ Backup (can delete)
│
├─ Views/
│   ├─ ContentView2D.swift           ✅ Updated with AppModel
│   ├─ BoardView2D.swift             ✅ From Phase 1.2
│   ├─ SimpleBowlView.swift          ✅ From Phase 1.2
│   └─ SupportingViews.swift         ✅ From Phase 1.2
│
├─ Documentation/
│   ├─ TESTING_CHECKLIST.md
│   └─ PHASE_1.3_TESTING.md          ✅ This file
│
├─ SGFPlayerCleanApp.swift           ✅ Test app
├─ PHASE_1_COMPLETE.md
└─ README.md
```

---

## Ready to Test!

1. Create Xcode project
2. Add all files
3. Build and run
4. Test with handicap games
5. Verify captures count correctly
6. Report any issues

**Let's verify the PRIMARY use case works perfectly!** 🎯
