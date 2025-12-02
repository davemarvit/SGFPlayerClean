# Advanced OGS Client

A modern, feature-rich web client for Online Go Server (OGS) with beautiful board rendering and Google Meet integration.

## ✨ Features

### 🎨 Beautiful Board Rendering
- **Adapted from SGFPlayer**: Uses the same gorgeous board rendering system from your SGFPlayer app
- **Realistic stone physics**: Stone jitter and positioning effects for authentic feel
- **Wood-grain board**: Authentic kaya wood appearance with shadows and depth
- **Capture bowls**: Animated stone capture system with physics-based positioning
- **Responsive design**: Works perfectly on desktop, tablet, and mobile

### 📹 Google Meet Integration
- **One-click video calls**: Start Google Meet sessions directly from games
- **Automatic invitations**: Send meet links to opponents via game chat
- **Smart notifications**: Detect and respond to meet invitations from opponents
- **Seamless experience**: Join calls without leaving the game

### 🔗 Full OGS Integration
- **WebSocket real-time**: Live game updates, chat, and notifications
- **OAuth2 authentication**: Secure login with OGS credentials
- **Complete game support**: Play, observe, and analyze games
- **Lobby system**: Browse open games, create challenges, auto-match
- **Chat integration**: Global and game-specific chat with meet invite detection

### 🎮 Enhanced Gaming Experience
- **Modern UI**: Clean, intuitive interface with smooth animations
- **Keyboard shortcuts**: Quick navigation and game controls
- **Multiple board sizes**: Support for 9×9, 13×13, and 19×19 boards
- **Time controls**: Blitz, live, and correspondence games
- **Game analysis**: Move history, captures, and territory calculation

## 🏗️ Architecture

### Core Components

```
Advanced OGS Client
├── 🎯 Core Game Engine (SGFPlayerEngine)
│   ├── Board state management
│   ├── Move validation and capture logic
│   ├── SGF parsing and game loading
│   └── Real-time move synchronization
├── 🎨 Board Renderer (BoardRenderer)
│   ├── Canvas-based Go board drawing
│   ├── Stone physics and jitter effects
│   ├── Capture animations
│   └── Responsive layout system
├── 🌐 OGS API Client (OGSClient)
│   ├── WebSocket real-time communication
│   ├── REST API for challenges and user data
│   ├── OAuth2 authentication flow
│   └── Game and lobby management
├── 📹 Google Meet Integration (GoogleMeetIntegration)
│   ├── Meeting space creation
│   ├── Invitation system via chat
│   ├── Link parsing and auto-join
│   └── Notification handling
└── 🎛️ UI Controllers
    ├── App Controller (main coordinator)
    ├── Lobby Controller (games and chat)
    └── Game Controller (active gameplay)
```

### Technology Stack

- **Frontend**: Vanilla JavaScript ES6+ with modern web APIs
- **Styling**: CSS3 with custom properties and responsive design
- **Rendering**: HTML5 Canvas for board graphics
- **Communication**: WebSocket for real-time, Fetch API for REST
- **Authentication**: OAuth2 with OGS integration
- **Video**: Google Meet REST API integration

## 🚀 Quick Start

### Prerequisites

1. **Web Server**: Any HTTP server (Python SimpleHTTPServer, Node.js serve, etc.)
2. **OGS Account**: Valid Online Go Server account
3. **Modern Browser**: Chrome, Firefox, Safari, or Edge (recent versions)

### Setup

1. **Clone or Download**:
   ```bash
   cd "/Users/Dave/Go/SGFPlayer Code/OGS-Client"
   ```

2. **Start Local Server**:
   ```bash
   # Python 3
   python -m http.server 8080

   # Python 2
   python -m SimpleHTTPServer 8080

   # Node.js (if you have 'serve' installed)
   npx serve .
   ```

3. **Open in Browser**:
   ```
   http://localhost:8080
   ```

4. **Login**:
   - Use your OGS username and password
   - OAuth2 login is available but requires additional setup

## 🛠️ Configuration

### Google Meet Setup (Optional)

For full Google Meet integration, you'll need:

1. **Google Cloud Project** with Meet API enabled
2. **API Key** and **OAuth2 credentials**
3. Update configuration in `js/main.js`:

```javascript
// Replace in initializeGoogleMeet()
await this.meetIntegration.initialize({
    apiKey: 'your-google-api-key',
    accessToken: null // Will be set during auth
});
```

### OGS API Credentials

For production use, register your client with OGS:

