# app/routers/settings.py

from fastapi import APIRouter, Depends, HTTPException
from app.auth import require_auth
from app.database import get_pool
from app.models import Setting, SettingUpdate

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("/", response_model=list[Setting])
async def list_settings(_: None = Depends(require_auth)):
    pool = get_pool()
    rows = await pool.fetch("SELECT key, value FROM settings ORDER BY key")
    return [dict(r) for r in rows]


@router.get("/{key}", response_model=Setting)
async def get_setting(key: str, _: None = Depends(require_auth)):
    pool = get_pool()
    row = await pool.fetchrow("SELECT key, value FROM settings WHERE key = $1", key)
    if not row:
        raise HTTPException(status_code=404, detail="Setting not found")
    return dict(row)


@router.put("/{key}", response_model=Setting)
async def upsert_setting(
    key: str,
    body: SettingUpdate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO settings (key, value) VALUES ($1, $2)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
        RETURNING key, value
        """,
        key, body.value,
    )
    return dict(row)