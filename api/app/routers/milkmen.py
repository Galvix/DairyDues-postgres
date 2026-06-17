# app/routers/milkmen.py

from uuid import UUID, uuid4
from fastapi import APIRouter, Depends, HTTPException, status
from app.auth import require_auth
from app.database import get_pool
from app.models import Milkman, MilkmanCreate, MilkmanUpdate

router = APIRouter(prefix="/milkmen", tags=["milkmen"])


@router.get("/", response_model=list[Milkman])
async def list_milkmen(
    active_only: bool = False,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    query = "SELECT * FROM milkmen"
    if active_only:
        query += " WHERE is_active = TRUE"
    query += " ORDER BY name"
    rows = await pool.fetch(query)
    return [dict(r) for r in rows]


@router.post("/", response_model=Milkman, status_code=status.HTTP_201_CREATED)
async def create_milkman(
    body: MilkmanCreate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    # Upsert by id so an offline-created milkman re-syncs idempotently. The id is
    # client-generated when present, otherwise minted here.
    row = await pool.fetchrow(
        """
        INSERT INTO milkmen (id, name, milk_rate, khoya_rate, supplies_khoya, is_active)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (id) DO UPDATE SET
            name           = EXCLUDED.name,
            milk_rate      = EXCLUDED.milk_rate,
            khoya_rate     = EXCLUDED.khoya_rate,
            supplies_khoya = EXCLUDED.supplies_khoya,
            is_active      = EXCLUDED.is_active
        RETURNING *
        """,
        body.id or uuid4(), body.name, body.milk_rate, body.khoya_rate,
        body.supplies_khoya, body.is_active,
    )
    return dict(row)


@router.get("/{milkman_id}", response_model=Milkman)
async def get_milkman(
    milkman_id: UUID,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    row = await pool.fetchrow("SELECT * FROM milkmen WHERE id = $1", milkman_id)
    if not row:
        raise HTTPException(status_code=404, detail="Milkman not found")
    return dict(row)


@router.patch("/{milkman_id}", response_model=Milkman)
async def update_milkman(
    milkman_id: UUID,
    body: MilkmanUpdate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    # Only update fields that were actually sent
    updates = body.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = ${i+2}" for i, k in enumerate(updates))
    values = list(updates.values())
    row = await pool.fetchrow(
        f"UPDATE milkmen SET {set_clause} WHERE id = $1 RETURNING *",
        milkman_id, *values,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Milkman not found")
    return dict(row)


@router.delete("/{milkman_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_milkman(
    milkman_id: UUID,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    result = await pool.execute("DELETE FROM milkmen WHERE id = $1", milkman_id)
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Milkman not found")