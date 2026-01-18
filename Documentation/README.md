# SGFPlayerClean Documentation

Documentation and reference implementations for future development phases.

## Current Status

**Phase 1 & 2: COMPLETE**
- 2D board rendering with traditional Go board aesthetics
- SGF file parsing and playback
- Auto-play with configurable timing
- Stone jitter for natural placement
- Move indicators (circle, dot, move numbers, coordinates)
- Glow effects for last move
- Settings panel with all playback controls
- Game library with folder selection
- Folder playback settings (auto-start, shuffle)

## Future Development Phases

### Phase 3: OGS Integration & Chat

**Documentation:** [Phase3_OGS_Chat/](Phase3_OGS_Chat/)

Integration with Online Go Server (OGS) for live play and chat functionality.

**Key Features:**
- WebSocket connection to OGS
- Authentication and user management
- Real-time game observation
- Live game play (make moves)
- Chat system (game chat, private messages)
- Time control management
- Game list and player info

**Reference Files:**
- OGSClient.swift - WebSocket client implementation
- OGSModels.swift - Data models for OGS
- OGSGameViewModel.swift - Game management ViewModel
- Multiple protocol documentation files

**Status:** Not started

---

### Phase 4: 3D Board Visualization

**Documentation:** [Phase4_3D_Board/](Phase4_3D_Board/)

Beautiful 3D rendering of the Go board using SceneKit.

**Key Features:**
- SceneKit-based 3D board
- Realistic stone materials and textures
- Smooth camera controls (orbit, zoom, pan)
- Stone placement animations
- Capture animations with physics
- Lighting and shadows
- Performance optimization

**Reference Files:**
- ContentView3D.swift - 3D view implementation
- SceneManager3D.swift - Scene management
- SPECIFICATION.md - Technical specifications
- TEXTURED_STONES_RESEARCH.md - Material research

**Status:** Not started

---

## Architecture Overview

### Current Architecture (Phase 1-2)

```
SGFPlayerClean/
├── Models/
│   ├── SGFKit.swift              # SGF parsing
│   ├── SGFPlayerEngine.swift     # Game playback engine
│   ├── SGFGameWrapper.swift      # Game metadata wrapper
│   ├── AppSettings.swift         # Centralized settings
│   ├── StoneJitter.swift         # Stone positioning
│   └── BoardSnapshot.swift       # Board state capture
├── ViewModels/
│   ├── BoardViewModel.swift      # Board state management
│   └── LayoutViewModel.swift     # Responsive layout
├── Views/
│   ├── ContentView2D.swift       # Main 2D view
│   ├── BoardView2D.swift         # 2D board rendering
│   ├── SupportingViews.swift     # Settings & controls
│   └── SimpleBowlView.swift      # Captured stones display
└── SGFPlayerCleanApp.swift       # App entry point
```

### Future Architecture (Phase 3-4)

```
SGFPlayerClean/
├── Models/
│   ├── [Phase 1-2 files]
│   ├── OGSModels.swift           # Phase 3: OGS data models
│   └── [3D models if needed]
├── Services/
│   └── OGSClient.swift           # Phase 3: WebSocket client
├── ViewModels/
│   ├── [Phase 1-2 files]
│   ├── OGSGameViewModel.swift    # Phase 3: OGS game management
│   └── SceneManager3D.swift      # Phase 4: 3D scene management
└── Views/
    ├── [Phase 1-2 files]
    ├── ChatView.swift            # Phase 3: Chat interface
    ├── OGSGameListView.swift     # Phase 3: Game browser
    └── ContentView3D.swift       # Phase 4: 3D board view
```

## Development Guidelines

### Code Style
- SwiftUI for all UI components
- MVVM architecture
- Combine for reactive programming
- Clear separation of concerns
- Extensive comments for complex logic

### File Organization
- Group files by feature/phase
- Keep models separate from views
- ViewModels bridge models and views
- Shared utilities in separate folder

### Documentation
- Document all public APIs
- Include usage examples
- Explain architectural decisions
- Keep documentation updated

### Testing
- Unit tests for models
- Integration tests for ViewModels
- UI tests for critical workflows
- Performance benchmarks for animations

## Getting Started with Future Phases

### Phase 3: OGS Integration

1. Read [Phase3_OGS_Chat/README.md](Phase3_OGS_Chat/README.md)
2. Study OGSClient.swift reference implementation
3. Review OGS protocol documentation
4. Start with basic WebSocket connection
5. Implement authentication
6. Add game observation
7. Implement chat system

**Estimated Effort:** 3-4 weeks

### Phase 4: 3D Board

1. Read [Phase4_3D_Board/README.md](Phase4_3D_Board/README.md)
2. Study ContentView3D.swift and SceneManager3D.swift
3. Review SceneKit documentation
4. Start with basic board geometry
5. Add stone rendering
6. Implement camera controls
7. Add animations and polish

**Estimated Effort:** 2-3 weeks

## Resources

### Apple Documentation
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [Combine](https://developer.apple.com/documentation/combine)
- [SceneKit](https://developer.apple.com/documentation/scenekit)
- [URLSession](https://developer.apple.com/documentation/foundation/urlsession) (for WebSocket)

### Go Game Resources
- [Sensei's Library](https://senseis.xmp.net/)
- [OGS API](https://online-go.com/docs/api)
- [SGF Format](https://www.red-bean.com/sgf/)

### Design Resources
- Traditional Go board proportions (15:14 cell ratio)
- Stone sizes and materials
- Board aesthetics and textures

## Notes

- All reference implementations are copied from the working SGFPlayer3D_backup
- These are tested, working implementations that can be adapted
- Focus on clean architecture and maintainability
- Performance is critical for real-time features (OGS, 3D)
- User experience should be smooth and intuitive
