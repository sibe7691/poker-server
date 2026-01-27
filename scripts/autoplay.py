#!/usr/bin/env python3
"""
Auto-play test script using two browser windows.

Usage:
    python scripts/autoplay.py

Prerequisites:
    - Server running at localhost:8765
    - Client served at localhost:3000
    - pip install playwright && playwright install chromium
"""
import asyncio
import random
from playwright.async_api import async_playwright, Page

CLIENT_URL = "http://localhost:3000"
API_URL = "http://localhost:8765"
TABLE_ID = "test-table"

# Test users
PLAYER1 = {"username": "player1", "password": "test123"}
PLAYER2 = {"username": "player2", "password": "test123"}


async def register_or_login(page: Page, username: str, password: str) -> bool:
    """Register a new user or login if exists."""
    # Try to register first
    await page.fill("#register-username", username)
    await page.fill("#register-password", password)
    
    # Click register tab first
    await page.click('[data-tab="register"]')
    await asyncio.sleep(0.3)
    
    await page.fill("#register-username", username)
    await page.fill("#register-password", password)
    await page.click('#register-form button[type="submit"]')
    
    await asyncio.sleep(1)
    
    # Check if we're in lobby (success) or still on auth (need to login)
    if await page.locator("#lobby-screen:not(.hidden)").count() > 0:
        print(f"  ✓ Registered {username}")
        return True
    
    # Try login instead
    await page.click('[data-tab="login"]')
    await asyncio.sleep(0.3)
    
    await page.fill("#login-username", username)
    await page.fill("#login-password", password)
    await page.click('#login-form button[type="submit"]')
    
    await asyncio.sleep(1)
    
    if await page.locator("#lobby-screen:not(.hidden)").count() > 0:
        print(f"  ✓ Logged in {username}")
        return True
    
    print(f"  ✗ Failed to auth {username}")
    return False


async def create_table_if_admin(page: Page, table_id: str):
    """Create a table if user is admin."""
    # Check if create button is visible
    create_btn = page.locator("#create-table-btn:not(.hidden)")
    if await create_btn.count() > 0:
        print(f"  Creating table '{table_id}'...")
        await create_btn.click()
        await asyncio.sleep(0.3)
        
        await page.fill("#new-table-id", table_id)
        await page.fill("#new-small-blind", "1")
        await page.fill("#new-big-blind", "2")
        await page.click('#create-table-form button[type="submit"]')
        await asyncio.sleep(1)
        print(f"  ✓ Table created")


async def join_table(page: Page, table_id: str):
    """Join a table."""
    await page.click("#refresh-tables")
    await asyncio.sleep(0.5)
    
    # Find and click join button for our table
    join_btn = page.locator(f'button:has-text("Join")').first
    if await join_btn.count() > 0:
        await join_btn.click()
        await asyncio.sleep(1)
        print(f"  ✓ Joined table")
    else:
        print(f"  ✗ No table to join")


async def give_chips_to_players(page: Page, amount: int = 1000):
    """Give chips to all players at the table (admin only)."""
    give_btn = page.locator("#btn-give-chips")
    if await give_btn.count() == 0:
        return
    
    # Get player list from dropdown
    await give_btn.click()
    await asyncio.sleep(0.3)
    
    # Get all options
    options = await page.locator("#chips-player option").all()
    player_names = []
    for opt in options:
        val = await opt.get_attribute("value")
        if val:
            player_names.append(val)
    
    for player in player_names:
        await page.select_option("#chips-player", player)
        await page.fill("#chips-amount", str(amount))
        await page.click('#give-chips-form button[type="submit"]')
        await asyncio.sleep(0.3)
        print(f"  ✓ Gave {amount} chips to {player}")
    
    await page.click("#cancel-give-chips")
    await asyncio.sleep(0.3)


async def start_hand(page: Page):
    """Start a hand (admin only)."""
    start_btn = page.locator("#btn-start-hand")
    if await start_btn.count() > 0:
        await start_btn.click()
        await asyncio.sleep(1)
        print(f"  ✓ Started hand")


