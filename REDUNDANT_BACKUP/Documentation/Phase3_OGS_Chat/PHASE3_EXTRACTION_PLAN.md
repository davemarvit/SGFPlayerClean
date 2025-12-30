# Phase 3: ContentView3D Component Extraction Plan

**Date**: 2025-10-16
**Current ContentView3D**: 1,361 lines
**Target**: ~500-600 lines

## Overview

This document details the exact line-by-line extraction plan for Phase 3. This documentation serves as both a guide for the refactoring and a reference for reverting changes if bugs are introduced.

---

## Component 1: GameInfoOverlay

**Purpose**: Display all game metadata and player information
**Location in ContentView3D**: Lines 446-597 (152 lines)
**Target file**: `SGFPlayer3D/Views/GameInfoOverlay.swift`

### What's Being Extracted

```swift
// Lines 446-597 of ContentView3D.swift
VStack(alignment: .trailing, spacing: 4) {
    // Player names with ranks (lines 448-496)
    HStack(spacing: 8) {
        // Black player info (OGS mode or local game)
        // White player info (OGS mode or local game)
    }

    // Time remaining - OGS only (lines 498-546)
    if ogsGame?.blackName != nil {
        HStack(spacing: 12) {
            // Black time with periods
            // White time with periods
        }
    }

    // Captures (lines 548-564)
    HStack(spacing: 12) {
        // Black captures
        // White captures
    }

    // Komi and ruleset (lines 566-578)
    HStack(spacing: 12) {
        // Komi display
        // Ruleset display
    }

    // Move counter (lines 580-583)
    Text("Move \(player.currentIndex) / \(player.moves.count)")
}
```

### Dependencies Required

- `@ObservedObject var ogsGame: OGSGameViewModel?` (or passed as optional)
- `@ObservedObject var timeControl: TimeControlManager`
- `@ObservedObject var player: SGFPlayer`
- `@Binding var gameSelection: GameWrapper?` (for local game mode)
- `formatTime(_ seconds: TimeInterval) -> String` helper function

### Integration in ContentView3D After Extraction

Replace lines 446-597 with:
```swift
GameInfoOverlay(
    ogsGame: ogsGame,
    timeControl: timeControl,
    player: player,
    gameSelection: app.selection
)
.padding()
```

---

## Component 2: PlaybackControls

**Purpose**: Handle game playback navigation
**Location in ContentView3D**: Lines 611-658 (48 lines)
**Target file**: `SGFPlayer3D/Views/PlaybackControls.swift`

### What's Being Extracted

```swift
// Lines 611-658 of ContentView3D.swift
HStack(spacing: 12) {
    // Backward button (lines 613-622)
    Button(action: {
        player.seek(to: max(0, player.currentIndex - 1))
        updateStonesWithJitter()
    }) {
        Image(systemName: "backward.fill")
    }

    // Play/pause button (lines 624-632)
    Button(action: { togglePlayPause() }) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    }

    // Forward button (lines 634-643)
    Button(action: {
        player.seek(to: min(player.moves.count, player.currentIndex + 1))
        updateStonesWithJitter()
    }) {
        Image(systemName: "forward.fill")
    }

    // Seek slider (lines 645-652)
    Slider(value: Binding(
        get: { Double(player.currentIndex) },
        set: { newValue in
            player.seek(to: Int(newValue))
            updateStonesWithJitter()
        }
    ), in: 0...Double(max(1, player.moves.count)), step: 1)
}
.padding(.horizontal, 20)
.padding(.vertical, 12)
.background(.ultraThinMaterial)
.cornerRadius(8)
.padding(.bottom, 20)
```

### Dependencies Required

- `@ObservedObject var player: SGFPlayer`
- `@Binding var isPlaying: Bool`
- `let onSeek: () -> Void` (callback for updateStonesWithJitter)
- `let onTogglePlayPause: () -> Void` (callback)

### Integration in ContentView3D After Extraction

Replace lines 611-658 with:
```swift
PlaybackControls(
    player: player,
    isPlaying: $isPlaying,
    onSeek: updateStonesWithJitter,
    onTogglePlayPause: togglePlayPause
)
```

---

## Component 3: SettingsPanelContainer

**Purpose**: Manage settings panel presentation with overlay
**Location in ContentView3D**: Lines 393-419 (27 lines)
**Target file**: `SGFPlayer3D/Views/SettingsPanelContainer.swift`

### What's Being Extracted

