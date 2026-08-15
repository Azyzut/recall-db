-- Add calendar tracking columns to requirements table
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "calendarTracking" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS frequency TEXT CHECK (frequency IN ('annual','semi_annual','quarterly','monthly','one_time'));
