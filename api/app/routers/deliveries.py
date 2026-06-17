# app/routers/deliveries.py

from datetime import date
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from app.auth import require_auth
from app.database import get_pool
from app.models import (
    MilkDelivery, MilkDeliveryCreate,
    KhoyaDelivery, KhoyaDeliveryCreate,
    PaneerEntry, PaneerEntryCreate,
)

router = APIRouter(tags=["deliveries"])


# ─── Milk Deliveries ─────────────────────────────────────────────────────────

@router.get("/milkmen/{milkman_id}/deliveries", response_model=list[MilkDelivery])
async def list_milk_deliveries(
    milkman_id: UUID,
    from_date: date | None = None,
    to_date: date | None = None,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    query = "SELECT * FROM milk_deliveries WHERE milkman_id = $1"
    params: list = [milkman_id]
    if from_date:
        params.append(from_date)
        query += f" AND delivery_date >= ${len(params)}"
    if to_date:
        params.append(to_date)
        query += f" AND delivery_date <= ${len(params)}"
    query += " ORDER BY delivery_date DESC"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("/milkmen/{milkman_id}/deliveries",
             response_model=MilkDelivery, status_code=status.HTTP_201_CREATED)
async def create_milk_delivery(
    milkman_id: UUID,
    body: MilkDeliveryCreate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    # billable_milk starts equal to net_milk; it's only overwritten once a
    # paneer test runs against this delivery (see paneer entry creation below).
    row = await pool.fetchrow(
        """
        INSERT INTO milk_deliveries (
            milkman_id, delivery_date, gross_weight, can_weight, net_milk,
            billable_milk, notes
        )
        VALUES ($1, $2, $3, $4, $5, $5, $6)
        RETURNING *
        """,
        milkman_id, body.delivery_date, body.gross_weight, body.can_weight,
        body.net_milk, body.notes,
    )
    return dict(row)


# ─── Khoya Deliveries ────────────────────────────────────────────────────────

@router.get("/milkmen/{milkman_id}/khoya", response_model=list[KhoyaDelivery])
async def list_khoya_deliveries(
    milkman_id: UUID,
    from_date: date | None = None,
    to_date: date | None = None,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    query = "SELECT * FROM khoya_deliveries WHERE milkman_id = $1"
    params: list = [milkman_id]
    if from_date:
        params.append(from_date)
        query += f" AND delivery_date >= ${len(params)}"
    if to_date:
        params.append(to_date)
        query += f" AND delivery_date <= ${len(params)}"
    query += " ORDER BY delivery_date DESC"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("/milkmen/{milkman_id}/khoya",
             response_model=KhoyaDelivery, status_code=status.HTTP_201_CREATED)
async def create_khoya_delivery(
    milkman_id: UUID,
    body: KhoyaDeliveryCreate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()

    # Gate on supplies_khoya, since the schema makes this a per-milkman toggle.
    milkman = await pool.fetchrow(
        "SELECT supplies_khoya FROM milkmen WHERE id = $1", milkman_id
    )
    if not milkman:
        raise HTTPException(status_code=404, detail="Milkman not found")
    if not milkman["supplies_khoya"]:
        raise HTTPException(
            status_code=400,
            detail="This milkman is not marked as supplying khoya",
        )

    row = await pool.fetchrow(
        """
        INSERT INTO khoya_deliveries (milkman_id, delivery_date, weight, notes)
        VALUES ($1, $2, $3, $4)
        RETURNING *
        """,
        milkman_id, body.delivery_date, body.weight, body.notes,
    )
    return dict(row)


# ─── Paneer Entries ──────────────────────────────────────────────────────────
# Always traced to one specific milkman AND one specific delivery — a sample
# is tested against that delivery's net_milk to catch dilution.
#
# Formula:  adjusted_milk_total = net_milk * (actual_paneer / expected_paneer)
# e.g. milkman registered 100 kg, 24 kg sample tested, standard yield 4.5 kg,
# actual yield 4.3 kg  ->  100 * (4.3 / 4.5) = 95.556 kg actual milk.

@router.get("/milkmen/{milkman_id}/paneer", response_model=list[PaneerEntry])
async def list_paneer_entries(
    milkman_id: UUID,
    from_date: date | None = None,
    to_date: date | None = None,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    query = "SELECT * FROM paneer_entries WHERE milkman_id = $1"
    params: list = [milkman_id]
    if from_date:
        params.append(from_date)
        query += f" AND entry_date >= ${len(params)}"
    if to_date:
        params.append(to_date)
        query += f" AND entry_date <= ${len(params)}"
    query += " ORDER BY entry_date DESC"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("/milkmen/{milkman_id}/paneer",
              response_model=PaneerEntry, status_code=status.HTTP_201_CREATED)
async def create_paneer_entry(
    milkman_id: UUID,
    body: PaneerEntryCreate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()

    if body.expected_paneer <= 0:
        raise HTTPException(status_code=400, detail="expected_paneer must be greater than 0")

    # Confirm the delivery exists and actually belongs to this milkman —
    # otherwise someone could test milkman A's sample against milkman B's delivery.
    delivery = await pool.fetchrow(
        "SELECT id, net_milk FROM milk_deliveries WHERE id = $1 AND milkman_id = $2",
        body.delivery_id, milkman_id,
    )
    if not delivery:
        raise HTTPException(
            status_code=404,
            detail="Delivery not found for this milkman",
        )

    yield_ratio = body.actual_paneer / body.expected_paneer
    adjusted_milk_total = float(delivery["net_milk"]) * yield_ratio

    async with pool.acquire() as conn:
        async with conn.transaction():
            entry = await conn.fetchrow(
                """
                INSERT INTO paneer_entries (
                    milkman_id, delivery_id, entry_date,
                    total_milk_used, expected_paneer, actual_paneer,
                    yield_ratio, tolerance_kg,
                    adjustment_applied, adjusted_milk_total
                )
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8, TRUE, $9)
                RETURNING *
                """,
                milkman_id, body.delivery_id, body.entry_date,
                body.total_milk_used, body.expected_paneer, body.actual_paneer,
                yield_ratio, body.tolerance_kg,
                adjusted_milk_total,
            )

            # Write the corrected figure onto the delivery itself so the app
            # can show "registered 100 kg, actual 95.56 kg" side by side.
            await conn.execute(
                """
                UPDATE milk_deliveries
                SET billable_milk   = $2,
                    paneer_adjusted = TRUE
                WHERE id = $1
                """,
                body.delivery_id, adjusted_milk_total,
            )

    return dict(entry)