-- DairyDues — PostgreSQL schema
-- Mapped directly from lib/database/models.dart (Firestore) so the migration
-- loses no data. Targets PostgreSQL 14+ (Pi 5 typically runs 15/16).
--
-- Conventions:
--   ids        : uuid (replaces Firestore auto-string ids; app already treats ids as String)
--   timestamps : timestamptz (was Firestore Timestamp)
--   weights    : numeric(12,3) kg
--   money      : numeric(12,2)
--   ratios     : numeric(10,4)


CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid() is core in PG13+, this is a safety net

-- ─── MILKMEN ────────────────────────────────────────────────────────────────
CREATE TABLE milkmen (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name           text          NOT NULL,
    milk_rate      numeric(12,2) NOT NULL DEFAULT 0,
    khoya_rate     numeric(12,2) NOT NULL DEFAULT 0,
    supplies_khoya boolean       NOT NULL DEFAULT false,
    is_active      boolean       NOT NULL DEFAULT true
);
CREATE INDEX idx_milkmen_active ON milkmen (is_active);

-- ─── MILK DELIVERIES ────────────────────────────────────────────────────────
CREATE TABLE milk_deliveries (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milkman_id      uuid          NOT NULL REFERENCES milkmen (id) ON DELETE CASCADE,
    delivery_date   timestamptz   NOT NULL,
    gross_weight    numeric(12,3) NOT NULL DEFAULT 0,
    can_weight      numeric(12,3) NOT NULL DEFAULT 0,
    net_milk        numeric(12,3) NOT NULL DEFAULT 0,
    billable_milk   numeric(12,3) NOT NULL DEFAULT 0,
    paneer_adjusted boolean       NOT NULL DEFAULT false,
    notes           text          NOT NULL DEFAULT ''
);
CREATE INDEX idx_deliveries_date          ON milk_deliveries (delivery_date);
CREATE INDEX idx_deliveries_milkman_date  ON milk_deliveries (milkman_id, delivery_date);

-- ─── KHOYA DELIVERIES ───────────────────────────────────────────────────────
CREATE TABLE khoya_deliveries (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milkman_id    uuid          NOT NULL REFERENCES milkmen (id) ON DELETE CASCADE,
    delivery_date timestamptz   NOT NULL,
    weight        numeric(12,3) NOT NULL DEFAULT 0,
    notes         text          NOT NULL DEFAULT ''
);
CREATE INDEX idx_khoya_date         ON khoya_deliveries (delivery_date);
CREATE INDEX idx_khoya_milkman_date ON khoya_deliveries (milkman_id, delivery_date);

-- ─── PANEER ENTRIES ─────────────────────────────────────────────────────────
-- Always traced to one specific milkman AND one specific delivery — a 24kg
-- sample is tested against that delivery's net_milk to catch dilution.
-- Formula: adjusted_milk_total = net_milk * (actual_paneer / expected_paneer),
-- written back into milk_deliveries.billable_milk (see app-layer logic).
CREATE TABLE paneer_entries (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milkman_id          uuid          NOT NULL REFERENCES milkmen (id) ON DELETE CASCADE,
    delivery_id         uuid          REFERENCES milk_deliveries (id) ON DELETE CASCADE,
    entry_date          timestamptz   NOT NULL,
    total_milk_used     numeric(12,3) NOT NULL DEFAULT 0,
    expected_paneer     numeric(12,3) NOT NULL DEFAULT 0,
    actual_paneer       numeric(12,3) NOT NULL DEFAULT 0,
    yield_ratio         numeric(10,4) NOT NULL DEFAULT 1.0,
    tolerance_kg        numeric(10,3) NOT NULL DEFAULT 0,
    adjustment_applied  boolean       NOT NULL DEFAULT false,
    adjusted_milk_total numeric(12,3)            -- nullable
);
CREATE INDEX idx_paneer_date         ON paneer_entries (entry_date);
CREATE INDEX idx_paneer_milkman_date ON paneer_entries (milkman_id, entry_date);
CREATE INDEX idx_paneer_delivery     ON paneer_entries (delivery_id);

