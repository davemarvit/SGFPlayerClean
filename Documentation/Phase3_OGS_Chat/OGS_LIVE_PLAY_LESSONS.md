# OGS Live Play Implementation - Lessons Learned

**Date:** 2025-10-24
**Status:** In Progress - Debugging Automatch

---

## What We Implemented

### 1. Automatch Feature
- **File:** `OGSClient.swift`
- **Methods:** `startAutomatch()`, `cancelAutomatch()`
- **Protocol:** WebSocket-based, documented in `OGS_AUTOMATCH_PROTOCOL.md`
- **UI:** PreGameOverlay with Quick Match section
- **Status:** ✅ Code implemented, ⚠️ OGS not responding

### 2. Direct Challenge Feature
- **File:** `OGSClient.swift`
- **Methods:** `sendChallenge()`, `lookupPlayerID()`, `sendChallengeToPlayerID()`
- **Endpoint:** REST API `POST /api/v1/challenges`
- **UI:** PreGameOverlay with Challenge Player section
- **Status:** ✅ Code implemented, ❌ OGS returns HTTP 500 errors

### 3. Game Settings
- **File:** `GameSettings.swift`
- Board size (9×9, 13×13, 19×19)
- Rank range (Any, Similar, Close)
- Time control (Blitz, Rapid, Correspondence)
- Color preference (Automatic, Black, White)
- **Status:** ✅ Fully functional

---

## Critical Issues Discovered

### Issue 1: OGS Challenge REST API Returns 500 Errors

**Problem:**
```
POST /api/v1/challenges
Response: HTTP 500 (Server Error)
```

**What We Tried:**
1. ✅ Fixed CSRF protection (Referer, Origin, X-CSRFToken headers)
2. ✅ Fixed cookie-based authentication (session cookies)
3. ✅ Corrected JSON structure per forum posts (duplicate `time_control` field)
4. ❌ Still getting HTTP 500 errors

**Evidence:**
- Zero search results for `api/v1/challenges` in OGS GitHub repository
- Forum posts from 2017 show same issues
- Suggests REST challenge API may be broken/deprecated

**Debug Log Example:**
```
Request headers: {"Origin": "https://online-go.com", "Referer": "https://online-go.com", "X-CSRFToken": "...", "Content-Type": "application/json"}
Request body: {"challenged_player_id":1872928,"game":{...},"challenger_color":"automatic"}
Response: HTTP 500 - Server Error
```

### Issue 2: Automatch Not Receiving Responses from OGS

**Problem:**
- Automatch requests sent successfully via WebSocket
- Zero responses from OGS (no `automatch/entry`, `automatch/start`, or `automatch/cancel`)
- Only receiving broadcast `active-bots` events

**What We Fixed:**
1. ✅ WebSocket cookie sharing - configured URLSession to use `HTTPCookieStorage.shared`
2. ✅ REST API authentication working (cookies set correctly)
3. ✅ Provisional account status (NewClient now has 6+ ranked games)
4. ✅ Settings match between accounts (19×19, Any rank, Rapid, Any color)

**Current Symptoms:**
- UI shows "Connected" and username
- Automatch requests sent with proper format
- WebSocket appears open (can send messages)
- But receive loop getting zero events from OGS

**Debug Log Example:**
```
SENDING AUTOMATCH: 42["automatch/find_match",{"uuid":"...","size_speed_options":[{"size":"19x19","speed":"rapid","system":"byoyomi"}],...}]
RECEIVED EVENT: active-bots
(no automatch/entry response)
```

### Issue 3: WebSocket Authentication Unclear

**Problem:**
- REST API login uses `URLSession.shared` → cookies stored in `HTTPCookieStorage.shared`
- WebSocket initially used separate `URLSession` → cookies not visible
- Fixed by explicitly configuring WebSocket session to use shared cookie storage
- But still not clear if WebSocket is properly authenticated

**What We Learned:**
- OGS documentation says "WebSocket inherits session cookies from REST login"
- In practice, this requires explicit configuration
- No clear WebSocket authentication event to confirm success

---

## Authentication Flow (Current Implementation)

### REST API Login
1. Get CSRF token via dummy POST to `/api/v0/login`
2. Login with username/password + CSRF token
3. Session cookies stored in `HTTPCookieStorage.shared`
4. User marked as `isAuthenticated = true`

