# SGFPlayerClean - Clean Architecture Rebuild

**Created**: 2025-11-19
**Purpose**: Fresh rebuild of SGF Player with clean, maintainable architecture

## Project Structure

```
SGFPlayerClean/
├── ViewModels/          # State management & business logic
│   ├── BoardViewModel.swift
│   ├── LayoutViewModel.swift
│   └── OGSGameViewModel.swift (reference old code)
│
├── Views/               # SwiftUI views (pure UI)
│   ├── ContentView2D.swift
│   ├── ContentView3D.swift
│   ├── BoardView.swift
│   ├── SimpleBowlView.swift
│   ├── ChatPanel.swift
│   └── OGSControlsPanel.swift
│
├── Models/              # Data structures
│   ├── Stone.swift
│   ├── BoardPosition.swift
│   └── GameState.swift
│
├── Services/            # External integrations
│   ├── OGSService.swift
│   └── SoundService.swift
│
└── Documentation/       # Architecture docs
    ├── ARCHITECTURE.md
    └── MIGRATION_GUIDE.md
```

## Key Principles

1. **Separation of Concerns** - ViewModels handle state, Views handle UI
2. **Single Source of Truth** - No duplicate state
3. **Testability** - ViewModels can be tested without UI
4. **2D & 3D Support** - Both modes use same ViewModels
5. **Local Mode First** - SGF playback is primary use case
6. **OGS Second** - Live games built on top

## Reference Old Code

Located at: `/Users/Dave/SGFPlayer/SGFPlayer3D/SGFPlayer3D/`

Reference but don't copy the entangled architecture.

## Build Phases

- [ ] Phase 1: Local SGF playback (2D)
- [ ] Phase 2: Responsive layout + bowls
- [ ] Phase 3: OGS integration
- [ ] Phase 4: Chat feature
- [ ] Phase 5: 3D mode support
- [ ] Phase 6: Polish & migration

## Next Steps

See: `/Users/Dave/SGFPlayer/CLEAN_ARCHITECTURE_REBUILD_PLAN.md`
