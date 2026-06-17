from datetime import date, datetime
from uuid import UUID
from fastapi import HTTPException, APIRouter, Depends, status
from app.auth import require_auth
from app.database import get_pool
from app.models import Loan, LoanCreate, WeeklyPayment, WeeklyPaymentCreate

router = APIRouter(tags=["payments"])

#-----------------Loans------------------------

@router.get("/milkmen/{milkman_id}/loans", response_model=list[Loan])
async def list_loans(
    milkman_id: UUID,
    *,
    _: None = Depends(require_auth)
):
    pool = get_pool()
    rows = await pool.fetch(
        "SELECT * FROM loans WHERE milkman_id = $1 ORDER BY loan_date DESC",
        milkman_id,
    )
    return [dict(r) for r in rows]


@router.post("/milkmen/{milkman_id}/loans",
             response_model=Loan, status_code=status.HTTP_201_CREATED)
async def create_loan(
    milkman_id: UUID,
    body: LoanCreate,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO loans (milkman_id, amount, loan_date, notes)
        VALUES ($1, $2, $3, $4)
        RETURNING *
        """,
        milkman_id, body.amount, body.loan_date, body.notes,
    )
    return dict(row)
 

@router.delete("/loans/{loan_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_loan(
    loan_id: UUID,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    result = await pool.execute("DELETE FROM loans WHERE id = $1", loan_id)
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Loan not found")
 

#--------------Weekly Payments-------------------------------


@router.get("/milkmen/{milkman_id}/payments", response_model=list[WeeklyPayment])
async def list_payments(
    milkman_id: UUID,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool(),
    rows = await pool.fetch(
        "SELECT * FROM weekly_payments WHERE milkman_id = $1 ORDER BY week_start_date DESC",
        milkman_id,
    )
    return [dict(r) for r in rows]


@router.post("/milkmen/{milkman_id}/payments",
             response_model=WeeklyPayment, status_code=status.HTTP_201_CREATED)
async def upsert_payment(
    milkman_id: UUID,
    body: WeeklyPaymentCreate,
    *,
    _: None = Depends(require_auth),
):
    """
    Upsert a weekly payment row — one per (milkman, week_start_date), matching
    the schema's UNIQUE constraint. Re-submitting recalculates in place.
    """
    pool = get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO weekly_payments (
            milkman_id, week_start_date, week_end_date,
            total_milk_kg, milk_earnings,
            total_khoya_kg, khoya_earnings,
            total_earnings, loan_deducted, carried_over_loan,
            net_payable, loan_carry_forward, is_paid,
            milk_rate_applied, khoya_rate_applied
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
        ON CONFLICT (milkman_id, week_start_date) DO UPDATE SET
            week_end_date       = EXCLUDED.week_end_date,
            total_milk_kg       = EXCLUDED.total_milk_kg,
            milk_earnings       = EXCLUDED.milk_earnings,
            total_khoya_kg      = EXCLUDED.total_khoya_kg,
            khoya_earnings      = EXCLUDED.khoya_earnings,
            total_earnings      = EXCLUDED.total_earnings,
            loan_deducted       = EXCLUDED.loan_deducted,
            carried_over_loan   = EXCLUDED.carried_over_loan,
            net_payable         = EXCLUDED.net_payable,
            loan_carry_forward  = EXCLUDED.loan_carry_forward,
            is_paid              = EXCLUDED.is_paid,
            milk_rate_applied   = EXCLUDED.milk_rate_applied,
            khoya_rate_applied  = EXCLUDED.khoya_rate_applied
        RETURNING *
        """,
        milkman_id,
        body.week_start_date,
        body.week_end_date,
        body.total_milk_kg,
        body.milk_earnings,
        body.total_khoya_kg,
        body.khoya_earnings,
        body.total_earnings,
        body.loan_deducted,
        body.carried_over_loan,
        body.net_payable,
        body.loan_carry_forward,
        body.is_paid,
        body.milk_rate_applied,
        body.khoya_rate_applied,
    )
    return dict(row)
 
 

@router.patch("/payments/{payment_id}/mark-paid", response_model=WeeklyPayment)
async def mark_payment_paid(
    payment_id: UUID,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    row = await pool.fetchrow(
        """
        UPDATE weekly_payments
        SET is_paid = TRUE, paid_at = now()
        WHERE id = $1
        RETURNING *
        """,
        payment_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Payment not found")
    return dict(row)
 
 
# ─── Hisab calculation (server-side) ─────────────────────────────────────────
 
@router.get("/milkmen/{milkman_id}/hisab")
async def calculate_hisab(
    milkman_id: UUID,
    week_start: datetime,
    week_end: datetime,
    *,
    _: None = Depends(require_auth),
):
    """
    Calculate the weekly hisab (account summary) for a milkman without saving it.
    The Flutter app can call this to preview before the user confirms payment.
 
    Uses billable_milk (not net_milk) so any paneer-test adjustment for the
    week is automatically reflected — that's the whole point of the column.
    """
    pool = get_pool()
 
    milkman = await pool.fetchrow("SELECT * FROM milkmen WHERE id = $1", milkman_id)
    if not milkman:
        raise HTTPException(status_code=404, detail="Milkman not found")
 
    milk_total = await pool.fetchval(
        """
        SELECT COALESCE(SUM(billable_milk), 0)
        FROM milk_deliveries
        WHERE milkman_id = $1 AND delivery_date BETWEEN $2 AND $3
        """,
        milkman_id, week_start, week_end,
    )
 
    khoya_total = 0.0
    if milkman["supplies_khoya"]:
        khoya_total = await pool.fetchval(
            """
            SELECT COALESCE(SUM(weight), 0)
            FROM khoya_deliveries
            WHERE milkman_id = $1 AND delivery_date BETWEEN $2 AND $3
            """,
            milkman_id, week_start, week_end,
        )
 
    pending_loans = await pool.fetchval(
        "SELECT COALESCE(SUM(amount), 0) FROM loans WHERE milkman_id = $1",
        milkman_id,
    )
 
    milk_kg    = float(milk_total)
    khoya_kg   = float(khoya_total)
    milk_rate  = float(milkman["milk_rate"])
    khoya_rate = float(milkman["khoya_rate"])
 
    milk_earnings  = milk_kg  * milk_rate
    khoya_earnings = khoya_kg * khoya_rate
    total_earnings = milk_earnings + khoya_earnings
    loan_deducted  = min(float(pending_loans), total_earnings)
    net_payable    = total_earnings - loan_deducted
 
    return {
        "milkman_id":         str(milkman_id),
        "week_start":         week_start,
        "week_end":           week_end,
        "total_milk_kg":      milk_kg,
        "total_khoya_kg":     khoya_kg,
        "milk_rate_applied":  milk_rate,
        "khoya_rate_applied": khoya_rate,
        "milk_earnings":      milk_earnings,
        "khoya_earnings":     khoya_earnings,
        "total_earnings":     total_earnings,
        "pending_loans":      float(pending_loans),
        "loan_deducted":      loan_deducted,
        "net_payable":        net_payable,
    }
 