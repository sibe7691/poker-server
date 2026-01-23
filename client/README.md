# Poker Web Client

A browser-based client for the Poker WebSocket server.

## Quick Start

### Option 1: Open directly

Just open `index.html` in your browser. Note: Some browsers may block WebSocket connections from `file://` URLs.

### Option 2: Serve with Python

```bash
cd client
python3 -m http.server 3000
```

Then open http://localhost:3000

### Option 3: Serve with Node.js

```bash
npx serve client -p 3000
```

Then open http://localhost:3000

## Features

- Login / Register
- View available tables
- Join tables
- Play Texas Hold'em
- Real-time game updates
- Chat with other players
- Automatic reconnection

## Configuration

Edit `app.js` to change the server URLs:

```javascript
const API_URL = 'http://localhost:8765';
const WS_URL = 'ws://localhost:8765/ws';
```

## Screenshots

The client features:
- Dark theme poker table UI
- Oval felt table with player positions
- Community cards display
- Player cards (hidden for opponents)
- Pot and bet displays
- Action buttons (Fold, Check, Call, Raise, All-In)
- Raise slider
- Chat panel
