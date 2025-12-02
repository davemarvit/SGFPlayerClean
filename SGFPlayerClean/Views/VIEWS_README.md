# Views - Clean Architecture

**Created**: 2025-11-19
**Phase**: 1.2 (Basic Views)

## Overview

These SwiftUI views implement the UI for the SGF Player using clean architecture principles:

- **Pure UI**: No business logic (that belongs in ViewModels)
- **Declarative**: State → UI (unidirectional data flow)
- **Composable**: Small, focused components
- **Testable**: Can preview and test in isolation

---

## View Hierarchy

```
ContentView2D
├─ GeometryReader (stays here!)
├─ Background
├─ HStack (70/30 split)
│   ├─ Left Panel (70%)
│   │   ├─ TatamiBackground
│   │   ├─ BoardView2D
│   │   │   ├─ Board background
│   │   │   ├─ Grid lines
│   │   │   ├─ Star points
│   │   │   ├─ Stones layer
│   │   │   ├─ Last move indicator
│   │   │   └─ Click handler
│   │   ├─ BowlsView
│   │   │   ├─ SimpleBowlView (upper)
│   │   │   └─ SimpleBowlView (lower)
│   │   └─ PlaybackControls
│   │
│   └─ Right Panel (30%)
│       ├─ GameInfoCard
│       ├─ ChatPanel (Phase 4)
│       └─ OGSControlsPanel (Phase 3)
│
└─ Overlays
    ├─ SettingsPanel
    └─ Top buttons (settings gear, fullscreen)
```

---

## ContentView2D

**Purpose**: Main container for 2D board view

**Key Features**:
- 70/30 split layout (board left, metadata right)
- GeometryReader for responsive sizing
- Mouse tracking for button auto-hide
- Overlay management (settings, buttons)

**Dependencies**:
- `@EnvironmentObject` AppModel - app-wide state
- `@StateObject` BoardViewModel - game state
- `@StateObject` LayoutViewModel - layout calculations

**Important**: GeometryReader stays in this view, is NOT extracted to subcomponent

**Usage**:
```swift
ContentView2D(app: appModel)
    .environmentObject(appModel)
```

---

## BoardView2D

**Purpose**: Renders the Go board grid and stones

**Components**:
1. **Board background** - Wood-colored gradient
2. **Grid lines** - Black lines using Canvas
3. **Star points** - Hoshi (9, 13, or 19 board)
4. **Stones layer** - All stones on the board
5. **Last move indicator** - Red circle on last stone
6. **Click handler** - Detect stone placement

**State Sources**:
- `boardVM.stones` - All stones on board
- `boardVM.boardSize` - 9, 13, or 19
- `boardVM.lastMovePosition` - For highlighting
- `layoutVM.boardFrame` - Size and position
- `layoutVM.getStoneSize()` - Stone size

**Click Handling**:
- Converts screen coordinates to board coordinates
- Will place stones in OGS games (Phase 3)
- Currently just logs clicks

---

## SimpleBowlView

**Purpose**: Display captured stones with simple random placement

**Simplification** (vs old code):
- ❌ NO physics simulation
- ❌ NO complex energy minimization
- ❌ NO stone-stone collision
- ✅ Simple random placement in circle
- ✅ Fast and reliable
- ✅ Can add physics later (Phase 6) if desired

**Algorithm**:
```swift
func generateStonePositions() {
    for each stone {
        angle = random(0 to 2π)
        distance = random(0 to 80% of radius)
        position = center + (cos(angle), sin(angle)) * distance
    }
}
```

**Performance**:
- Positions cached in @State
- Regenerated only when count/size changes
- Smooth animation on updates

---

## BowlsView

**Purpose**: Container for both upper and lower bowls

**Layout**:
- Upper bowl: Black captures (white stones)
- Lower bowl: White captures (black stones)

**State**:
- `boardVM.blackCapturedCount` - Number of white stones captured
- `boardVM.whiteCapturedCount` - Number of black stones captured
- `layoutVM.upperBowlCenter` - Position of upper bowl
- `layoutVM.lowerBowlCenter` - Position of lower bowl
- `layoutVM.bowlRadius` - Bowl size

---

## SupportingViews.swift

### TatamiBackground

**Purpose**: Japanese tatami mat background texture

**Implementation**: Simple gradient (greenish-brown)

---

### PlaybackControls

**Purpose**: Navigation buttons for game playback

