# OGS Live Play Implementation Plan

**Last Updated:** 2025-10-18
**Current Status:** Stage 1 - COMPLETE ✅
**Current Session:** Session 2 - Stage 1 Foundation Complete

---

## Overview & Goals

Transform SGFPlayer3D from a game viewer into a full OGS live game player while maintaining the clean, uncluttered interface.

**Key Constraints:**
- Live games only (no correspondence)
- One game at a time (simplifies UX)
- Use dimmed board space for pre-game UI
- Context-aware controls (switch based on game state)
- Maintain current auto-hide behavior

**Success Criteria:**
- Can find and join automatch games
- Can send and receive challenges
- Can place stones and make moves
- Can pass, resign, and complete games
- Works in both 2D and 3D modes

---

## Implementation Stages

### **Stage 1: Foundation & UI Structure** ✅ COMPLETE

**Goal:** Create the basic structure for game state management and pre-game overlay

#### 1.1 Game State Management
- [x] Add `GamePhase` enum: `.preGame`, `.playing`, `.scoring`, `.finished`
- [x] Track `currentGamePhase` in OGSClient
- [x] Add `isMyTurn: Bool` property (already existed)
- [x] Add `myColor: Stone?` property (uses existing `playerColor`)
- [x] Add game state observation/publishing (@Published on gamePhase)

**Files modified:**
- `SGFPlayer3D/OGSClient.swift`

#### 1.2 Pre-Game Overlay Component
- [x] Create `Views/PreGameOverlay.swift` view component
- [x] Design overlay with semi-transparent background over dimmed board
- [x] Add show/hide based on `gamePhase`
- [x] Position centered over board area
- [x] Test in both 2D and 3D modes

**New files:**
- `SGFPlayer3D/Views/PreGameOverlay.swift`

**Files modified:**
- `SGFPlayer3D/ContentView.swift` (add overlay)
- `SGFPlayer3D/ContentView3D.swift` (add overlay)

#### 1.3 Game Parameter State
- [x] Create `Models/GameSettings.swift` struct with:
  - `boardSize: Int` (19, 13, 9)
  - `rankRange: RankRange` enum (±1, ±2, ±3, Any) with Codable
  - `timeControl: TimeControlPreset` enum (Blitz, Rapid, Fischer) with Codable
  - `colorPreference: ColorPreference` enum (Auto, Black, White) with Codable
- [x] Add persistence to UserDefaults (load/save methods)
- [x] Create UI controls in PreGameOverlay for each setting
- [x] Add preset time control definitions (in seconds/periods)

**New files:**
- `SGFPlayer3D/Models/GameSettings.swift`

**Implementation Notes:**
- Used manual UserDefaults instead of @AppStorage for more control
- Time presets implemented: Blitz (3min+3x20s byo-yomi), Rapid (10min+3x30s byo-yomi), Fischer (5min+30s/move)
- All enums made Codable for future extensibility
- PreGameOverlay includes Quick Match, Challenge Player, and Settings sections
- Overlay shows when gamePhase == .preGame

---

### **Stage 2: Automatch/Quick Match** ⏳ NOT STARTED

**Goal:** Implement the simplest path to playing - automatch

#### 2.1 OGS Automatch API Integration
- [ ] Research OGS automatch WebSocket protocol documentation
- [ ] Add `startAutomatch(settings: GameSettings)` method to OGSClient
- [ ] Implement WebSocket message for automatch request
- [ ] Handle automatch response (game found)
- [ ] Add `cancelAutomatch()` method
- [ ] Handle automatch timeout/failure

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`

**Research needed:**
- OGS automatch API documentation
- WebSocket message format for automatch

#### 2.2 Automatch UI
- [ ] Add "Quick Match" section to PreGameOverlay
- [ ] Add "Start Game" button
- [ ] Show "Searching..." state with spinner
- [ ] Add "Cancel" button during search
- [ ] Display search parameters
- [ ] Handle timeout UI feedback

**Files to modify:**
- `SGFPlayer3D/Views/PreGameOverlay.swift`

#### 2.3 Game Start Transition
- [ ] Detect game start event from OGS (in WebSocket handler)
- [ ] Update `gamePhase` to `.playing`
- [ ] Fade out pre-game overlay
- [ ] Clear dimmed effect on board
- [ ] Load initial game state
- [ ] Set `myColor` based on game assignment
- [ ] Initialize time controls

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`
- `SGFPlayer3D/ContentView.swift`
- `SGFPlayer3D/ContentView3D.swift`

