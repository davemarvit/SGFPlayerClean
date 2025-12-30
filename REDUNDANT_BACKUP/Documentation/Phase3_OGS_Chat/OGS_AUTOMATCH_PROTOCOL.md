# OGS Automatch Protocol Documentation

**Research Date:** 2025-10-22
**Source:** Official OGS Goban Library Documentation (docs.online-go.com/goban)

---

## Overview

OGS uses Socket.IO for real-time automatch functionality. The WebSocket endpoint is `wss://online-go.com/socket.io/`.

## Message Format

**Client → Server:**
```
[command: string, data: any, id?: number]
```

**Server → Client:**
```
[event_name: string, data: any]
or
[id: number, data?: any, error?: {code, message}]
```

---

## Client-to-Server Commands

### 1. `automatch/find_match`
**Purpose:** Request a match via the automatch system

**Parameters:** `AutomatchPreferences` object

**Example:**
```typescript
socket.emit("automatch/find_match", {
    uuid: "unique-uuid-string",
    size_speed_options: [
        {
            size: "19x19",
            speed: "live",
            system: "byoyomi"
        }
    ],
    lower_rank_diff: -3,  // Accept 3 ranks lower
    upper_rank_diff: 3,   // Accept 3 ranks higher
    rules: {
        condition: "required",
        value: "japanese"
    },
    handicap: {
        condition: "preferred",
        value: "disabled"
    }
})
```

### 2. `automatch/cancel`
**Purpose:** Cancel an active automatch request

**Parameters:**
```typescript
{
    uuid: string  // The match request identifier to cancel
}
```

### 3. `automatch/list`
**Purpose:** Get active automatch entries for the current user

**Parameters:** `{}` (empty object)

### 4. `automatch/available/subscribe`
**Purpose:** Subscribe to receive notifications about available automatch offers

**Parameters:** None

### 5. `automatch/available/unsubscribe`
**Purpose:** Unsubscribe from automatch offer notifications

**Parameters:** None

---

## Server-to-Client Events

### 1. `automatch/entry`
**Meaning:** An automatch request is active

**Data:** `AutomatchPreferences` object

**When Received:** After successfully calling `automatch/find_match`

### 2. `automatch/cancel`
**Meaning:** An automatch request was canceled

**Data:** `{ uuid: string }`

**When Received:** After calling `automatch/cancel` or if the server cancels it

### 3. `automatch/start`
**Meaning:** An automatch request resulted in a game!

**Data:**
```typescript
{
    game_id: number,
    uuid: string  // The original automatch request uuid
}
```

**When Received:** When OGS finds a match for your request

**Action Required:** Load the game using the `game_id`

### 4. `automatch/available/add`
**Meaning:** An automatch offer was added (another player is seeking)

**Data:**
```typescript
{
    player: { /* player info */ },
    preferences: AutomatchPreferences,
    uuid: string,
    timestamp: number
}
```

### 5. `automatch/available/remove`
**Meaning:** An automatch offer was removed

**Data:** `{ uuid: string }`

### 6. `active_game`
**Meaning:** Notification of an active game or game state change

**Data:** `GameListEntry` object

**When Received:** After a game starts (following `automatch/start`)

---

## AutomatchPreferences Structure

```typescript
interface AutomatchPreferences {
    uuid: string;  // Unique identifier for this request

    size_speed_options: Array<{
        size: "9x9" | "13x13" | "19x19";
        speed: "blitz" | "rapid" | "live" | "correspondence";
        system: "fischer" | "byoyomi";
    }>;

    lower_rank_diff: number;  // e.g., -3 for 3 ranks lower
    upper_rank_diff: number;  // e.g., +3 for 3 ranks higher

    rules: {
        condition: "required" | "preferred" | "no-preference";
        value: "chinese" | "aga" | "japanese" | "korean" | "ing" | "nz";
    };

    handicap: {
        condition: "required" | "preferred" | "no-preference";
        value: "enabled" | "disabled";
    };

    timestamp?: number;  // Optional
}
```

---

## Type Definitions

### Size
```typescript
type Size = "9x9" | "13x13" | "19x19"
```

### Speed
```typescript
type Speed = "blitz" | "rapid" | "live" | "correspondence"
```

### Time System
```typescript
type TimeSystem = "fischer" | "byoyomi"
```

### Rules
```typescript
type Rules = "chinese" | "aga" | "japanese" | "korean" | "ing" | "nz"
```

