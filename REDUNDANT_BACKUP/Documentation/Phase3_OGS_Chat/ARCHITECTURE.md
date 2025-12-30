# SGFPlayer Architecture Documentation

## System Overview

SGFPlayer implements a sophisticated MVVM architecture with reactive data flow, designed for maintainability, testability, and extensibility. The system features a modular physics simulation engine, comprehensive caching mechanisms, and a strategic migration layer enabling incremental modernization of legacy components.

## Architectural Patterns

### 1. Model-View-ViewModel (MVVM)

The application strictly adheres to MVVM principles with clear separation of concerns:

#### Model Layer
- **Data Structures**: Immutable game data, board states, and configuration objects
- **Business Logic**: Go game rules, SGF parsing, and file system operations
- **Persistence**: UserDefaults integration and security-scoped bookmark management

#### ViewModel Layer
- **State Management**: Observable objects with @Published properties for reactive updates
- **Business Logic Coordination**: Game playback control, physics simulation management
- **UI State Abstraction**: Window management, user preferences, and visual state

#### View Layer
- **Pure UI Components**: SwiftUI views with minimal business logic
- **Data Binding**: Reactive updates through Combine and @Published properties
- **User Interaction**: Event handling delegated to ViewModels

### 2. Strategy Pattern (Physics System)

The physics system employs the Strategy pattern for extensible algorithm support:

```swift
protocol PhysicsModel {
    var name: String { get }
    var description: String { get }
    func computeStonePositions(...) -> BowlPhysicsResult
}

class PhysicsEngine: ObservableObject {
    private let models: [PhysicsModel]
    @Published var activeModelIndex: Int
    var activeModel: PhysicsModel { models[activeModelIndex] }
}
```

**Benefits**:
- Runtime algorithm switching without code changes
- Easy addition of new physics models through protocol conformance
- Clean separation between algorithm selection and execution

### 3. Observer Pattern (Reactive Data Flow)

Combine framework provides reactive data flow throughout the system:

```swift
class SGFPlayerViewModel: ObservableObject {
    @Published var autoNext: Bool = false {
        didSet {
            if autoNext {
                player.play()
            } else {
                player.pause()
            }
        }
    }
}
```

**Benefits**:
- Automatic UI updates when data changes
- Decoupled communication between components
- Memory-safe subscriptions with automatic cleanup

### 4. Bridge Pattern (Legacy Integration)

PhysicsIntegration serves as a strategic bridge enabling gradual migration:

```swift
class PhysicsIntegration: ObservableObject {
    @Published var useNewPhysics: Bool = true
    private let physicsReplacement = CompatibilityLayer.createPhysicsReplacement()

    func updateStonePositions(...) {
        if useNewPhysics {
            physicsReplacement.updateStonePositions(...)
        } else {
            // Legacy physics fallback
        }
    }
}
```

**Benefits**:
- Risk-free migration from legacy to new architecture
- Runtime switching between old and new implementations
- Preservation of existing functionality during modernization

## Component Architecture

### Core Application Layer

#### AppModel
- **Purpose**: Central application state management and file system integration
- **Responsibilities**:
  - SGF file discovery and parsing
  - Game library management with alphabetical organization
  - Background pre-calculation coordination
  - Security-scoped bookmark persistence
- **Integration**: Environment object providing global state access

#### SGFPlayerEngine
- **Purpose**: Core Go game rule implementation and move execution
- **Responsibilities**:
  - SGF game loading and initialization
  - Move sequence execution with capture logic
  - Board state management with efficient recomputation
  - Automatic playback with timer coordination
- **Algorithm**: Implements complete Go rules including suicide moves for SGF compatibility

### ViewModel Layer Architecture

#### SGFPlayerViewModel
```swift
class SGFPlayerViewModel: ObservableObject {
    // Core Dependencies
    @Published var player = SGFPlayer()

    // Cached State
    @Published var tallyAtMove: [Int:(w:Int,b:Int)] = [0:(0,0)]
    @Published var gridAtMove: [Int : [[Stone?]]] = [:]

    // Performance Optimization
    private var physicsUpdateTimer: Timer?
    private var pendingPhysicsUpdate: Int?
}
```