---

### **Stage 3: Challenge System** ⏳ NOT STARTED

**Goal:** Enable direct player-to-player challenges

#### 3.1 Send Challenge
- [ ] Add "Challenge Player" section to PreGameOverlay
- [ ] Add username text field
- [ ] Implement `sendChallenge(username: String, settings: GameSettings)` in OGSClient
- [ ] Build and send challenge WebSocket message
- [ ] Show "Challenge sent to [username]..." state
- [ ] Handle challenge accepted response
- [ ] Handle challenge declined response
- [ ] Handle timeout (30 seconds?)

**Files to modify:**
- `SGFPlayer3D/Views/PreGameOverlay.swift`
- `SGFPlayer3D/OGSClient.swift`

#### 3.2 Receive & Accept Challenges
- [ ] Listen for incoming challenge WebSocket events
- [ ] Create `ChallengeNotification` model
- [ ] Show toast notification for incoming challenge
- [ ] Add "Incoming Challenges" section to PreGameOverlay
- [ ] Display challenger name, rank, and settings
- [ ] Add Accept/Decline buttons
- [ ] Transition to game when accepted
- [ ] Handle auto-decline after timeout

**New files:**
- `SGFPlayer3D/Models/ChallengeNotification.swift`

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`
- `SGFPlayer3D/Views/PreGameOverlay.swift`

---

### **Stage 4: Board Interaction & Move Making** ⏳ NOT STARTED

**Goal:** Enable placing stones and sending moves to OGS

#### 4.1 Stone Placement Core Logic
- [ ] Add `attemptMove(x: Int, y: Int)` method to OGSClient
- [ ] Validate it's player's turn (`isMyTurn == true`)
- [ ] Validate game phase is `.playing`
- [ ] Send move WebSocket message to OGS
- [ ] Optimistically update local board
- [ ] Handle move confirmation from server
- [ ] Handle illegal move response

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`

#### 4.2 Move Validation & Feedback
- [ ] Handle illegal move errors from OGS
- [ ] Show error toast notification
- [ ] Revert optimistic board update
- [ ] Add visual feedback for successful move (brief highlight?)
- [ ] Update turn state after move

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`

#### 4.3 2D Board Click Handling
- [ ] Add tap gesture recognizer to 2D board view
- [ ] Convert screen coordinates to board coordinates
- [ ] Implement coordinate conversion math
- [ ] Add hover preview (semi-transparent stone on hover)
- [ ] Only allow clicks when `isMyTurn && gamePhase == .playing`
- [ ] Show click feedback (stone placement or error)

**Files to modify:**
- `SGFPlayer3D/ContentView.swift`

**Notes:**
- Need to handle board coordinate system (top-left vs bottom-left origin)
- Account for board margins and spacing

#### 4.4 3D Board Click Handling
- [ ] Add tap gesture to SceneKit view
- [ ] Implement ray casting from camera to board
- [ ] Detect intersection hit on board plane
- [ ] Convert 3D position to board coordinates
- [ ] Add hover preview (semi-transparent 3D stone)
- [ ] Only allow clicks when `isMyTurn && gamePhase == .playing`
- [ ] Show click feedback

**Files to modify:**
- `SGFPlayer3D/ContentView3D.swift`
- `SGFPlayer3D/SceneManager3D.swift`

**Notes:**
- SceneKit ray casting: use `hitTest` with ray from camera
- Preview stone should use same material as regular stones but with alpha

---

### **Stage 5: Game Controls** ⏳ NOT STARTED

**Goal:** Add pass, resign, and turn indicators

#### 5.1 Bottom Control Bar - Context Switch
- [ ] Add logic to detect game phase and turn state
- [ ] Hide playback controls when `isMyTurn && gamePhase == .playing`
- [ ] Show game action controls instead
- [ ] Add smooth transition animation
- [ ] Restore playback controls after move (when waiting for opponent)

**Files to modify:**
- `SGFPlayer3D/Views/PlaybackControls.swift` (or create new GameControls.swift?)
- `SGFPlayer3D/ContentView.swift`
- `SGFPlayer3D/ContentView3D.swift`

#### 5.2 Pass Button
- [ ] Add Pass button to game action controls
- [ ] Implement `passMove()` in OGSClient
- [ ] Send pass WebSocket message
- [ ] Update local game state
- [ ] Show "Passed" feedback briefly
- [ ] Detect double-pass (both players pass → scoring)

**New files:**
- `SGFPlayer3D/Views/GameActionControls.swift` (maybe?)

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`