**Buttons**:
- ⏮ Go to start (`boardVM.goToStart()`)
- ⏪ Previous move (`boardVM.previousMove()`)
- ⏯ Play/Pause (`boardVM.toggleAutoPlay()`)
- ⏩ Next move (`boardVM.nextMove()`)
- ⏭ Go to end (`boardVM.goToEnd()`)

**Styling**:
- White icons on dark background
- Circular button style
- Hover and press animations

---

### GameInfoCard

**Purpose**: Display game metadata and player info

**Displays**:
- Game title
- Black player name
- White player name
- Board size
- Handicap (if any)
- Komi
- Current move number
- Captures (both sides)
- Result (if game complete)

**State**:
- `boardVM.currentGame` - Game metadata
- `boardVM.currentMoveIndex` - Current position
- `boardVM.blackCapturedCount` - Captures by black
- `boardVM.whiteCapturedCount` - Captures by white

---

### SettingsPanel

**Purpose**: Settings overlay (placeholder for Phase 5)

**Features**:
- Slides in from left
- Close button
- Placeholder settings (to be implemented)

---

## Testing (Phase 1.2)

### Visual Tests

**Test 1.2.1: BoardView2D Rendering**
- [ ] Board renders with correct size
- [ ] Grid lines are visible
- [ ] Star points at correct positions
- [ ] Stones render at correct positions
- [ ] Last move indicator shows

**Test 1.2.2: SimpleBowlView**
- [ ] Bowl container renders
- [ ] Stones appear in bowl
- [ ] Stones stay within bowl circle
- [ ] Random placement looks natural

**Test 1.2.3: PlaybackControls**
- [ ] All buttons visible
- [ ] Buttons respond to clicks
- [ ] Play/pause icon toggles
- [ ] Hover effects work

**Test 1.2.4: GameInfoCard**
- [ ] Game title displays
- [ ] Player names display
- [ ] Move counter displays
- [ ] Capture counts display

**Test 1.2.5: ContentView2D Layout**
- [ ] 70/30 split works
- [ ] Board centers in left panel
- [ ] Bowls position correctly
- [ ] Right panel displays metadata

**Test 1.2.6: Responsive Sizing**
- [ ] Window resize updates layout
- [ ] Board stays centered
- [ ] Bowls reposition
- [ ] Components don't overlap

### SwiftUI Previews

All views have `#Preview` blocks for quick testing:

```bash
# Open in Xcode and use Canvas previews
# Or use SwiftUI preview tool
```

---

## Next Steps (Phase 1.3)

**Wire Up Local SGF Playback** (CRITICAL - PRIMARY USE CASE):

1. **Connect to AppModel**:
   - Reference actual SGFPlayer from old code
   - Load games from AppModel.games
   - Wire up SGFPlayer.board to BoardViewModel.stones

2. **Implement Stone Updates**:
   - Parse SGF moves
   - Update board state as user navigates
   - Calculate captures correctly

3. **Test Local Playback**:
   - Load a local SGF file
   - Navigate through moves
   - Verify stones appear correctly
   - Verify captures update
   - Auto-play works

---

## Architecture Principles Followed

✅ **Pure UI** - No business logic in views
✅ **Declarative** - State drives UI updates
✅ **Composable** - Small, focused components
✅ **Testable** - Each view has preview
✅ **No side effects** - All state changes through ViewModels
✅ **Separation of concerns** - Views don't manage state

---

## Key Differences from Old Code

### What We Kept:
- Basic board rendering logic
- Star point positions
- Stone appearance
- Layout algorithm concepts

### What We Improved:
- ✅ **Clean state management** - ViewModels instead of 50+ @State properties
- ✅ **No side effects** - GeometryReader doesn't mutate state directly
- ✅ **Composable views** - Small, focused components
- ✅ **No physics complexity** - Simple random bowl placement
- ✅ **Testable** - Can preview each component

### What We Simplified:
- ❌ **Removed physics simulation** - Too complex, buggy, not essential
- ❌ **Removed caching complexity** - ViewModels handle caching cleanly
- ❌ **Removed duplicate state** - Single source of truth

---

## Reference

**Based on**:
- `CLEAN_ARCHITECTURE_REBUILD_PLAN.md`
- Old code: `/Users/Dave/SGFPlayer/SGFPlayer3D/SGFPlayer3D/ContentView.swift` (lines 464-475, 928-1023)
- Testing: `/Users/Dave/SGFPlayerClean/Documentation/TESTING_CHECKLIST.md`

**Old Components Referenced**:
- SimpleBoardView → BoardView2D
- Responsive layout → LayoutViewModel.calculateLayout()
- Physics bowls → SimpleBowlView (simplified)
- Game info overlay → GameInfoCard