**Design Principles**:
- **Caching Strategy**: Move-based caching prevents expensive recalculation
- **Debounced Updates**: Timer-based debouncing prevents rapid-fire physics updates
- **State Isolation**: Clear separation between game logic and UI concerns

#### UIStateViewModel
```swift
class UIStateViewModel: ObservableObject {
    // Window State
    @Published var showFullscreen: Bool = false
    @Published var buttonsVisible: Bool = true

    // Mouse Tracking
    @Published var isMouseMoving: Bool = false
    @Published var lastMouseMoveTime: Date = Date()

    // Bowl Positioning
    @Published var actualUlCenter: CGPoint = CGPoint(x: 150, y: 150)
    @Published var actualLrCenter: CGPoint = CGPoint(x: 650, y: 450)
}
```

**Design Principles**:
- **Transient State Management**: Handles temporary UI states and window controls
- **Input Coordination**: Centralizes mouse tracking and keyboard input handling
- **Layout Coordination**: Manages bowl positioning updates from GameBoardView

#### PhysicsViewModel
```swift
class PhysicsViewModel: ObservableObject {
    // Physics Integration
    @Published var physicsIntegration = PhysicsIntegration()
    @Published var activePhysicsModel: Int = 2

    // Layout Caching
    @Published var layoutAtMove: [Int: LidLayout] = [:]

    // Performance Monitoring
    @Published var updateDuration: TimeInterval = 0
    @Published var stoneCount: Int = 0
}
```

**Design Principles**:
- **Physics Abstraction**: High-level interface to complex physics system
- **Performance Monitoring**: Built-in metrics collection for optimization
- **Cache Management**: Intelligent caching with invalidation strategies

### Physics System Architecture

#### Core Physics Engine
```swift
class PhysicsEngine: ObservableObject {
    private let models: [PhysicsModel] = [
        SpiralPhysicsModel(),
        GroupDropPhysicsModel(),
        EnergyMinimizationModel()
    ]

    @Published var activeModelIndex: Int = 1

    func computeStonePositions(...) -> BowlPhysicsResult {
        return activeModel.computeStonePositions(...)
    }
}
```

#### Physics Model Implementations

**SpiralPhysicsModel**:
- **Algorithm**: Archimedean spiral with color-based angular offset
- **Characteristics**: Deterministic, fast computation, predictable patterns
- **Use Cases**: Baseline physics, performance comparison, testing

**GroupDropPhysicsModel**:
- **Algorithm**: Realistic clustering with stone interaction simulation
- **Characteristics**: Balanced realism and performance, natural grouping
- **Use Cases**: Default physics model, general gameplay visualization

**EnergyMinimizationModel**:
- **Algorithm**: Advanced force simulation with contact propagation
- **Characteristics**: Highly realistic, computationally intensive, complex interactions
- **Use Cases**: Detailed analysis, research applications, maximum realism

#### Coordinate System Design
```swift
struct StonePosition {
    let id: UUID                // Unique identification for tracking
    let position: CGPoint       // Bowl-relative coordinates (-1.0 to 1.0)
    let isWhite: Bool          // Color for physics and rendering
}
```

**Benefits**:
- **UI Independence**: Physics calculations independent of screen dimensions
- **Consistent Results**: Deterministic positioning across different window sizes
- **Efficient Transformation**: Simple scaling for UI rendering

### Integration Layer Architecture

#### PhysicsIntegration Bridge
```swift
class PhysicsIntegration: ObservableObject {
    // Architecture Control
    @Published var useNewPhysics: Bool = true
    private let physicsReplacement = CompatibilityLayer.createPhysicsReplacement()

    // Batching Mechanism
    private var pendingBlackStones: [LegacyCapturedStone] = []
    private var pendingWhiteStones: [LegacyCapturedStone] = []
    private var physicsUpdateTimer: Timer?

    // Reactive Bindings
    private var cancellables = Set<AnyCancellable>()
}
```

