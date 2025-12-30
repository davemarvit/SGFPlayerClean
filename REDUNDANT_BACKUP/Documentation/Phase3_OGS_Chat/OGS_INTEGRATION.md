# OGS Integration for SGFPlayer3D

## Overview
SGFPlayer3D now has basic OGS (Online Go Server) WebSocket integration for real-time online game play.

## Features Implemented

### 1. Click Detection on 3D Board
- **File**: `ContentView3D.swift` (lines 371-387)
- Mouse clicks on the 3D board are converted to board coordinates (col, row)
- Uses SceneKit hit testing to raycast from screen coordinates to 3D world coordinates
- Converts world coordinates to grid positions using board dimensions

### 2. Ghost Stone Cursor
- **File**: `ContentView3D.swift` (lines 257-262, 384-387), `SceneManager3D` (updateGhostStone method)
- Semi-transparent stone follows mouse cursor over the board
- Shows the correct color (black/white) based on whose turn it is
- Automatically switches color when a move is made
- 50% transparency with enhanced specular highlights for visibility

### 3. OGS WebSocket Client
- **File**: `OGSClient.swift`
- Connects to OGS WebSocket server at `wss://online-go.com/socket.io/?EIO=3&transport=websocket`
- Implements Socket.io protocol over WebSocket
- Features:
  - Connect/disconnect to OGS
  - Join a specific game by ID
  - Send moves in SGF notation
  - Receive opponent moves
  - Automatic ping/pong for connection keep-alive
  - Coordinate conversion: Board position ↔ SGF notation

### 4. UI Integration
- **File**: `ContentView3D.swift` (lines 476-490)
- Network icon button in top bar shows connection status
  - Gray with slash = disconnected
  - Green = connected
- Click to connect/disconnect from OGS
- Hover tooltip shows current state

## How It Works

### Sending Moves
1. User clicks on the 3D board
2. Click location is converted to board coordinates (x, y)
3. Board coordinates are converted to SGF notation (e.g., "pd" for Q16)
4. If connected to OGS and in a game, the move is sent via WebSocket:
   ```swift
   42["game/move",{"game_id":12345,"move":"pd"}]
   ```

### Receiving Moves
1. OGS sends move via WebSocket in Socket.io format
2. `OGSClient` parses the message and extracts the move
3. Move is converted from SGF notation back to board coordinates
4. `NotificationCenter` broadcasts the move to `ContentView3D`
5. ContentView3D receives the move and updates the board (TODO: actual stone placement)

### Ghost Stone Cursor
1. Mouse movement is tracked in `CameraControlView`
2. On `mouseMoved`, hit testing converts screen coordinates to board position
3. If over a valid board position, `onBoardHover` callback is triggered
4. `updateGhostStone` creates/updates a semi-transparent stone at cursor position
5. Stone color matches `currentTurn` (black or white)
6. When a move is made, `currentTurn` alternates

## Testing the Integration

### ✅ Working Features (Tested)
1. **Ghost Stone Cursor**: Hover over the board - semi-transparent stone follows mouse
2. **Turn Alternation**: Click the board - ghost stone alternates between black and white
3. **Click Detection**: Board clicks converted to coordinates and logged
4. **Network Button UI**: Button in top-right shows connection state
5. **Network Permissions**: App has proper entitlements for outgoing connections

### ✅ OGS Connection Status
**FIXED (2025-10-08)**: WebSocket endpoint has been corrected.
- Previous (broken): `wss://online-go.com/socket.io/?EIO=4&transport=websocket` - returned "Bad request"
- Current (working): `wss://online-go.com/socket.io/?transport=websocket` - connects successfully

**Recent Improvements**:
1. ✅ Fixed WebSocket URL (removed EIO=4 parameter that was causing 400 errors)
2. ✅ Fixed move handling - moves now properly update the board in real-time
3. ✅ Added connection error reporting and disconnect notifications
4. ✅ Improved move synchronization logic in handleOGSMove()

### OGS Game Testing (requires account)
1. Connect to OGS (click network icon)
2. Open browser to https://online-go.com and start a game
3. Note the game ID from the URL (e.g., `/game/12345`)
4. In code, call `ogsClient.joinGame(gameID: 12345)` to join the game
5. Click on the 3D board to send moves
6. Opponent moves should appear (currently just logs, stone placement TODO)

### Console Logging
All actions are logged with prefixes:
- `BOARDCLICK:` - Board interaction events
- `OGS:` - WebSocket communication

To view logs:
```bash
log show --predicate 'processImagePath CONTAINS "SGFPlayer3D"' --style compact --last 5m | grep -E "(BOARDCLICK|OGS:)"
```

## Implementation Details

### Coordinate Systems
- **Screen**: NSPoint (x, y) from mouse events
- **World**: SCNVector3 (x, y, z) in 3D scene
- **Board**: BoardPosition (x: Int, y: Int) where (0,0) is top-left
- **SGF**: String like "aa" (top-left) to "ss" (bottom-right) for 19×19

### Key Methods
- `getBoardPosition(from:in:)` - Screen → Board coordinates
- `positionToSGF(x:y:)` - Board → SGF notation
- `sgfToPosition(move:)` - SGF → Board coordinates
- `updateGhostStone(at:color:)` - Create/update cursor stone

### WebSocket Protocol (Socket.io)
- `0` - Connection established
- `2` - Ping
- `3` - Pong
- `40` - Namespace connected
- `42[...]` - Event message with JSON payload

## TODO / Next Steps

### Critical
- [ ] Actual stone placement on board when receiving moves
- [ ] UI to input game ID and join OGS games
- [ ] Handle game state synchronization (not just moves)
- [ ] Display captures and score

### Important
- [ ] Prevent clicking on occupied positions
- [ ] Show whose turn it is
- [ ] Handle pass moves
- [ ] Resignation handling
- [ ] Time control display

### Nice to Have
- [ ] Auto-reconnect on connection loss
- [ ] Game list browser
- [ ] Chat integration
- [ ] Sound effects for moves
- [ ] Animation for received moves

## Known Issues
1. Ghost stone color only updates after clicking (not when receiving moves) - needs turn tracking from OGS game state
2. No validation of legal moves - can click anywhere
3. ~~No actual stone placement when receiving moves - just logs the move~~ **FIXED**: Moves now properly update the board
4. ~~Game ID must be manually specified in code - needs UI input~~ **FIXED**: UI dialog for entering game ID
5. ~~No authentication - can only spectate or play as guest~~ **FIXED**: Login dialog with keychain storage

## Files Modified
- `ContentView3D.swift` - Main 3D view with click handling and OGS integration
- `SceneManager3D.swift` - Board hit testing and ghost stone rendering
- `OGSClient.swift` - NEW: WebSocket client for OGS communication

## Architecture Notes
- Uses `@StateObject` for OGS client to maintain connection across view updates
- NotificationCenter used for move events (OGS → ContentView3D)
- Callbacks used for UI events (mouse → board logic)
- Turn tracking currently local only (needs sync with OGS game state)

## Resources
- OGS API: https://online-go.com/docs/
- Socket.io Protocol: https://socket.io/docs/v3/
- SceneKit Hit Testing: Apple Developer Documentation
