# SGFPlayerClean - User Guide

Welcome to SGFPlayerClean! This is a modern macOS Go/Baduk game viewer.

## Quick Start

### Opening a Game
1. Launch the app
2. Press **Cmd+O** (or menu File → Open SGF File...)
3. Select an .sgf file from your computer
4. The game loads instantly

### Navigating the Game

#### Using Keyboard (Recommended)
- **`←`** Previous move
- **`→`** Next move
- **`↑`** Jump to start
- **`↓`** Jump to end
- **`Space`** Play/Pause auto-play

#### Using Mouse
Click the playback controls at the bottom of the board:
- **⏮** Go to start
- **◀️** Previous move
- **▶️** Play/Pause
- **▶️** Next move
- **⏭** Go to end

## Interface Overview

```
┌─────────────────────────────────────────────────────┐
│  ⚙️                                         ⛶      │  Settings & Fullscreen
├──────────────────────┬──────────────────────────────┤
│                      │                              │
│                      │  Game Information            │
│      Go Board        │  - Players                   │
│     (70% width)      │  - Rank                      │
│                      │  - Date                      │
│                      │  - Result                    │
│                      │                              │
│                      │                              │
│                      │  (Chat - Phase 4)            │
│                      │                              │
│     ⏮ ◀️ ▶️ ▶️ ⏭       │                              │
│                      │                              │
└──────────────────────┴──────────────────────────────┘
```

## Features

### Current (Phase 1.3)
✅ Load SGF files (Cmd+O)
✅ Navigate moves (arrows/buttons)
✅ Auto-play (space bar)
✅ Responsive layout
✅ Smooth performance

### Coming Soon
- Coordinate labels (A-T, 1-19)
- Move numbers overlay
- Variation branches
- Analysis tools
- OGS integration

## Settings

Click the **⚙️** gear icon to access settings:
- Auto-play speed
- Board theme
- Stone style
- Sound effects

## Keyboard Shortcuts

### Navigation
| Key | Action |
|-----|--------|
| `←` | Previous move |
| `→` | Next move |
| `↑` | Go to start |
| `↓` | Go to end |
| `Space` | Play/Pause |

### File Operations
| Key | Action |
|-----|--------|
| `Cmd+O` | Open SGF file |
| `Cmd+W` | Close window |
| `Cmd+Q` | Quit app |

### Window
| Key | Action |
|-----|--------|
| `Cmd+F` | Toggle fullscreen |

## Tips & Tricks

### Rapid Review
1. Load a game
2. Press `Space` to start auto-play
3. Watch the game unfold automatically

### Study a Position
1. Navigate to the position you want to study
2. The board shows the current state
3. Use `←` and `→` to see how it developed

### Check Game Info
Look at the right panel to see:
- Player names and ranks
- Game date and location
- Rules and komi
- Final result

## Troubleshooting

### App Not Responding
- **Check CPU**: Should be 0% when idle
- **Restart**: Cmd+Q and relaunch
- **Report**: If persistent, check logs

### File Won't Load
- **Format**: Must be .sgf extension
- **Encoding**: Should be UTF-8
- **Syntax**: SGF format must be valid

### Performance Issues
- This version is optimized for 0% CPU usage
- If you see high CPU, please report!

## Sample SGF Files

Looking for games to view? Find SGF files at:
- **GoKifu.com**: Professional game records
- **OGS**: Online Go Server game archives
- **KGS**: KGS Go Server archives
- **Your own games**: Export from any Go app

## Support

### Documentation
- [FEATURES.md](FEATURES.md) - Complete feature list
- [SPINNING_BALL_FIX.md](SPINNING_BALL_FIX.md) - Performance fix details
- [COMPLETION_STATUS.md](COMPLETION_STATUS.md) - Development status

### Issues
Found a bug? Have a suggestion?
- Performance should be 0% CPU when idle
- All major features should work smoothly

## System Requirements

### Minimum
- macOS 13.0 (Ventura) or later
- 4GB RAM
- 100MB disk space

### Recommended
- macOS 14.0 (Sonoma) or later
- 8GB RAM
- 200MB disk space (for game library)

## Version History

### v1.3 (2025-11-20) - Current
- ✅ Fixed spinning ball (infinite loop) bug
- ✅ Added file picker (Cmd+O)
- ✅ Added keyboard shortcuts
- ✅ Optimized performance to 0% CPU
- ✅ Full SGF parsing support

### Coming in v1.4
- Coordinate labels
- Move numbers
- Game tree visualization
- Preferences panel

---

**Enjoy reviewing Go games!** 🎮