**Batching Strategy**:
- **50ms Delay**: Aggregates rapid physics updates for smooth UI transitions
- **Incremental Updates**: Prevents visual blinking through gradual stone addition
- **Timer Management**: Automatic debouncing with cancellation of pending updates

## Data Flow Architecture

### Game Loading Flow
```
User Selection → AppModel.promptForFolder()
    ↓
File Discovery → SGF Parsing → Game Wrapper Creation
    ↓
Cache Initialization → Background Pre-calculation
    ↓
Reactive UI Updates → @Published Property Changes
```

### Move Navigation Flow
```
User Input → SGFPlayerViewModel.moveNext()
    ↓
Player.stepForward() → Board State Update
    ↓
Capture Calculation → Cache Update
    ↓
Physics Update → Stone Positioning
    ↓
UI Rendering → Reactive Property Updates
```

### Physics Calculation Flow
```
Move Change → PhysicsViewModel.updatePhysics()
    ↓
Cache Check → Layout Retrieval or Calculation
    ↓
PhysicsEngine.computeStonePositions()
    ↓
Strategy Pattern → Active Model Execution
    ↓
Result Batching → Debounced UI Updates
```

## Caching Architecture

### Multi-Layer Caching Strategy

#### Level 1: Move-Based Caching (SGFPlayerViewModel)
```swift
@Published var tallyAtMove: [Int:(w:Int,b:Int)] = [0:(0,0)]
@Published var gridAtMove: [Int : [[Stone?]]] = [:]
```
- **Purpose**: Prevents expensive capture recalculation
- **Scope**: Per-game session
- **Invalidation**: Game loading, model changes

#### Level 2: Physics Layout Caching (PhysicsViewModel)
```swift
@Published var layoutAtMove: [Int: LidLayout] = [:]
```
- **Purpose**: Avoids physics recalculation for visited moves
- **Scope**: Per-physics model configuration
- **Invalidation**: Model switching, parameter changes

#### Level 3: Game State Caching (GameCacheManager)
```swift
class GameCacheManager {
    func preCalculateGame(_ game: SGFGame, fingerprint: String)
    func getCachedCaptures(gameFingerprint: String, moveIndex: Int) -> (Int, Int)?
}
```
- **Purpose**: Cross-session persistence and background pre-calculation
- **Scope**: Application lifetime
- **Invalidation**: Manual cleanup, memory pressure

### Cache Coordination
- **Hierarchical Lookup**: L1 → L2 → L3 → Calculation
- **Background Population**: Non-blocking pre-calculation of next games
- **Memory Management**: Bounded cache sizes with LRU eviction
- **Consistency**: Automatic invalidation on relevant state changes

## Performance Architecture

### Optimization Strategies

#### 1. Reactive Data Flow Optimization
```swift
private func setupPlayerBindings() {
    player.objectWillChange
        .sink { [weak self] in
            self?.updateGameInfo()
        }
        .store(in: &cancellables)
}
```
- **Benefit**: Automatic UI updates without manual coordination
- **Implementation**: Combine publishers with weak reference cycles
- **Memory Safety**: Automatic cancellation prevents memory leaks

#### 2. Debounced Physics Updates
```swift
private func schedulePhysicsUpdate() {
    physicsUpdateTimer?.invalidate()
    pendingPhysicsUpdate = currentMoveIndex

    physicsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
        self?.executePhysicsUpdate()
    }
}
```
- **Benefit**: Prevents excessive computation during rapid navigation
- **Implementation**: Timer-based debouncing with state tracking
- **User Experience**: Smooth navigation without performance degradation

