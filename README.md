# Poker WebSocket Server

A lightweight, robust Texas Hold'em poker server built with Python, FastAPI, and WebSockets.

## Features

- **Texas Hold'em** - Full game logic including blinds, betting rounds, hand evaluation
- **FastAPI + WebSockets** - HTTP API for auth/admin, WebSockets for real-time game
- **JWT Authentication** - Secure auth with access/refresh tokens
- **Admin Role** - Chip management, ledger tracking, standings calculation, table management
- **Reconnection Support** - Players can reconnect within grace period without losing their seat
- **PostgreSQL** - Robust persistence for users, ledger, and transaction history
- **Redis** - Fast in-memory state for real-time game data and sessions
- **Docker Ready** - Easy deployment with docker-compose

## Table of Contents

- [Setup](#setup)
- [Web Client](#web-client)
- [CLI Admin Tool](#cli-admin-tool)
- [HTTP API](#http-api)
- [WebSocket API](#websocket-api)
- [Configuration](#configuration)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [Documentation Links](#documentation-links)

---

## Setup

### Prerequisites

- Python 3.13+ (3.14 recommended)
- Docker & Docker Compose (recommended)
- Or: PostgreSQL 16+ and Redis 7+ running locally

### Using Docker (Recommended)

```bash
# Clone and enter directory
cd pk

# Copy environment template
cp .env.example .env

# Start all services (app, postgres, redis)
docker-compose up --build

# Server runs on http://localhost:8765
# WebSocket endpoint: ws://localhost:8765/ws
```

### Manual Setup

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start PostgreSQL
docker run -d --name postgres \
  -e POSTGRES_USER=poker \
  -e POSTGRES_PASSWORD=poker \
  -e POSTGRES_DB=poker \
  -p 5432:5432 postgres:16-alpine

# Start Redis
docker run -d --name redis -p 6379:6379 redis:7-alpine

# Set environment variables
export DATABASE_URL=postgresql://poker:poker@localhost:5432/poker
export REDIS_URL=redis://localhost:6379
export JWT_SECRET=your-secret-key-change-in-production

# Run the server
uvicorn src.main:app --host 0.0.0.0 --port 8765
```

### Verify Installation

```bash
# Check health endpoint
curl http://localhost:8765/health

# Expected: {"status":"healthy","redis":true,"postgres":true}
```

---

## Web Client

A browser-based poker client is included in the `client/` folder.

### Running the Client

```bash
# Option 1: Python
cd client
python3 -m http.server 3000

# Option 2: Node.js
npx serve client -p 3000
```

Then open http://localhost:3000

### Features

- Login / Register forms
- Lobby with table list
- Poker table with oval felt design
- Player positions around the table
- Community cards and pot display
- Action buttons (Fold, Check, Call, Raise, All-In)
- Raise slider for custom amounts
- Chat panel
- Automatic reconnection

**Admin Features (in-game):**
- Start Hand button
- Give/Take Chips modal with preset amounts (+100, +500, +1000, -100, -500)
- Real-time chip updates for all players

---

## CLI Admin Tool

Manage users from the command line:

```bash
# Activate virtual environment
source venv/bin/activate

# List all users
python -m src.cli list

# Promote user to admin
python -m src.cli promote alice

# Demote admin to player
python -m src.cli demote alice

# Get user details
python -m src.cli get alice

# Delete user
python -m src.cli delete bob
```

With Docker:
```bash
docker-compose exec app python -m src.cli promote alice
```

---

## HTTP API

Base URL: `http://localhost:8765`

### Authentication

#### Register a new user

```bash
curl -X POST http://localhost:8765/api/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "secret123"}'
```

Response:
```json
{
  "user_id": "uuid-here",
  "username": "alice",
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

#### Login

```bash
curl -X POST http://localhost:8765/api/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "secret123"}'
```

#### Refresh token

```bash
curl -X POST http://localhost:8765/api/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "eyJ..."}'
```

### Tables (Admin only)

#### List all tables

```bash
curl http://localhost:8765/api/tables
```

Response:
```json
{
  "tables": [
    {
      "table_id": "main",
      "players": 3,
      "max_players": 10,
      "state": "waiting",
      "small_blind": 1,
      "big_blind": 2
    }
  ]
}
```

#### Create a table

```bash
curl -X POST http://localhost:8765/api/tables \
  -H "Authorization: Bearer <admin_access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "table_id": "high-stakes",
    "small_blind": 5,
    "big_blind": 10,
    "max_players": 6
  }'
```

#### Delete a table

```bash
curl -X DELETE "http://localhost:8765/api/tables?table_id=high-stakes" \
  -H "Authorization: Bearer <admin_access_token>"
```

### Standings

```bash
curl "http://localhost:8765/api/standings?session_id=<session_id>"
```

---

## WebSocket API

Connect to: `ws://localhost:8765/ws`

### Connection Flow

1. Connect to WebSocket
2. Authenticate with JWT token
3. Join a table
4. Play!

### JavaScript Example

```javascript
const ws = new WebSocket('ws://localhost:8765/ws');

ws.onopen = () => {
  // Step 1: Authenticate
  ws.send(JSON.stringify({
    type: 'auth',
    token: '<your_access_token>'
  }));
};

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  console.log('Received:', msg);

  if (msg.type === 'authenticated') {
    // Step 2: Join a table
    ws.send(JSON.stringify({
      type: 'join_table',
      table_id: 'main',
      seat: 0  // optional, auto-assigned if omitted
    }));
  }

  if (msg.type === 'game_state') {
    // Handle game state updates
    console.log('Pot:', msg.pot);
    console.log('Your cards:', msg.players.find(p => p.is_you)?.cards);
    console.log('Valid actions:', msg.valid_actions);
  }
};

// Send game action
function sendAction(action, amount = 0) {
  ws.send(JSON.stringify({
    type: 'action',
    action: action,  // 'fold', 'check', 'call', 'bet', 'raise', 'all_in'
    amount: amount
  }));
}

// Examples
sendAction('call');
sendAction('raise', 100);
sendAction('fold');
```

### Python Example

```python
import asyncio
import websockets
import json

async def play_poker():
    uri = "ws://localhost:8765/ws"
    
    async with websockets.connect(uri) as ws:
        # Authenticate
        await ws.send(json.dumps({
            "type": "auth",
            "token": "<your_access_token>"
        }))
        
        auth_response = await ws.recv()
        print(f"Auth: {auth_response}")
        
        # Join table
        await ws.send(json.dumps({
            "type": "join_table",
            "table_id": "main"
        }))
        
        # Listen for messages
        async for message in ws:
            data = json.loads(message)
            print(f"Received: {data['type']}")
            
            if data["type"] == "game_state":
                # Your turn?
                if data.get("current_player") == "<your_user_id>":
                    # Simple bot: always call or check
                    if "call" in data["valid_actions"]:
                        await ws.send(json.dumps({
                            "type": "action",
                            "action": "call"
                        }))
                    elif "check" in data["valid_actions"]:
                        await ws.send(json.dumps({
                            "type": "action",
                            "action": "check"
                        }))

asyncio.run(play_poker())
```

### Message Types

#### Client → Server

| Type | Description | Fields |
|------|-------------|--------|
| `auth` | Authenticate connection | `token` |
| `register` | Create new account | `username`, `password` |
| `login` | Login to account | `username`, `password` |
| `join_table` | Join a poker table | `table_id`, `seat?` |
| `leave_table` | Leave current table | - |
| `action` | Game action | `action`, `amount?` |
| `chat` | Send chat message | `message` |
| `start_game` | Start a new hand (admin) | - |
| `create_table` | Create table (admin) | `table_id`, `small_blind?`, `big_blind?`, `max_players?` |
| `delete_table` | Delete table (admin) | `table_id` |
| `give_chips` | Buy-in chips (admin) | `player`, `amount` |
| `take_chips` | Cash-out chips (admin) | `player`, `amount` |
| `get_ledger` | Get transaction history (admin) | - |
| `get_standings` | Get player standings (admin) | - |

#### Server → Client

| Type | Description |
|------|-------------|
| `authenticated` | Auth successful |
| `auth_success` | Login/register successful with tokens |
| `error` | Error message |
| `game_state` | Full game state update |
| `player_action` | Another player acted |
| `player_joined` | Player joined table |
| `player_left` | Player left table |
| `hand_result` | Hand finished with winners |
| `chips_updated` | Player chips changed (admin action) |
| `hand_started` | New hand started |
| `state_changed` | Game state changed (preflop→flop, etc.) |
| `chat` | Chat message |
| `ledger` | Transaction history |
| `standings` | Player standings |
| `table_created` | Table was created |
| `table_deleted` | Table was deleted |
| `tables_list` | List of available tables |

### Game State Message

```json
{
  "type": "game_state",
  "table_id": "main",
  "state": "preflop",
  "hand_number": 5,
  "dealer_seat": 2,
  "small_blind": 1,
  "big_blind": 2,
  "pot": 150,
  "community_cards": ["Ah", "Kd", "Qs"],
  "players": [
    {
      "user_id": "uuid",
      "username": "alice",
      "seat": 0,
      "chips": 450,
      "current_bet": 50,
      "hole_cards": ["As", "Kh"],
      "has_cards": true,
      "is_folded": false,
      "is_all_in": false
    }
  ],
  "current_player": "uuid",
  "valid_actions": ["fold", "call", "raise"],
  "call_amount": 50,
  "min_raise": 100
}
```

---

## Configuration

Environment variables (copy `.env.example` to `.env`):

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql://poker:poker@postgres:5432/poker` | PostgreSQL connection |
| `REDIS_URL` | `redis://redis:6379` | Redis connection |
| `JWT_SECRET` | `dev-secret-change-in-production` | **Change in production!** |
| `JWT_EXPIRY_MINUTES` | `15` | Access token expiry |
| `JWT_REFRESH_EXPIRY_DAYS` | `7` | Refresh token expiry |
| `RECONNECT_GRACE_SECONDS` | `60` | Disconnect grace period |
| `HOST` | `0.0.0.0` | Server bind host |
| `PORT` | `8765` | Server bind port |
| `LOG_LEVEL` | `INFO` | Logging verbosity |

---

## Testing

```bash
# Activate virtual environment
source venv/bin/activate

# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test file
pytest tests/test_hand_eval.py

# Run with coverage report
pip install pytest-cov
pytest --cov=src --cov-report=html
```

---

## Project Structure

```
pk/
├── docker-compose.yml      # Docker orchestration
├── Dockerfile              # App container
├── requirements.txt        # Python dependencies
├── pytest.ini              # Test configuration
├── .env.example            # Environment template
├── client/                 # Web client
│   ├── index.html          # Main HTML
│   ├── style.css           # Styles
│   ├── app.js              # Client logic
│   └── README.md           # Client docs
├── src/
│   ├── main.py             # FastAPI app + WebSocket server
│   ├── cli.py              # Admin CLI tool
│   ├── config.py           # Configuration management
│   ├── auth/               # Authentication
│   │   ├── jwt_handler.py  # JWT token management
│   │   ├── middleware.py   # WebSocket auth middleware
│   │   ├── password.py     # Password hashing (bcrypt)
│   │   └── roles.py        # Role definitions
│   ├── admin/              # Admin functionality
│   │   ├── chip_manager.py # Chip operations
│   │   ├── ledger.py       # Transaction ledger
│   │   └── standings.py    # Player standings
│   ├── db/                 # Database
│   │   ├── connection.py   # PostgreSQL connection pool
│   │   └── models.py       # Schema definitions
│   ├── game/               # Game logic
│   │   ├── table.py        # Table state machine
│   │   ├── betting.py      # Betting round logic
│   │   ├── hand_eval.py    # Hand evaluation
│   │   ├── pot.py          # Pot/side-pot calculation
│   │   ├── player.py       # Player model
│   │   └── deck.py         # Cards and deck
│   ├── state/              # State management
│   │   ├── redis_client.py # Redis wrapper
│   │   ├── game_store.py   # Game state persistence
│   │   ├── session_store.py# Session management
│   │   └── user_store.py   # User persistence
│   ├── protocol/           # WebSocket protocol
│   │   ├── messages.py     # Pydantic message schemas
│   │   └── handlers.py     # Message handlers
│   └── utils/
│       └── logger.py       # Structured logging
└── tests/                  # Test suite
    ├── test_auth.py        # Auth tests
    ├── test_admin.py       # Admin/ledger tests
    ├── test_api.py         # Protocol/message tests
    ├── test_betting.py     # Betting logic tests
    ├── test_game_flow.py   # Game flow tests
    ├── test_hand_eval.py   # Hand evaluation tests
    ├── test_pot.py         # Pot calculation tests
    └── test_reconnect.py   # Reconnection tests
```

---

## Documentation Links

### Technologies Used

- **[FastAPI](https://fastapi.tiangolo.com/)** - Modern Python web framework
- **[websockets](https://websockets.readthedocs.io/)** - WebSocket library for Python
- **[Pydantic](https://docs.pydantic.dev/)** - Data validation
- **[asyncpg](https://magicstack.github.io/asyncpg/)** - Async PostgreSQL driver
- **[redis-py](https://redis-py.readthedocs.io/)** - Async Redis client
- **[PyJWT](https://pyjwt.readthedocs.io/)** - JWT implementation
- **[bcrypt](https://github.com/pyca/bcrypt)** - Password hashing
- **[pytest](https://docs.pytest.org/)** - Testing framework

### Poker Rules Reference

- [Texas Hold'em Rules](https://www.pokernews.com/poker-rules/texas-holdem.htm)
- [Hand Rankings](https://www.cardplayer.com/rules-of-poker/hand-rankings)

### Deployment

- **[Docker Compose](https://docs.docker.com/compose/)** - Container orchestration
- **[Uvicorn](https://www.uvicorn.org/)** - ASGI server for production

---

## License

MIT
