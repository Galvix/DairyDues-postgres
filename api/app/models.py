# app/models.py
#
# Pydantic models for request bodies and API responses.
# Field names match your Flutter model classes so the Dart side barely changes.

from __future__ import annotations
from datetime import date, datetime
from typing import Any
from uuid import UUID
from pydantic import BaseModel, ConfigDict


# ─── Milkmen ────────────────────────────────────────────────────────────────

class MilkmanCreate(BaseModel):
    id: UUID | None = None          # client-generated id for offline-first upserts
    name: str
    milk_rate: float
    khoya_rate: float
    supplies_khoya: bool = False
    is_active: bool = True

class MilkmanUpdate(BaseModel):
    name: str | None = None
    milk_rate: float | None = None
    khoya_rate: float | None = None
    supplies_khoya: bool | None = None
    is_active: bool | None = None

class Milkman(MilkmanCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID


# ─── Milk Deliveries ─────────────────────────────────────────────────────────

class MilkDeliveryCreate(BaseModel):
    id: UUID | None = None             # client-generated id for offline-first upserts
    delivery_date: datetime            # supports multiple entries/day (morning + evening)
    gross_weight: float = 0
    can_weight: float = 0
    net_milk: float = 0                # what the milkman registered as delivered
    notes: str = ""

class MilkDelivery(MilkDeliveryCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    milkman_id: UUID
    billable_milk: float               # net_milk, or adjusted_milk_total once a paneer test runs
    paneer_adjusted: bool


# ─── Khoya Deliveries ────────────────────────────────────────────────────────

class KhoyaDeliveryCreate(BaseModel):
    id: UUID | None = None             # client-generated id for offline-first upserts
    delivery_date: datetime
    weight: float
    notes: str = ""

class KhoyaDelivery(KhoyaDeliveryCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    milkman_id: UUID


# ─── Paneer Entries ──────────────────────────────────────────────────────────

class PaneerEntryCreate(BaseModel):
    id: UUID | None = None             # client-generated id for offline-first upserts
    milkman_id: UUID
    delivery_id: UUID                  # the specific milk_deliveries row being tested
    entry_date: date
    total_milk_used: float             # the lab sample, e.g. 24 kg
    expected_paneer: float             # standard yield for that sample size, e.g. 4.5 kg
    actual_paneer: float               # what the test actually produced, e.g. 4.3 kg
    tolerance_kg: float = 0

class PaneerEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    milkman_id: UUID
    delivery_id: UUID
    entry_date: date
    total_milk_used: float
    expected_paneer: float
    actual_paneer: float
    yield_ratio: float                 # actual_paneer / expected_paneer
    tolerance_kg: float
    adjustment_applied: bool
    adjusted_milk_total: float | None  # net_milk * yield_ratio, written after the test


# ─── Loans ───────────────────────────────────────────────────────────────────

class LoanCreate(BaseModel):
    id: UUID | None = None             # client-generated id for offline-first upserts
    amount: float
    loan_date: datetime
    notes: str = ""

class Loan(LoanCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    milkman_id: UUID


# ─── Weekly Payments ─────────────────────────────────────────────────────────

class WeeklyPaymentCreate(BaseModel):
    week_start_date: datetime
    week_end_date: datetime
    total_milk_kg: float
    milk_earnings: float
    total_khoya_kg: float
    khoya_earnings: float
    total_earnings: float
    loan_deducted: float
    carried_over_loan: float = 0
    net_payable: float
    loan_carry_forward: float = 0
    is_paid: bool = False
    milk_rate_applied: float           # milkmen.milk_rate snapshotted at settlement time
    khoya_rate_applied: float          # milkmen.khoya_rate snapshotted at settlement time

class WeeklyPayment(WeeklyPaymentCreate):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    milkman_id: UUID
    paid_at: datetime | None = None


# ─── Settings ────────────────────────────────────────────────────────────────

class Setting(BaseModel):
    key: str
    value: float

class SettingUpdate(BaseModel):
    value: float


# ─── Print Jobs ──────────────────────────────────────────────────────────────

class PrintJobCreate(BaseModel):
    job_type: str                       # e.g. "weekly_slip", "full_payslip"
    params: dict[str, Any] = {}        # e.g. {"milkman_id": "...", "week_start": "..."}

class PrintJob(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    job_type: str
    params: dict[str, Any]
    status: str
    attempts: int
    error: str | None
    created_at: datetime
    updated_at: datetime
    printed_at: datetime | None
    # `pdf` bytes are NOT returned in list responses — agent fetches separately

class PrintJobStatusUpdate(BaseModel):
    status: str                         # "done" | "failed"
    error: str | None = None


# ─── Mark weekly payment paid by natural key ─────────────────────────────────
# Lets the offline-first app settle a week without knowing the server-assigned
# payment id (which it may not have if the payment was upserted while offline).

class MarkPaidByWeek(BaseModel):
    week_start_date: datetime