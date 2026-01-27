#!/usr/bin/env python3
"""
Auto-play test using direct WebSocket connections (no browser needed).

Usage:
    python scripts/autoplay_ws.py

This is faster than the browser version and good for automated testing.
"""
import asyncio
import json
import random
import httpx
import websockets

API_URL = "http://localhost:8765"
WS_URL = "ws://localhost:8765/ws"
TABLE_ID = "ws-test-table"


class Player:
    def __init__(self, username: str, password: str):
        self.username = username
        self.password = password
        self.user_id = None
        self.access_token = None
        self.ws = None
        self.game_state = None
        self.is_my_turn = False
        self.valid_actions = []
    
    async def register_or_login(self):
        """Register or login via HTTP API."""
        async with httpx.AsyncClient() as client:
            # Try register
            try:
                res = await client.post(
                    f"{API_URL}/api/register",
                    json={"username": self.username, "password": self.password}
                )
                if res.status_code == 200:
                    data = res.json()
                    self.user_id = data["user_id"]
                    self.access_token = data["access_token"]
                    print(f"  ✓ Registered {self.username}")
                    return True
            except:
                pass
            
            # Try login
            res = await client.post(
                f"{API_URL}/api/login",
                json={"username": self.username, "password": self.password}
            )
            if res.status_code == 200:
                data = res.json()
                self.user_id = data["user_id"]
                self.access_token = data["access_token"]
                print(f"  ✓ Logged in {self.username}")
                return True
            
            print(f"  ✗ Auth failed for {self.username}: {res.text}")
            return False
    
    async def connect_ws(self):
        """Connect to WebSocket and authenticate."""
        self.ws = await websockets.connect(WS_URL)
        
        # Authenticate
        await self.ws.send(json.dumps({
            "type": "auth",
            "token": self.access_token
        }))
        
        msg = await self.ws.recv()
        data = json.loads(msg)
        if data.get("type") == "authenticated":
            print(f"  ✓ {self.username} WebSocket connected")
            return True
        
        print(f"  ✗ {self.username} WS auth failed: {data}")
        return False
    
    async def send(self, message: dict):
        """Send a message."""
        await self.ws.send(json.dumps(message))
    
    async def recv(self, timeout: float = 5.0):
        """Receive a message with timeout."""
        try:
            msg = await asyncio.wait_for(self.ws.recv(), timeout)
            return json.loads(msg)
        except asyncio.TimeoutError:
            return None
    
    def update_state(self, msg: dict):
        """Update local state from message."""
        if msg.get("type") == "game_state":
            self.game_state = msg
            self.is_my_turn = msg.get("current_player") == self.user_id
            self.valid_actions = msg.get("valid_actions", [])
    
    async def play_action(self) -> bool:
        """Play an action if it's our turn."""
        if not self.is_my_turn or not self.valid_actions:
            return False
        
        # Simple strategy
        roll = random.random()
        
        if roll < 0.05 and "fold" in self.valid_actions:
            action = "fold"
        elif roll < 0.2 and "raise" in self.valid_actions:
            action = "raise"
            amount = self.game_state.get("min_raise", 4)
        elif "check" in self.valid_actions:
            action = "check"
        elif "call" in self.valid_actions:
            action = "call"
        else:
            action = self.valid_actions[0]
        
        msg = {"type": "action", "action": action}
        if action == "raise":
            msg["amount"] = amount
        
        await self.send(msg)
        print(f"  {self.username}: {action.upper()}")
        
        self.is_my_turn = False
        return True


async def create_table(token: str, table_id: str):
    """Create a table via HTTP API."""
    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{API_URL}/api/tables",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "table_id": table_id,
                "small_blind": 1,
                "big_blind": 2,
                "max_players": 10
            }
        )
        if res.status_code == 200:
            print(f"  ✓ Created table '{table_id}'")
            return True
        elif "already exists" in res.text:
            print(f"  ✓ Table '{table_id}' already exists")
            return True
        print(f"  ✗ Failed to create table: {res.text}")
        return False