```swift
// Lines 393-419 of ContentView3D.swift
HStack {
    SettingsPanelView3D(
        isPanelOpen: $showSettings,
        app: app,
        player: player,
        settingsVM: settingsVM,
        soundManager: soundManager,
        ogsClient: ogsClient,
        autoPlay: $isPlaying,
        playbackSpeed: $playbackSpeed,
        onGameSelected: { game in
            player.load(game: game.game)
            player.seek(to: 0)
            updateStonesWithJitter()
        },
        onJitterChanged: {
            NSLog("DEBUG3D: 🎲 onJitterChanged callback triggered")
            updateStonesWithJitter()
        }
    )
    .transition(.move(edge: .leading))

    Spacer()
}
.zIndex(100)
```

### Dependencies Required

- `@Binding var showSettings: Bool`
- `@EnvironmentObject var app: AppModel`
- `@ObservedObject var player: SGFPlayer`
- `@ObservedObject var settingsVM: SettingsViewModel`
- `@ObservedObject var soundManager: SoundManager`
- `@ObservedObject var ogsClient: OGSClient`
- `@Binding var isPlaying: Bool`
- `@Binding var playbackSpeed: Double`
- `let onGameSelected: (GameWrapper) -> Void`
- `let onJitterChanged: () -> Void`

### Integration in ContentView3D After Extraction

Replace lines 393-419 with:
```swift
SettingsPanelContainer(
    showSettings: $showSettings,
    app: app,
    player: player,
    settingsVM: settingsVM,
    soundManager: soundManager,
    ogsClient: ogsClient,
    isPlaying: $isPlaying,
    playbackSpeed: $playbackSpeed,
    onGameSelected: { game in
        player.load(game: game.game)
        player.seek(to: 0)
        updateStonesWithJitter()
    },
    onJitterChanged: {
        NSLog("DEBUG3D: 🎲 onJitterChanged callback triggered")
        updateStonesWithJitter()
    }
)
```

---

## Helper Function to Extract

**Function**: `formatTime(_ seconds: TimeInterval) -> String`
**Location**: Lines 780-791 (12 lines)
**Target**: Move to GameInfoOverlay.swift as a private function

---

## Expected Line Count Changes

| File | Before | After | Change |
|------|--------|-------|--------|
| ContentView3D.swift | 1,361 | ~600 | -761 |
| GameInfoOverlay.swift | 0 | ~180 | +180 |
| PlaybackControls.swift | 0 | ~80 | +80 |
| SettingsPanelContainer.swift | 0 | ~60 | +60 |
| **Net Change** | | | **-441 lines** |

---

## Extraction Order & Testing

### Step 1: Extract GameInfoOverlay
1. Create `SGFPlayer3D/Views/GameInfoOverlay.swift`
2. Copy lines 446-597 + helper function (lines 780-791)
3. Wrap in struct with proper bindings
4. Update ContentView3D to use new component
5. **Build and test** - verify display is identical

### Step 2: Extract PlaybackControls
1. Create `SGFPlayer3D/Views/PlaybackControls.swift`
2. Copy lines 611-658
3. Replace direct calls with callbacks
4. Update ContentView3D to use new component
5. **Build and test** - verify playback works

### Step 3: Extract SettingsPanelContainer
1. Create `SGFPlayer3D/Views/SettingsPanelContainer.swift`
2. Copy lines 393-419
3. Simplify bindings
4. Update ContentView3D to use new component
5. **Build and test** - verify settings panel works

### Step 4: Run Full Test Suite
```bash
xcodebuild test -project SGFPlayer3D.xcodeproj -scheme SGFPlayer3D -destination 'platform=macOS'
```

Verify all 21 tests still pass.

### Step 5: Commit
Create detailed commit message documenting all changes.

---

## Rollback Plan

If bugs are introduced:

1. **Identify which component** introduced the bug
2. **Check this document** to see exactly what was moved
3. **Revert options**:
   - Revert entire Phase 3: `git revert <commit-sha>`
   - Revert specific file: `git restore SGFPlayer3D/Views/GameInfoOverlay.swift SGFPlayer3D/ContentView3D.swift`
   - Fix forward: Use line numbers in this document to identify issue

---

## Success Criteria

- ✅ Build succeeds with no warnings
- ✅ All 21 unit tests pass
- ✅ Game loading displays correctly
- ✅ Player info shows correctly (OGS and local modes)
- ✅ Time clocks count down correctly
- ✅ Playback controls work (forward, backward, play/pause, slider)
- ✅ Settings panel opens and closes correctly
- ✅ No visual regressions
- ✅ ContentView3D reduced to ~600 lines

---

**End of Phase 3 Extraction Plan**