1. Visit [OGS OAuth Applications](https://online-go.com/oauth2/applications/)
2. Create new application
3. Update credentials in `js/api/ogs-client.js`:

```javascript
client_id: 'your-client-id',
client_secret: 'your-client-secret'
```

## 🎮 Usage

### Playing Games

1. **Browse Lobby**: View open games and challenges
2. **Quick Match**: Use auto-match for instant games
3. **Create Custom**: Set up games with specific rules
4. **Join Games**: Click any open game to join

### Video Calls

1. **Start Meet**: Click "📹 Start Google Meet" during a game
2. **Send Invite**: Automatically sends invitation to opponent
3. **Join Call**: Click join when receiving an invitation
4. **Auto-detection**: App detects meet links in chat

### Game Controls

- **Click to Play**: Click intersections to place stones
- **Pass**: Use pass button when you can't move
- **Resign**: Resign from the current game
- **Chat**: Communicate with opponent and global chat

## 🔧 Development

### File Structure

```
OGS-Client/
├── index.html              # Main application HTML
├── styles/                  # CSS stylesheets
│   ├── main.css            # Core application styles
│   ├── auth.css            # Authentication screen
│   ├── board.css           # Go board rendering
│   └── lobby.css           # Lobby and game views
├── js/                     # JavaScript modules
│   ├── utils/
│   │   └── logger.js       # Logging utility
│   ├── core/
│   │   ├── sgf-parser.js   # SGF file parsing (from SGFPlayer)
│   │   ├── game-engine.js  # Game logic (adapted from SGFPlayerEngine)
│   │   └── board-renderer.js # Canvas board rendering
│   ├── api/
│   │   ├── ogs-client.js   # OGS WebSocket/REST API
│   │   └── google-meet.js  # Google Meet integration
│   ├── ui/
│   │   ├── app-controller.js    # Main app coordinator
│   │   ├── lobby-controller.js  # Lobby management
│   │   └── game-controller.js   # Game view management
│   └── main.js             # Application entry point
└── README.md               # This file
```

### Code Adaptation from SGFPlayer

The web client carefully adapts key components from your SGFPlayer:

#### SGF Parsing (`sgf-parser.js`)
- **Direct port** of `SGFKit.swift` parsing logic
- Maintains same AST structure and move handling
- Supports variations, comments, and all SGF properties

#### Game Engine (`game-engine.js`)
- **Adapted from** `SGFPlayerEngine.swift`
- Preserves board state management and capture logic
- Adds live game support for OGS integration
- Event-driven architecture for UI updates

#### Board Rendering (`board-renderer.js`)
- **Inspired by** `SimpleBoardView.swift` rendering
- Canvas-based implementation of your board graphics
- Maintains stone jitter, physics, and bowl systems
- Responsive design for web environments

### Adding Features

#### New Game Features
1. Add handler in `GameController`
2. Update UI in `game-controller.js`
3. Implement OGS protocol in `ogs-client.js`

#### Board Enhancements
1. Modify rendering in `BoardRenderer` class
2. Update CSS in `board.css`
3. Add physics in stone positioning logic

#### Meet Integration
1. Extend `GoogleMeetIntegration` class
2. Add UI controls in game view
3. Update chat parsing for new invite formats

## 🐛 Troubleshooting

### Common Issues

#### "Authentication Failed"
- **Solution**: Verify OGS credentials are correct
- **Check**: Network connectivity to online-go.com
- **Note**: Demo uses placeholder client credentials

#### "Board Not Rendering"
- **Solution**: Check browser console for Canvas errors
- **Verify**: Browser supports HTML5 Canvas
- **Try**: Refresh page to reinitialize renderer

#### "Google Meet Not Working"
- **Expected**: Meet integration requires API setup
- **Fallback**: Simple meet links are generated automatically
- **Alternative**: Copy/paste meet links manually

#### "WebSocket Connection Failed"
- **Check**: Browser security settings
- **Verify**: OGS server accessibility
- **Try**: Disable ad blockers or VPN

### Debug Mode

For development, open browser console and use:

```javascript
// Debug utilities (localhost only)
window.debug.getApp()        // Get app instance
window.debug.getOGS()        // Get OGS client
window.debug.testSGFParser(sgfText)  // Test SGF parsing
window.debug.simulateGame()  // Simulate test game
```

## 🤝 Contributing

This project adapts and extends your SGFPlayer codebase. Key principles:

1. **Preserve SGFPlayer Logic**: Maintain compatibility with existing game engine
2. **Enhance for Web**: Add modern web features while keeping core functionality
3. **Follow Patterns**: Use established architectural patterns from the Swift codebase
4. **Document Changes**: Clearly mark adaptations and new features

## 📄 License

This project is based on your SGFPlayer application. License terms should match your original SGFPlayer licensing.

## 🙏 Acknowledgments

- **SGFPlayer**: Core game engine and rendering logic
- **Online Go Server**: API access and game platform
- **Google Meet**: Video conferencing integration
- **Go Community**: For the beautiful game of Go

---

**🎮 Ready to play beautiful Go games with video chat? Open `index.html` in your browser and start playing!**