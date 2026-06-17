-- migration_002_paneer_delivery_link.sql
--
-- Confirmed workflow:
--   1. Milkman delivers milk in the morning -> milk_deliveries row with net_milk (e.g. 100 kg)
--   2. A 24 kg sample is tested -> paneer_entries row records total_milk_used (24),
--      expected_paneer (4.5 standard), actual_paneer (4.3 from the test)
--   3. actual_milk_total = net_milk * (actual_paneer / expected_paneer)
--      e.g. 100 * (4.3 / 4.5) = 95.556 kg
--   4. That figure is written into milk_deliveries.billable_milk and
--      paneer_adjusted is flipped to true, so the app can show
--      "registered 100 kg (net_milk), actual 95.56 kg (billable_milk)" side by side.
--
-- This migration adds the missing link from a paneer test back to the
-- specific delivery row it adjusts, required since milkman_id + entry_date
-- alone can't disambiguate multiple entries on the same day.

ALTER TABLE paneer_entries
    ADD COLUMN delivery_id uuid REFERENCES milk_deliveries (id) ON DELETE CASCADE;

-- Always per-milkman per the confirmed usage — every test traces to one
-- specific milkman's milk, never a pooled/anonymous sample.
ALTER TABLE paneer_entries
    ALTER COLUMN milkman_id SET NOT NULL;

CREATE INDEX idx_paneer_delivery ON paneer_entries (delivery_id);