async def process_messages(player: Player, timeout: float = 0.5):
    """Process all pending messages for a player."""
    while True:
        msg = await player.recv(timeout)
        if not msg:
            break
        player.update_state(msg)
        
        msg_type = msg.get("type", "unknown")
        if msg_type == "error":
            print(f"  [{player.username}] Error: {msg.get('message')}")
        elif msg_type == "hand_result":
            winners = msg.get("winners", [])
            for w in winners:
                print(f"  🏆 {w.get('username')} wins ${w.get('amount')}")


async def main():
    print("=" * 50)
    print("Poker Auto-Play (WebSocket)")
    print("=" * 50)
    
    # Create players
    player1 = Player("wsplayer1", "test123")
    player2 = Player("wsplayer2", "test123")
    
    # Auth
    print("\n--- Authentication ---")
    if not await player1.register_or_login():
        return
    if not await player2.register_or_login():
        return
    
    # Create table (player1 must be admin - promote first if needed)
    print("\n--- Table Setup ---")
    await create_table(player1.access_token, TABLE_ID)
    
    # Connect WebSockets
    print("\n--- WebSocket Connections ---")
    if not await player1.connect_ws():
        return
    if not await player2.connect_ws():
        return
    
    # Join table
    print("\n--- Joining Table ---")
    await player1.send({"type": "join_table", "table_id": TABLE_ID})
    await asyncio.sleep(0.5)
    await process_messages(player1)
    
    await player2.send({"type": "join_table", "table_id": TABLE_ID})
    await asyncio.sleep(0.5)
    await process_messages(player2)
    
    print(f"  ✓ Both players joined")
    
    # Give chips (admin)
    print("\n--- Giving Chips ---")
    await player1.send({"type": "give_chips", "player": player1.username, "amount": 1000})
    await asyncio.sleep(0.3)
    await player1.send({"type": "give_chips", "player": player2.username, "amount": 1000})
    await asyncio.sleep(0.5)
    await process_messages(player1)
    await process_messages(player2)
    print(f"  ✓ Chips given")
    
    # Start hand
    print("\n--- Starting Game ---")
    await player1.send({"type": "start_game"})
    await asyncio.sleep(0.5)
    await process_messages(player1)
    await process_messages(player2)
    
    # Play loop
    print("\n--- Playing Hands ---")
    hands_played = 0
    max_hands = 10
    
    while hands_played < max_hands:
        # Process any pending messages
        await process_messages(player1, 0.2)
        await process_messages(player2, 0.2)
        
        # Try to play
        played1 = await player1.play_action()
        if played1:
            await asyncio.sleep(0.3)
            await process_messages(player1, 0.2)
            await process_messages(player2, 0.2)
        
        played2 = await player2.play_action()
        if played2:
            await asyncio.sleep(0.3)
            await process_messages(player1, 0.2)
            await process_messages(player2, 0.2)
        
        # Check if hand ended
        if player1.game_state and player1.game_state.get("state") == "waiting":
            hands_played += 1
            print(f"\n[Hand {hands_played} complete]")
            
            if hands_played < max_hands:
                await asyncio.sleep(0.5)
                await player1.send({"type": "start_game"})
                await asyncio.sleep(0.5)
                await process_messages(player1, 0.2)
                await process_messages(player2, 0.2)
        
        await asyncio.sleep(0.1)
    
    print("\n" + "=" * 50)
    print(f"Completed {hands_played} hands!")
    print("=" * 50)
    
    # Get final chip counts
    if player1.game_state:
        for p in player1.game_state.get("players", []):
            print(f"  {p.get('username')}: ${p.get('chips')}")
    
    # Close connections
    await player1.ws.close()
    await player2.ws.close()


if __name__ == "__main__":
    asyncio.run(main())
