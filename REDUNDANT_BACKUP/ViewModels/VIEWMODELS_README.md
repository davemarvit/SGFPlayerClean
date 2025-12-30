# ViewModels - Clean Architecture

**Created**: 2025-11-19
**Phase**: 1.1 (Foundation)

## Overview

These ViewModels manage all state and business logic for the SGF Player, following clean architecture principles:

- **Separation of Concerns**: ViewModels handle state, Views handle UI
- **Single Source of Truth**: Each piece of state has one owner
- **Testable**: Can be unit tested without UI
- **Shared by 2D & 3D**: Both ContentView2D and ContentView3D use the same ViewModels

---

## BoardViewModel

**Purpose**: Manages game state, move navigation, and local SGF playback

**Key Responsibilities**:
- Load local SGF files (PRIMARY use case)
- Navigate through moves (prev/next/seek)
- Auto-play mode
- Calculate captured stones
- Track board state
- Handle OGS live games (Phase 3)

**Published State**:
```swift
@Published var currentMoveIndex: Int = 0
@Published var stones: [BoardPosition: Stone] = [:]
@Published var lastMovePosition: BoardPosition?
@Published var blackCapturedCount: Int = 0
@Published var whiteCapturedCount: Int = 0
@Published var isAutoPlaying: Bool = false
```

**Key Methods**:
- `loadGame(_ game: SGFGameWrapper)` - Load local SGF file
- `seekToMove(_ index: Int)` - Jump to specific move
- `nextMove()` / `previousMove()` - Navigate moves
- `toggleAutoPlay()` - Start/stop auto-play
- `placeStone(at:color:)` - For OGS live games (Phase 3)

**Optimizations**:
- Caches board state at each move (performance)
- Caches capture counts (performance)

---

## LayoutViewModel

**Purpose**: Manages responsive layout calculations for 2D view

**Key Responsibilities**:
- Calculate board size based on window size
- Position board within container
- Position capture bowls
- Convert between board coordinates and screen coordinates
- Handle window resize

**Published State**:
```swift
@Published var boardFrame: CGRect = .zero
@Published var boardCenter: CGPoint = .zero
@Published var boardCenterX: CGFloat = 0
@Published var upperBowlCenter: CGPoint = .zero
@Published var lowerBowlCenter: CGPoint = .zero
@Published var bowlRadius: CGFloat = 100
```

**Key Methods**:
- `calculateLayout(containerSize:boardSize:leftPanelWidth:)` - Main layout calculation
- `handleResize(newSize:boardSize:leftPanelWidth:)` - Window resize handler
- `boardToScreen(row:col:boardSize:)` - Convert board coords to screen
- `screenToBoard(_:boardSize:)` - Convert screen coords to board
- `getStoneSize(boardSize:)` - Calculate stone size

**Important**: GeometryReader stays in ContentView2D (not in ViewModel)

---

## Usage Pattern

### In ContentView2D:

```swift
struct ContentView2D: View {
    @EnvironmentObject var app: AppModel
    @StateObject var boardVM = BoardViewModel()
    @StateObject var layoutVM = LayoutViewModel()

    var body: some View {
        GeometryReader { geometry in
            // Calculate layout (NO side effects in GeometryReader!)
            let _ = layoutVM.calculateLayout(
                containerSize: geometry.size,
                boardSize: boardVM.boardSize
            )

            HStack(spacing: 0) {
                // Left Panel (70%) - Board
                ZStack {
                    BoardView2D(
                        boardVM: boardVM,
                        layoutVM: layoutVM
                    )
                }
                .frame(width: geometry.size.width * 0.7)

                // Right Panel (30%) - Metadata + Chat
                RightPanel(
                    boardVM: boardVM
                )
                .frame(width: geometry.size.width * 0.3)
            }
        }
        .onAppear {
            // Load first game
            if let firstGame = app.games.first {
                boardVM.loadGame(firstGame)
            }
        }
    }
}
```

---

## Testing (Phase 1.1)

### BoardViewModel Tests

**Test 1.1.1: Initialization**
- [x] BoardViewModel initializes with empty state
- [x] No crashes

**Test 1.1.2: Load Game**
- [ ] `loadGame()` clears previous state
- [ ] Board size set correctly
- [ ] Move index reset to 0

**Test 1.1.3: Navigation**
- [ ] `nextMove()` increments index
- [ ] `previousMove()` decrements index
- [ ] `seekToMove()` clamps to valid range
- [ ] Can't go below 0
- [ ] Can't go above totalMoves

**Test 1.1.4: Auto-Play**
- [ ] `startAutoPlay()` creates timer
- [ ] Timer advances moves
- [ ] `stopAutoPlay()` cleans up timer
- [ ] Stops at end of game

### LayoutViewModel Tests

**Test 1.1.5: Layout Calculation**
- [ ] Calculates board frame correctly
- [ ] Board is square
- [ ] Board respects min/max size
- [ ] Centers board in container

**Test 1.1.6: Bowl Positioning**
- [ ] Upper bowl above board
- [ ] Lower bowl below board
- [ ] Bowl size scales with board

**Test 1.1.7: Coordinate Conversion**
- [ ] `boardToScreen()` returns correct screen point
- [ ] `screenToBoard()` returns correct board coords
- [ ] `screenToBoard()` returns nil for out-of-bounds

**Test 1.1.8: Window Resize**
- [ ] `handleResize()` recalculates layout
- [ ] Board stays centered
- [ ] Bowls reposition correctly

---

## Next Steps (Phase 1.2)

**Views to Create**:
1. `ContentView2D.swift` - Main container
2. `BoardView2D.swift` - Board grid + stones
3. `SimpleBowlView.swift` - Random stone placement

**Then**: Wire up to SGFPlayer for local playback (Phase 1.3)

---

## Architecture Principles Followed

✅ **No side effects** - ViewModels update @Published properties, views react
✅ **Pure calculations** - LayoutViewModel has no side effects in calculations
✅ **Dependency injection** - Dependencies passed via init
✅ **Single source of truth** - No duplicate state
✅ **Testable** - Can unit test without SwiftUI
✅ **Clean separation** - State in ViewModels, UI in Views

---

## Reference

**Based on**: `CLEAN_ARCHITECTURE_REBUILD_PLAN.md`
**Old code reference**: `/Users/Dave/SGFPlayer/SGFPlayer3D/SGFPlayer3D/ContentView.swift`
**Testing checklist**: `/Users/Dave/SGFPlayerClean/Documentation/TESTING_CHECKLIST.md`