-- ─── LOANS ──────────────────────────────────────────────────────────────────
CREATE TABLE loans (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milkman_id uuid          NOT NULL REFERENCES milkmen (id) ON DELETE CASCADE,
    loan_date  timestamptz   NOT NULL,
    amount     numeric(12,2) NOT NULL DEFAULT 0,
    notes      text          NOT NULL DEFAULT ''
);
CREATE INDEX idx_loans_milkman_date ON loans (milkman_id, loan_date);

-- ─── WEEKLY PAYMENTS ────────────────────────────────────────────────────────
CREATE TABLE weekly_payments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milkman_id          uuid          NOT NULL REFERENCES milkmen (id) ON DELETE CASCADE,
    week_start_date     timestamptz   NOT NULL,
    week_end_date       timestamptz   NOT NULL,
    total_milk_kg       numeric(12,3) NOT NULL DEFAULT 0,
    milk_earnings       numeric(12,2) NOT NULL DEFAULT 0,
    total_khoya_kg      numeric(12,3) NOT NULL DEFAULT 0,
    khoya_earnings      numeric(12,2) NOT NULL DEFAULT 0,
    total_earnings      numeric(12,2) NOT NULL DEFAULT 0,
    loan_deducted       numeric(12,2) NOT NULL DEFAULT 0,
    carried_over_loan   numeric(12,2) NOT NULL DEFAULT 0,
    net_payable         numeric(12,2) NOT NULL DEFAULT 0,
    loan_carry_forward  numeric(12,2) NOT NULL DEFAULT 0,
    is_paid             boolean       NOT NULL DEFAULT false,
    paid_at             timestamptz,
    -- Snapshotted at settlement time — without this, a milkman's rate change
    -- later would make it impossible to reconstruct exactly how a past
    -- week's payout was calculated.
    milk_rate_applied   numeric(12,2) NOT NULL DEFAULT 0,
    khoya_rate_applied  numeric(12,2) NOT NULL DEFAULT 0,
    -- one payment row per milkman per week (matches upsertWeeklyPayment logic)
    UNIQUE (milkman_id, week_start_date)
);
CREATE INDEX idx_payments_milkman_week ON weekly_payments (milkman_id, week_start_date);

COMMENT ON COLUMN weekly_payments.milk_rate_applied  IS 'milkmen.milk_rate at the time this week was settled';
COMMENT ON COLUMN weekly_payments.khoya_rate_applied IS 'milkmen.khoya_rate at the time this week was settled';

-- ─── SETTINGS ───────────────────────────────────────────────────────────────
-- Was a Firestore collection of single-value docs. Seeded with the app defaults.
CREATE TABLE settings (
    key   text PRIMARY KEY,
    value double precision NOT NULL
);
INSERT INTO settings (key, value) VALUES
    ('standard_paneer_kg',   6.5),
    ('sample_milk_kg',       24.0),
    ('paneer_tolerance_kg',  0.5)
ON CONFLICT (key) DO NOTHING;

-- ─── PRINT JOBS (new) ───────────────────────────────────────────────────────
-- The queue the home print-agent polls. Server generates the PDF and stores the
-- bytes; the agent downloads, prints via CUPS, and reports status back.
CREATE TABLE print_jobs (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_type   text        NOT NULL,                 -- e.g. 'weekly_slip', 'full_payslip'
    params     jsonb       NOT NULL DEFAULT '{}',    -- e.g. {"milkmanId": "...", "weekStart": "..."}
    status     text        NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending','printing','done','failed')),
    pdf        bytea,                                -- rendered server-side, null until generated
    attempts   integer     NOT NULL DEFAULT 0,
    error      text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    printed_at timestamptz
);
CREATE INDEX idx_print_jobs_status ON print_jobs (status, created_at);

-- keep updated_at fresh as the worker/agent move a job through its states
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_print_jobs_touch
    BEFORE UPDATE ON print_jobs
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();