### Automatch Condition
```typescript
type AutomatchCondition = "required" | "preferred" | "no-preference"
```

---

## Typical Automatch Flow

1. **User clicks "Quick Match"**
   - Client generates a UUID
   - Client creates `AutomatchPreferences` from user settings
   - Client sends `automatch/find_match` command

2. **Server acknowledges**
   - Server sends `automatch/entry` event back
   - This confirms the request is active

3. **Waiting for match...**
   - Client can show "Searching..." UI
   - User can click "Cancel" to send `automatch/cancel`

4. **Match found!**
   - Server sends `automatch/start` with `game_id`
   - Server also sends `active_game` notification

5. **Start playing**
   - Client loads the game using `game_id`
   - Client subscribes to game events via `game/connect`
   - Transition to playing state

---

## Actual Working Code from OGS (online-go.com)

### From `automatch_manager.tsx`

**Start Automatch:**
```typescript
public findMatch(preferences: AutomatchPreferences) {
    socket.send("automatch/find_match", preferences);
    console.log("findMatch", preferences);

    // For live games, show a toast notification
    if (preferences.size_speed_options.filter(
            (opt) => opt.speed === "blitz" || opt.speed === "rapid" || opt.speed === "live"
        ).length) {
        this.last_find_match_uuid = preferences.uuid;
        // ... toast notification code ...
    }
}
```

**Cancel Automatch:**
```typescript
public cancel(uuid: string) {
    this.remove(uuid);
    socket.send("automatch/cancel", { uuid });
}
```

**Event Listeners (in constructor):**
```typescript
socket.on("automatch/start", this.onAutomatchStart);
socket.on("automatch/entry", this.onAutomatchEntry);
socket.on("automatch/cancel", this.onAutomatchCancel);
```

**Key Insight:**
OGS uses `socket.send(command, data)` which is likely a wrapper around Socket.IO's `socket.emit(command, data)`. Since we're already using Socket.IO in OGSClient, we can use the same pattern.

---

## Implementation Notes

### UUID Generation
Each automatch request needs a unique UUID. Use:
```swift
UUID().uuidString
```

### Multiple Size/Speed Options
The `size_speed_options` array can contain multiple entries. This allows searching for multiple game types simultaneously. Example:
```typescript
size_speed_options: [
    { size: "19x19", speed: "live", system: "byoyomi" },
    { size: "13x13", speed: "live", system: "byoyomi" }
]
```

### Rank Differences
- `lower_rank_diff`: Negative number (e.g., -3 means 3 ranks weaker)
- `upper_rank_diff`: Positive number (e.g., +3 means 3 ranks stronger)
- Setting both to 0 means exact rank only

### Handicap Settings
- `"enabled"`: Accept handicap games
- `"disabled"`: No handicap
- `condition` can be "required", "preferred", or "no-preference"

### Rules Settings
- OGS primarily uses "japanese" rules
- Can set to "required" to ensure specific ruleset
- "preferred" allows flexibility

---

## Error Handling

### Timeout
If no match is found after a reasonable time (e.g., 60 seconds), consider:
- Showing a "Still searching..." message
- Offering to cancel
- Suggesting broader search parameters

### Disconnection
If WebSocket disconnects during automatch:
- The server will automatically cancel the request
- Re-subscribe on reconnection if desired

### Already in a Game
- OGS may reject automatch if the user already has an active game
- Check for errors in the server response

---

## Testing Checklist

- [ ] Can initiate automatch with valid preferences
- [ ] Receive `automatch/entry` confirmation
- [ ] Can cancel automatch request
- [ ] Receive `automatch/cancel` confirmation
- [ ] Handle `automatch/start` and extract game_id
- [ ] Transition to game on match found
- [ ] Handle no match found (timeout)
- [ ] Handle multiple simultaneous requests (should not happen)
- [ ] Test with different board sizes
- [ ] Test with different time controls
- [ ] Test with different rank ranges

---

## References

- **Official Documentation:** https://docs.online-go.com/goban/
- **Protocol Interfaces:** https://docs.online-go.com/goban/modules/protocol.html
- **AutomatchPreferences:** https://docs.online-go.com/goban/interfaces/protocol.AutomatchPreferences.html
- **ClientToServer:** https://docs.online-go.com/goban/interfaces/protocol.ClientToServer.html
- **ServerToClient:** https://docs.online-go.com/goban/interfaces/protocol.ServerToClient.html

---

**END OF DOCUMENTATION**