#### 5.3 Resign Button
- [ ] Add Resign button to game action controls
- [ ] Show confirmation dialog ("Are you sure?")
- [ ] Implement `resignGame()` in OGSClient
- [ ] Send resign WebSocket message
- [ ] Show game result
- [ ] Return to pre-game state
- [ ] Clean up game state

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`
- `SGFPlayer3D/Views/GameActionControls.swift`

#### 5.4 "Your Turn" Indicator
- [ ] Add visual highlight to GameInfoOverlay when `isMyTurn`
- [ ] Subtle glow or color change around current player
- [ ] Pulsing animation (optional)
- [ ] Sound notification when turn changes to you (optional)
- [ ] Clear indicator when not your turn

**Files to modify:**
- `SGFPlayer3D/Views/GameInfoOverlay.swift`

---

### **Stage 6: Scoring & Game End** ⏳ NOT STARTED

**Goal:** Handle game completion and scoring phase

#### 6.1 Scoring Phase Detection
- [ ] Detect when both players pass consecutively
- [ ] Switch `gamePhase` to `.scoring`
- [ ] Receive scoring data from OGS
- [ ] Update UI to show scoring mode
- [ ] Display territory estimate

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`

#### 6.2 Simple Scoring UI
- [ ] Show scoring controls in bottom control area
- [ ] Add "Accept Score" button
- [ ] Add "Reject Score" button (returns to play)
- [ ] Display territory count for each player
- [ ] Show score difference
- [ ] Highlight disputed areas (if OGS provides this)

**Files to modify:**
- `SGFPlayer3D/Views/GameActionControls.swift`
- `SGFPlayer3D/OGSClient.swift`

**Notes:**
- For live games, auto-scoring is usually pretty good
- Marking dead stones may not be necessary if both players agree

#### 6.3 Game End
- [ ] Detect game end event from OGS
- [ ] Update `gamePhase` to `.finished`
- [ ] Show final result overlay
- [ ] Display winner, score, and reason
- [ ] Add "Play Again" button (returns to pre-game)
- [ ] Add "Review Game" button (load game as SGF for viewing)
- [ ] Clean up game state
- [ ] Disconnect from game

**New files:**
- `SGFPlayer3D/Views/GameResultOverlay.swift`

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`
- `SGFPlayer3D/ContentView.swift`
- `SGFPlayer3D/ContentView3D.swift`

---

### **Stage 7: Polish & UX** ⏳ NOT STARTED

**Goal:** Add nice-to-have features for better experience

#### 7.1 Notifications
- [ ] Show toast when opponent moves
- [ ] Play sound on opponent move
- [ ] "Your turn" notification
- [ ] Challenge received notification
- [ ] Game started notification

**New files:**
- `SGFPlayer3D/Views/ToastNotification.swift`

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`

#### 7.2 Time Pressure Indicators
- [ ] Highlight time display when < 30 seconds
- [ ] Change color to yellow/orange
- [ ] Flash time display when < 10 seconds
- [ ] Change color to red
- [ ] Audio tick in last 10 seconds (optional)
- [ ] Stronger visual pulse

**Files to modify:**
- `SGFPlayer3D/Views/GameInfoOverlay.swift`

