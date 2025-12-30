# SGFPlayer System Specification

## Overview

SGFPlayer is a comprehensive macOS application for viewing and analyzing SGF (Smart Game Format) Go game files. The application features a sophisticated physics simulation system for realistic captured stone visualization, extensive customization options, and a clean MVVM architecture designed for maintainability and extensibility.

## Core Features

### 1. SGF Game Playback
- **File Management**: Folder-based game library with automatic SGF discovery
- **Playback Control**: Manual navigation and automatic playback with configurable timing
- **Game Navigation**: Forward/backward stepping, seeking to specific moves, jump navigation
- **Visual Feedback**: Last move highlighting, capture visualization, game progress indication

### 2. Physics Simulation System
- **Multiple Physics Models**:
  - Spiral: Deterministic spiral placement for consistent patterns
  - Group Drop: Realistic clustering simulation with stone interaction
  - Energy Minimization: Advanced force simulation with contact propagation
- **Real-time Positioning**: Dynamic stone positioning in capture bowls
- **Performance Optimization**: Cached calculations and debounced updates
- **Visual Realism**: Authentic stone clustering and collision behavior

### 3. User Interface
- **Traditional Aesthetics**: Authentic Go board textures (tatami, kaya wood, stone images)
- **Responsive Layout**: Adaptive sizing based on window dimensions
- **Fullscreen Mode**: Immersive viewing with auto-hiding controls
- **Settings Panel**: Comprehensive physics and visual customization

### 4. Persistence and Caching
- **Game State Persistence**: Automatic restoration of folder and game selection
- **Performance Caching**: Pre-calculated move sequences and capture data
- **Physics Layout Caching**: Cached stone positions for instant navigation
- **User Preferences**: Persistent settings across application sessions

## Technical Architecture

### MVVM Pattern Implementation

The application follows a strict MVVM (Model-View-ViewModel) architecture pattern:

#### Models
- **SGFGame**: Core game data structure containing moves and board state
- **AppModel**: Application-level state management and file system integration
- **PhysicsEngine**: Physics computation coordination and model management
- **GameCacheManager**: Performance optimization through pre-calculation

#### ViewModels
- **SGFPlayerViewModel**: Game state, move navigation, playback control
- **UIStateViewModel**: Window management, fullscreen mode, button visibility
- **PhysicsViewModel**: Physics simulation, stone positioning, performance monitoring
- **SettingsViewModel**: User preferences and configuration management

#### Views
- **ContentView**: Main application interface orchestration
- **GameBoardView**: Traditional Go board rendering with physics integration
- **SettingsPanelView**: Configuration interface for physics and display options

### Physics System Architecture

The physics system employs a strategy pattern for extensible algorithm support:

#### Core Components
- **PhysicsEngine**: Central coordinator managing model selection and execution
- **PhysicsModel Protocol**: Unified interface for pluggable physics algorithms
- **PhysicsIntegration**: Strategic bridge layer for legacy compatibility
- **StonePosition**: Immutable position data with unique identification

#### Physics Models
1. **SpiralPhysicsModel**: Archimedean spiral algorithm for deterministic placement
2. **GroupDropPhysicsModel**: Clustering simulation with realistic interaction
3. **EnergyMinimizationModel**: Force-based simulation with contact propagation

#### Coordinate System
- Physics computations use bowl-relative coordinates (-1.0 to 1.0 range)
- UI rendering transforms to absolute screen coordinates
- Deterministic positioning ensures consistent results across sessions

### Performance Optimizations

#### Caching Strategy
- **Move-based Caching**: Capture counts and board states cached per move
- **Physics Layout Caching**: Stone positions cached to avoid recalculation
- **Background Pre-calculation**: Next 2-3 games pre-calculated for smooth navigation
- **Debounced Updates**: Batched physics updates prevent UI oscillation

#### Memory Management
- **Combine Integration**: Automatic subscription cleanup and memory management
- **Immutable Data Structures**: Thread-safe snapshots preventing state corruption
- **Limited Pre-calculation**: Bounded cache sizes prevent memory issues

## File Structure

### Core Application Files
```
SGFPlayer/
├── SGFPlayerApp.swift              # Application entry point and lifecycle
├── AppModel.swift                  # Core application model and file management
├── ContentView.swift               # Main UI orchestration and MVVM coordination
└── Integration/                    # Legacy compatibility and migration support
    ├── PhysicsIntegration.swift    # Strategic bridge for physics architecture
    ├── CompatibilityLayer.swift    # Legacy system compatibility
    └── ContentViewBridge.swift     # UI integration utilities
```

### ViewModels (MVVM Architecture)
```
ViewModels/
├── SGFPlayerViewModel.swift        # Game state and move navigation
├── UIStateViewModel.swift          # Window management and UI state
├── PhysicsViewModel.swift          # Physics simulation coordination
└── SettingsViewModel.swift         # User preferences and configuration
```

