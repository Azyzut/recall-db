-- Migration 007: Add possibleObligations column for AI-extracted time-based obligations
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "possibleObligations" JSONB DEFAULT '[]'::jsonb;
