#app/database.py

# Sets up a single asyncpg connection pool shared across all requests.  The pool is created on startup and closed on shutdown.
# FastAPI calls connect() on startup and disconnect() on shutdown.  

import asyncpg
from fastapi import FastAPI
import os 

_pool: asyncpg.Pool | None = None

async def connect():
    global _pool
    _pool = await asyncpg.create_pool(
        dsn = os.environ.get("DATABASE_URL"),
        min_size = 2,
        max_size = 10
    )

async def disconnect():
    if _pool:
        await _pool.close()

def get_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("Database pool not initialized. Did you forget to call connect() on startup?")
    return _pool