async def play_turn(page: Page, player_name: str):
    """Play a turn if it's our turn."""
    # Check if any action button is enabled
    actions = ["#btn-check", "#btn-call", "#btn-fold"]
    
    for action_id in actions:
        btn = page.locator(f"{action_id}:not([disabled])")
        if await btn.count() > 0:
            action_name = action_id.replace("#btn-", "")
            
            # Random strategy: 70% call/check, 20% raise, 10% fold
            roll = random.random()
            
            if roll < 0.1:  # Fold sometimes
                fold_btn = page.locator("#btn-fold:not([disabled])")
                if await fold_btn.count() > 0:
                    await fold_btn.click()
                    print(f"  {player_name}: FOLD")
                    return True
            elif roll < 0.3:  # Raise sometimes
                raise_btn = page.locator("#btn-raise:not([disabled])")
                if await raise_btn.count() > 0:
                    await raise_btn.click()
                    await asyncio.sleep(0.2)
                    # Click the confirm raise button
                    await page.click("#btn-raise-confirm")
                    print(f"  {player_name}: RAISE")
                    return True
            
            # Default: check or call
            check_btn = page.locator("#btn-check:not([disabled])")
            if await check_btn.count() > 0:
                await check_btn.click()
                print(f"  {player_name}: CHECK")
                return True
            
            call_btn = page.locator("#btn-call:not([disabled])")
            if await call_btn.count() > 0:
                await call_btn.click()
                print(f"  {player_name}: CALL")
                return True
    
    return False


async def get_game_state(page: Page) -> str:
    """Get current game state."""
    state_el = page.locator("#game-state")
    if await state_el.count() > 0:
        return await state_el.inner_text()
    return "unknown"


async def run_player(context, player: dict, is_admin: bool = False):
    """Run a player session."""
    page = await context.new_page()
    await page.goto(CLIENT_URL)
    await asyncio.sleep(1)
    
    print(f"\n[{player['username']}] Starting...")
    
    # Login/Register
    if not await register_or_login(page, player["username"], player["password"]):
        return None
    
    # Create table if admin
    if is_admin:
        await create_table_if_admin(page, TABLE_ID)
    
    await asyncio.sleep(0.5)
    
    # Join table
    await join_table(page, TABLE_ID)
    
    return page


async def main():
    print("=" * 50)
    print("Poker Auto-Play Test")
    print("=" * 50)
    print(f"Client: {CLIENT_URL}")
    print(f"Server: {API_URL}")
    print("=" * 50)
    
    async with async_playwright() as p:
        # Launch browser with two windows
        browser = await p.chromium.launch(headless=False)
        
        # Create two separate contexts (like incognito windows)
        context1 = await browser.new_context()
        context2 = await browser.new_context()
        
        # Start both players
        print("\n--- Setting up players ---")
        page1 = await run_player(context1, PLAYER1, is_admin=True)
        page2 = await run_player(context2, PLAYER2, is_admin=False)
        
        if not page1 or not page2:
            print("Failed to set up players")
            await browser.close()
            return
        
        await asyncio.sleep(1)
        
        # Admin gives chips
        print("\n--- Giving chips ---")
        await give_chips_to_players(page1, 1000)
        
        await asyncio.sleep(1)
        
        # Start the hand
        print("\n--- Starting game ---")
        await start_hand(page1)
        
        await asyncio.sleep(1)
        
        # Play loop
        print("\n--- Playing hands ---")
        hands_played = 0
        max_hands = 5
        
        while hands_played < max_hands:
            state = await get_game_state(page1)
            print(f"\n[Hand {hands_played + 1}] State: {state}")
            
            # Keep playing until hand ends
            turns = 0
            max_turns = 20  # Safety limit
            
            while turns < max_turns:
                # Check both players for their turn
                played1 = await play_turn(page1, PLAYER1["username"])
                await asyncio.sleep(0.5)
                
                played2 = await play_turn(page2, PLAYER2["username"])
                await asyncio.sleep(0.5)
                
                if not played1 and not played2:
                    # No one could play, check state
                    new_state = await get_game_state(page1)
                    if new_state == "waiting":
                        print(f"  Hand complete!")
                        hands_played += 1
                        
                        # Start new hand
                        await asyncio.sleep(1)
                        await start_hand(page1)
                        await asyncio.sleep(1)
                        break
                    await asyncio.sleep(0.5)
                
                turns += 1
            
            if turns >= max_turns:
                print("  Max turns reached, starting new hand")
                hands_played += 1
                await start_hand(page1)
                await asyncio.sleep(1)
        
        print("\n" + "=" * 50)
        print(f"Completed {hands_played} hands!")
        print("=" * 50)
        
        # Keep browsers open for inspection
        print("\nBrowsers will stay open. Press Ctrl+C to exit.")
        try:
            await asyncio.sleep(3600)  # Keep open for 1 hour
        except KeyboardInterrupt:
            pass
        
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