#### 7.3 Connection Status
- [ ] Add connection status indicator to UI
- [ ] Show "Connected", "Connecting", "Disconnected"
- [ ] Handle disconnection gracefully
- [ ] Implement auto-reconnect
- [ ] Show reconnection attempts
- [ ] Handle game state sync after reconnect

**Files to modify:**
- `SGFPlayer3D/OGSClient.swift`
- `SGFPlayer3D/Views/GameInfoOverlay.swift` or new status indicator

#### 7.4 Game History (Maybe)
- [ ] Store recently finished games
- [ ] List of recent games in PreGameOverlay
- [ ] Click to review game
- [ ] Load game as SGF for viewing

**Notes:**
- This might be out of scope - can just use OGS website for history

---

## Sprint Planning

### **Sprint 1: Foundation** (Estimated: 1-2 sessions)
- Stage 1: Complete foundation
- **Milestone:** Pre-game overlay visible, game state structure in place

### **Sprint 2: First Playable Game** (Estimated: 2-3 sessions)
- Stage 2: Automatch
- Stage 4.1-4.3: 2D stone placement
- Stage 5.1-5.3: Pass and Resign
- **Milestone:** 🎯 Can play a complete automatch game in 2D!

### **Sprint 3: Full Features** (Estimated: 2-3 sessions)
- Stage 3: Challenge system
- Stage 4.4: 3D stone placement
- Stage 6: Scoring and game end
- **Milestone:** 🎯 Full live play experience in 2D and 3D!

### **Sprint 4: Polish** (Estimated: 1-2 sessions)
- Stage 7: All polish features
- **Milestone:** 🎯 Production-ready!

---

## Technical Notes & Decisions

### OGS WebSocket Protocol
- **Base URL:** `wss://online-go.com/socket.io/`
- **Authentication:** Uses existing session/token
- **Key Messages:**
  - `game/connect`: Join a game
  - `game/move`: Send a move
  - `game/chat`: Send chat message
  - Need to research: automatch, challenge

### Game State Architecture
- `OGSClient` owns game state
- `GamePhase` drives UI visibility
- `isMyTurn` controls interaction
- Board clicks filtered through game phase check

### UI Layout Strategy
- Pre-game: Overlay on dimmed board
- Playing: Controls context-switch based on turn
- Scoring: Different control set
- Finished: Result overlay, return to pre-game

---

## Session Log

### Session 1 - 2025-10-17
**Completed:**
- Initial planning and scope definition
- Created complete stage breakdown
- Defined sprint milestones
- Created this planning document

**Next Session:**
- Start Stage 1.1: Game State Management
- Add GamePhase enum to OGSClient

**Notes:**
- User wants live games only (no correspondence)
- Using dimmed board for pre-game UI
- One game at a time to keep UI simple

### Session 2 - 2025-10-18
**Completed:**
- ✅ Stage 1.1: Game State Management
  - Added GamePhase enum with 4 states (.preGame, .playing, .scoring, .finished)
  - Added @Published gamePhase property to OGSClient (defaults to .preGame)
  - Confirmed isMyTurn and playerColor (myColor) already exist
- ✅ Stage 1.2: Pre-Game Overlay Component
  - Created PreGameOverlay.swift view (300+ lines)
  - Designed overlay with semi-transparent dimmed background
  - Integrated into both ContentView.swift (2D) and ContentView3D.swift (3D)
  - Conditional rendering based on gamePhase == .preGame
- ✅ Stage 1.3: Game Parameter State
  - Created Models/GameSettings.swift (160 lines)
  - Implemented RankRange enum (±1, ±2, ±3, Any) with Codable
  - Implemented TimeControlPreset enum (Blitz, Rapid, Fischer) with Codable
  - Implemented ColorPreference enum (Auto, Black, White) with Codable
  - Added UserDefaults persistence (load/save methods)
  - Built full UI in PreGameOverlay with all settings controls
- Build successful, all files compile

**Next Session:**
- Start Stage 2: Automatch/Quick Match
- Research OGS automatch WebSocket protocol
- Implement startAutomatch() in OGSClient