#### 3. Background Pre-calculation
```swift
func selectGame(_ gameWrapper: SGFGameWrapper) {
    // Immediate selection
    selection = gameWrapper
    gameCacheManager.loadGame(gameWrapper.game, fingerprint: gameWrapper.fingerprint)

    // Background pre-calculation
    for i in 1...min(2, games.count - currentIndex - 1) {
        let nextGame = games[currentIndex + i]
        gameCacheManager.preCalculateGame(nextGame.game, fingerprint: nextGame.fingerprint)
    }
}
```
- **Benefit**: Instant navigation to pre-calculated games
- **Implementation**: Limited background processing prevents memory issues
- **Resource Management**: Bounded pre-calculation prevents system overload

#### 4. Immutable State Architecture
```swift
struct BoardSnapshot {
    let size: Int
    let grid: [[Stone?]]
}

@Published private(set) var board: BoardSnapshot
```
- **Benefit**: Thread-safe access without defensive copying
- **Implementation**: Immutable data structures with controlled mutation
- **Memory Efficiency**: Structural sharing reduces memory footprint

## Error Handling Architecture

### Defensive Programming Strategies

#### 1. Safe Array Access
```swift
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
```

#### 2. Graceful Degradation
```swift
var activeModel: PhysicsModel {
    models[safe: activeModelIndex] ?? models[0]
}
```

#### 3. Comprehensive Logging
```swift
func updateStonePositions(...) {
    if debugMode {
        print("🚀 PhysicsIntegration: Move \(currentMove), Black: \(blackStoneCount), White: \(whiteStoneCount)")
    }
}
```

### Error Recovery Patterns
- **Fallback Values**: Default configurations when preferences are corrupted
- **State Reset**: Clean reset mechanisms for recovery from invalid states
- **Graceful Degradation**: Reduced functionality rather than application failure
- **User Feedback**: Clear error messages with actionable recovery steps

## Testing Architecture

### Testability Design Principles

#### 1. Dependency Injection
```swift
class PhysicsViewModel: ObservableObject {
    private let physicsEngine: PhysicsEngine

    init(physicsEngine: PhysicsEngine = PhysicsEngine()) {
        self.physicsEngine = physicsEngine
    }
}
```

#### 2. Protocol-Based Abstractions
```swift
protocol PhysicsModel {
    func computeStonePositions(...) -> BowlPhysicsResult
}

// Test implementations can conform to protocol
class MockPhysicsModel: PhysicsModel { ... }
```

#### 3. Observable State
```swift
// ViewModels expose @Published properties for testing
@Published var isAnimating: Bool = false
@Published var updateDuration: TimeInterval = 0
```

### Testing Strategy
- **Unit Tests**: Pure functions and business logic validation
- **Integration Tests**: Component interaction and data flow verification
- **Performance Tests**: Cache efficiency and physics computation benchmarks
- **UI Tests**: User interaction flows and visual state validation

## Security Architecture

### Sandboxing Compliance
```swift
private func persistFolderURL() {
    guard let url = folderURL else { return }
    do {
        let bookmark = try url.bookmarkData(options: .withSecurityScope, ...)
        UserDefaults.standard.set(bookmark, forKey: folderKey)
    } catch {
        print("❗️Failed to persist folder URL: \(error)")
    }
}
```

### Data Protection
- **Security-Scoped Bookmarks**: Persistent file access without storing paths
- **Sandboxed File Access**: Compliant with macOS security requirements
- **Memory Safety**: Swift's memory management prevents common vulnerabilities
- **Input Validation**: Robust SGF parsing with error handling

## Migration Strategy

### Current Architecture Evolution
1. **Phase 1** (Current): Bridge pattern with new physics backend
2. **Phase 2** (Planned): Legacy code removal and API simplification
3. **Phase 3** (Future): Direct physics integration without compatibility layers

### Migration Benefits
- **Risk Mitigation**: Gradual replacement reduces introduction of bugs
- **Feature Preservation**: Existing functionality maintained during modernization
- **Performance Improvement**: New architecture provides better performance characteristics
- **Maintainability**: Cleaner code structure improves long-term maintainability

This architecture documentation provides the technical foundation for understanding, maintaining, and extending the SGFPlayer system. The modular design, comprehensive caching, and strategic migration approach ensure the system remains maintainable and extensible for future development.