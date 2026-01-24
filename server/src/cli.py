#!/usr/bin/env python3
"""CLI tool for poker server administration."""
import asyncio
import sys
from typing import Optional

from src.db.connection import db
from src.auth.roles import Role


async def list_users():
    """List all users."""
    await db.connect()
    try:
        records = await db.fetch(
            "SELECT id, username, role, created_at FROM users ORDER BY created_at"
        )
        
        if not records:
            print("No users found.")
            return
        
        print(f"\n{'Username':<20} {'Role':<10} {'ID':<36} {'Created'}")
        print("-" * 90)
        for r in records:
            created = r['created_at'].strftime('%Y-%m-%d %H:%M') if r['created_at'] else 'N/A'
            print(f"{r['username']:<20} {r['role']:<10} {r['id']!s:<36} {created}")
        print(f"\nTotal: {len(records)} users")
    finally:
        await db.disconnect()


async def promote_user(username: str):
    """Promote a user to admin."""
    await db.connect()
    try:
        result = await db.execute(
            "UPDATE users SET role = $1 WHERE LOWER(username) = LOWER($2)",
            Role.ADMIN.value, username
        )
        
        if "UPDATE 0" in result:
            print(f"Error: User '{username}' not found.")
            sys.exit(1)
        else:
            print(f"Success: '{username}' is now an admin.")
    finally:
        await db.disconnect()


async def demote_user(username: str):
    """Demote a user to player."""
    await db.connect()
    try:
        result = await db.execute(
            "UPDATE users SET role = $1 WHERE LOWER(username) = LOWER($2)",
            Role.PLAYER.value, username
        )
        
        if "UPDATE 0" in result:
            print(f"Error: User '{username}' not found.")
            sys.exit(1)
        else:
            print(f"Success: '{username}' is now a regular player.")
    finally:
        await db.disconnect()


async def delete_user(username: str):
    """Delete a user."""
    await db.connect()
    try:
        result = await db.execute(
            "DELETE FROM users WHERE LOWER(username) = LOWER($1)",
            username
        )
        
        if "DELETE 0" in result:
            print(f"Error: User '{username}' not found.")
            sys.exit(1)
        else:
            print(f"Success: User '{username}' deleted.")
    finally:
        await db.disconnect()


async def get_user(username: str):
    """Get user details."""
    await db.connect()
    try:
        record = await db.fetchrow(
            "SELECT id, username, role, created_at FROM users WHERE LOWER(username) = LOWER($1)",
            username
        )
        
        if not record:
            print(f"Error: User '{username}' not found.")
            sys.exit(1)
        
        print(f"\nUser: {record['username']}")
        print(f"  ID:      {record['id']}")
        print(f"  Role:    {record['role']}")
        print(f"  Created: {record['created_at']}")
    finally:
        await db.disconnect()


def print_usage():
    """Print usage information."""
    print("""
Poker Server CLI

Usage:
  python -m src.cli <command> [args]

Commands:
  list                  List all users
  get <username>        Get user details
  promote <username>    Promote user to admin
  demote <username>     Demote user to player
  delete <username>     Delete a user

Examples:
  python -m src.cli list
  python -m src.cli promote alice
  python -m src.cli demote bob
""")


def main():
    """Main CLI entry point."""
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == "list":
        asyncio.run(list_users())
    
    elif command == "get":
        if len(sys.argv) < 3:
            print("Error: Username required.")
            print("Usage: python -m src.cli get <username>")
            sys.exit(1)
        asyncio.run(get_user(sys.argv[2]))
    
    elif command == "promote":
        if len(sys.argv) < 3:
            print("Error: Username required.")
            print("Usage: python -m src.cli promote <username>")
            sys.exit(1)
        asyncio.run(promote_user(sys.argv[2]))
    
    elif command == "demote":
        if len(sys.argv) < 3:
            print("Error: Username required.")
            print("Usage: python -m src.cli demote <username>")
            sys.exit(1)
        asyncio.run(demote_user(sys.argv[2]))
    
    elif command == "delete":
        if len(sys.argv) < 3:
            print("Error: Username required.")
            print("Usage: python -m src.cli delete <username>")
            sys.exit(1)
        asyncio.run(delete_user(sys.argv[2]))
    
    elif command in ("help", "-h", "--help"):
        print_usage()
    
    else:
        print(f"Unknown command: {command}")
        print_usage()
        sys.exit(1)


if __name__ == "__main__":
    main()