**Notes:**
- All enums made Codable for future API integration
- PreGameOverlay has 3 sections: Quick Match, Challenge Player, Game Settings
- Time presets fully defined with mainTime, periodTime, periods, and timeSystem
- Placeholder methods (TODO) added for automatch and challenge actions

### Session 3 - 2025-10-22
**Completed:**
- ✅ WebSocket Clock Subscription Fix (v3.36)
  - **Problem:** Clock events weren't arriving via WebSocket
  - **Root Cause:** Missing player_id parameter in game/connect subscription
  - **Research:** Analyzed flovo/ogs_api Python implementation on GitHub
  - **Solution:**
    - Added `@Published var playerID: Int?` to OGSClient (line 27)
    - Parse player ID from REST API login response (lines 307-317)
    - Include player_id in game/connect WebSocket message (lines 520-561)
    - Fallback to spectator mode if no player_id available
  - **Expected Result:** Real-time clock updates via WebSocket, eliminating REST polling

- ✅ Spurious Click Sound Fix (v3.37)
  - **Problem:** Stone click sounds playing every ~1 second during OGS game observation
  - **Root Cause:** OGSGameLoaded notification fires on every poll, causing unnecessary player.seek() calls
  - **Investigation:** Logs showed notification firing every second even when move count unchanged
  - **Solution:**
    - Track lastLoadedOGSMoveCount in ContentView and ContentView3D
    - Only call player.seek() when moveCount actually changes
    - Added debug logging for polling vs. new move detection
  - **Testing:** User confirmed spurious clicks eliminated, sounds only play on actual new moves
  - **Files Modified:**
    - SGFPlayer3D/ContentView3D.swift (lines 51-53, 286-296)
    - SGFPlayer3D/ContentView.swift (lines 58-59, 350-361)

- ✅ Created SESSION_STATE.md crash recovery document
  - Comprehensive state snapshot for easy recovery after crashes
  - Documents current work, testing status, recovery instructions
  - Links to all key documents and recent commits

**Next Session:**
- Test WebSocket clock events are arriving properly
- Verify player_id appears in subscription logs
- Start Stage 2: Automatch/Quick Match
- Research OGS automatch WebSocket protocol
- Implement startAutomatch() in OGSClient

---

## Open Questions & Research Needed

1. **OGS Automatch Protocol**
   - What is the exact WebSocket message format?
   - How are game settings specified?
   - How does OGS respond when match is found?

2. **OGS Challenge Protocol**
   - WebSocket message format for sending challenges
   - How to receive incoming challenges
   - Challenge timeout handling

3. **Move Validation**
   - Does OGS validate moves server-side?
   - What error responses should we expect?
   - Should we do client-side validation too?

4. **Time Control Format**
   - How does OGS represent different time controls?
   - Fischer time increment format?
   - Byo-yomi period format?

5. **Scoring Phase**
   - What data does OGS send during scoring?
   - How are dead stones marked?
   - Auto-score format?

---

## Change Log

### 2025-10-17
- Initial document creation
- Defined 7 implementation stages
- Planned 4 sprints
- Estimated session counts

### 2025-10-18
- Completed Stage 1 (Foundation & UI Structure)
- Created 2 new files: GameSettings.swift, PreGameOverlay.swift
- Modified 3 existing files: OGSClient.swift, ContentView.swift, ContentView3D.swift
- Updated status: Stage 1 COMPLETE ✅
- Added detailed session log for Session 2

---

## Next Steps

**Immediate (Next Session):**
1. Start Stage 1.1: Add GamePhase enum to OGSClient
2. Add game state properties (isMyTurn, myColor)
3. Create basic GameSettings struct

**Short Term (Sprint 1):**
- Complete Stage 1 foundation
- Get pre-game overlay rendering

**Medium Term (Sprint 2):**
- Research OGS automatch API
- Implement basic stone placement in 2D
- Get first complete game working

**Long Term (Sprint 3-4):**
- Add challenge system
- Complete 3D support
- Polish and refinements