### WebSocket Connection
1. Connect to `wss://online-go.com/socket.io/?EIO=3&transport=websocket`
2. Receive handshake (message "0")
3. Receive namespace connection (message "40")
4. Mark as `isConnected = true`
5. WebSocket should inherit session cookies for authentication

### Problem
- No explicit WebSocket auth confirmation event
- OGS silently ignores requests if not authenticated
- Hard to debug whether authentication succeeded

---

## Code Locations

### OGSClient.swift
- Lines 166-201: `connect()` - WebSocket connection with cookie sharing fix
- Lines 202-357: `authenticate()` - REST API login
- Lines 369-505: Automatch methods (`startAutomatch`, `cancelAutomatch`)
- Lines 517-748: Challenge methods (`sendChallenge`, `lookupPlayerID`, `sendChallengeToPlayerID`)
- Lines 1004-1032: `receiveMessage()` - WebSocket receive loop

### PreGameOverlay.swift
- Lines 75-111: Quick Match section UI
- Lines 115-144: Challenge Player section UI
- Lines 148-253: Game Settings section UI
- Lines 258-296: Action handlers

### GameSettings.swift
- Complete game configuration data structures
- Persistence via UserDefaults
- API value converters

---

## Testing Performed

### Automatch Tests
1. ✅ Two accounts (DaveM - established, NewClient - now non-provisional)
2. ✅ Both logged in via REST API
3. ✅ Both showing "Connected" status
4. ✅ Identical settings (19×19, Any, Rapid, Any)
5. ❌ No match found after multiple attempts
6. ❌ No `automatch/entry` confirmations from OGS

### Challenge Tests
1. ✅ Username lookup working (finds player ID)
2. ✅ CSRF protection headers correct
3. ✅ Session cookies being sent
4. ❌ OGS returns HTTP 500 for all challenge requests

---

## Possible Root Causes

### Why Automatch Might Not Work
1. **WebSocket not actually authenticated** - cookies not being sent with WebSocket upgrade request
2. **Receive loop broken** - error killing the loop before events arrive
3. **OGS restrictions** - additional requirements we don't know about
4. **Protocol mismatch** - our message format doesn't match what OGS expects
5. **Server-side issues** - OGS automatch system may have problems

### Why Challenges Might Not Work
1. **API deprecated** - `/api/v1/challenges` may no longer be supported
2. **Missing required fields** - undocumented parameters needed
3. **Server bugs** - OGS challenge API has known issues (per forums)
4. **Account restrictions** - some limitation on who can send challenges

---

## Next Steps to Try

### For Automatch
1. Verify WebSocket is actually receiving ANY messages (not just seeing sends)
2. Check if receive loop is running continuously or dying on first error
3. Add more diagnostic logging to track message flow
4. Try simpler test: just connect and see if we receive any events at all
5. Compare with working OGS browser session (capture network traffic)

### For Challenges
1. Contact OGS developers on forum to ask if REST challenge API works
2. Check if there's a WebSocket-based challenge command instead
3. Look for alternative ways to start games programmatically

### For Both
1. Test with OGS's own official tools/bots to see if they work
2. Check OGS status page for known issues
3. Review OGS changelog for recent API changes

---

## Working Features

✅ **REST API Authentication** - Login works, cookies stored
✅ **WebSocket Connection** - Can connect and send messages
✅ **Game Settings UI** - All controls functional
✅ **Username Lookup** - Player ID resolution works
✅ **PreGameOverlay** - UI complete and polished
✅ **Cookie Sharing** - WebSocket configured to use shared cookies

---

## Known OGS Limitations

1. **Provisional accounts can't use automatch** - need 5-6 ranked games first
2. **Live game limits** - users under 500 games can only play 1 simultaneous Live/Blitz game
3. **Rank restrictions** - ranked challenges can't exceed 9 kyu/dan difference
4. **Documentation gaps** - many API features poorly documented or undocumented

---

## References

- `OGS_AUTOMATCH_PROTOCOL.md` - Complete automatch protocol documentation
- `OGS_INTEGRATION.md` - General WebSocket integration guide
- Forum: https://forums.online-go.com/t/issuing-challenges-through-the-api/5715
- Docs: https://docs.online-go.com/goban/
- Docs: https://ogs.readme.io/docs/finding-games-and-challenging-users

---

**END OF DOCUMENT**
