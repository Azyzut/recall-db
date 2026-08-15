-- Migration: Alter requirements table to add missing columns
-- Run: psql $DATABASE_URL -f migrations/003_alter_requirements_table.sql

-- Create enums if they don't exist
DO $$ BEGIN
  CREATE TYPE requirement_compliance_status AS ENUM (
    'pending', 'in_progress', 'compliant', 'non_compliant', 'n_a'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE requirement_priority AS ENUM ('high', 'medium', 'low');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Add missing columns (only if they don't exist)
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS name VARCHAR(500);
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS part VARCHAR(20);
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS section VARCHAR(50);
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "appliesTo" TEXT;
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS triggers JSONB DEFAULT '[]';
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS excerpt TEXT;
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "fullText" TEXT;
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "regulationSummary" JSONB;
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "discoveredAt" TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS "modifiedByUserId" UUID REFERENCES users(id) ON DELETE SET NULL;

-- Ensure citation is NOT NULL with default
ALTER TABLE requirements ALTER COLUMN citation SET NOT NULL;
ALTER TABLE requirements ALTER COLUMN citation SET DEFAULT '';

-- Ensure agency has constraint (add check if not exists)
DO $$ BEGIN
  ALTER TABLE requirements ADD CONSTRAINT check_agency CHECK (agency IN ('FDA', 'CPSC'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create unique index on discovery + citation (if not exists)
CREATE UNIQUE INDEX IF NOT EXISTS idx_requirements_discovery_citation ON requirements("discoveryId", citation);

-- Comment
COMMENT ON TABLE requirements IS 'Normalized requirements from discoveries, with CRUD support for status/priority/notes';