### Views (UI Components)
```
Views/
├── GameBoardView.swift             # Traditional Go board with physics integration
├── SettingsPanelView.swift         # Configuration interface
└── ControlsView.swift              # Playback controls and navigation
```

### Physics System
```
Physics/
├── PhysicsEngine.swift             # Central physics coordinator
├── SpiralPhysicsModel.swift        # Deterministic spiral placement
├── GroupDropPhysicsModel.swift     # Realistic clustering simulation
└── EnergyMinimizationModel.swift   # Advanced force simulation
```

### Core Game Engine
```
├── SGFPlayerEngine.swift           # Go rule implementation and playback
├── PlayerCapturesAdapter.swift     # Legacy capture management
├── StoneJitter.swift               # Animation utilities
└── Cache/
    └── CacheManager.swift          # Performance optimization caching
```

## Data Flow

### Game Loading Sequence
1. **User Selection**: Folder selection through NSOpenPanel
2. **SGF Discovery**: Automatic file scanning and filtering
3. **Parsing**: SGF text parsing into structured game data
4. **Cache Initialization**: Background pre-calculation of game states
5. **UI Update**: Reactive updates through Combine publishers

### Move Playback Sequence
1. **User Input**: Navigation command (manual or automatic)
2. **ViewModel Processing**: SGFPlayerViewModel handles move logic
3. **Capture Calculation**: Efficient capture counting with caching
4. **Physics Update**: Stone positioning calculation through PhysicsViewModel
5. **UI Rendering**: Reactive UI updates through @Published properties

### Physics Calculation Flow
1. **State Change**: Move navigation triggers physics recalculation
2. **Cache Check**: PhysicsViewModel checks for cached layout
3. **Model Selection**: PhysicsEngine delegates to active physics model
4. **Computation**: Algorithm-specific stone positioning calculation
5. **Batched Updates**: Debounced UI updates prevent visual flickering

## Configuration

### Physics Parameters
- **Model Selection**: 6 different physics algorithms with unique characteristics
- **Visual Effects**: Configurable shadows, opacity, and positioning offsets
- **Performance Settings**: Cache limits and update intervals
- **Debug Options**: Detailed logging and diagnostic information

### Display Settings
- **Board Appearance**: Authentic textures and traditional proportions
- **Stone Sizing**: Responsive scaling based on window dimensions
- **Layout Options**: Debug visualization and development overlays
- **Fullscreen Behavior**: Auto-hiding controls and immersive viewing

### Playback Settings
- **Timing Control**: Configurable automatic playback intervals (0.1-5.0 seconds)
- **Navigation Options**: Random game selection and continuous play modes
- **Session Persistence**: Automatic restoration of folder and game selection

## Dependencies

### System Requirements
- **Platform**: macOS 12.0+ (native SwiftUI application)
- **Architecture**: Universal Binary (Intel and Apple Silicon support)
- **File System**: Security-scoped bookmark support for sandboxed access

### Frameworks
- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive programming and data flow management
- **AppKit**: Native macOS integration (file dialogs, window management)
- **Foundation**: Core system services and data structures

## Development Guidelines

### Code Organization
- **MVVM Separation**: Strict separation between UI, business logic, and data
- **Observable Pattern**: Reactive data flow using Combine and @Published properties
- **Protocol-Oriented Design**: Extensible physics system through protocol conformance
- **Error Handling**: Comprehensive error handling with user-friendly feedback

### Performance Considerations
- **Main Thread Safety**: All UI updates on main thread using @MainActor
- **Background Processing**: Non-blocking file operations and physics calculations
- **Memory Efficiency**: Bounded caches and automatic cleanup
- **Responsive UI**: Debounced updates and efficient rendering

### Testing Strategy
- **Unit Testing**: Physics algorithms and game logic validation
- **Performance Testing**: Cache efficiency and memory usage monitoring
- **Integration Testing**: End-to-end game loading and playback verification
- **Visual Testing**: UI layout and physics visualization validation

## Future Development Opportunities

### Planned Enhancements
- **Additional Physics Models**: More sophisticated stone interaction algorithms
- **Game Analysis**: Move analysis and professional game commentary integration
- **Export Features**: Game state export and position sharing capabilities
- **Accessibility**: VoiceOver support and keyboard navigation improvements

### Architecture Evolution
- **Direct Physics Integration**: Removal of compatibility layers for simplified architecture
- **Modular Plugin System**: Extensible physics model loading and configuration
- **Cloud Integration**: Online game library and synchronization support
- **Performance Optimization**: Advanced caching strategies and lazy loading

This specification provides a comprehensive foundation for understanding, maintaining, and extending the SGFPlayer application. The modular architecture and extensive documentation ensure that future developers can effectively contribute to and enhance the system.