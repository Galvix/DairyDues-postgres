# app/main.py

from contextlib import asynccontextmanager
from fastapi import FastAPI
from app import database
from app.routers import milkmen, deliveries, payments, print_jobs, settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: open the DB connection pool
    await database.connect()
    yield
    # Shutdown: close it cleanly
    await database.disconnect()


app = FastAPI(
    title="DairyDues API",
    version="1.0.0",
    # Disable the public docs in production — nothing should be browsable
    # from outside your tailnet. Comment these out during local development
    # if you want the /docs Swagger UI.
    docs_url=None,
    redoc_url=None,
    lifespan=lifespan,
)

# ─── Routers ──────────────────────────────────────────────────────────────────
app.include_router(milkmen.router,    prefix="/api/v1")
app.include_router(deliveries.router, prefix="/api/v1")
app.include_router(payments.router,   prefix="/api/v1")
app.include_router(print_jobs.router, prefix="/api/v1")
app.include_router(settings.router,   prefix="/api/v1")


# ─── Health check (no auth — used by Docker healthcheck and the proxy) ────────
@app.get("/health")
async def health():
    pool = database.get_pool()
    await pool.fetchval("SELECT 1")          # verifies DB is reachable
    return {"status": "ok"}