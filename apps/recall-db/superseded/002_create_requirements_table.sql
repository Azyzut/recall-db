-- Migration: Create requirements table for normalized requirement data
-- Run: psql $DATABASE_URL -f migrations/002_create_requirements_table.sql

-- Create enums for status and priority
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

-- Create requirements table
CREATE TABLE IF NOT EXISTS requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  discovery_id UUID NOT NULL REFERENCES discoveries(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- Core data
  citation VARCHAR(100) NOT NULL,
  title VARCHAR(500) NOT NULL,
  name VARCHAR(500),
  agency VARCHAR(20) NOT NULL CHECK (agency IN ('FDA', 'CPSC')),
  part VARCHAR(20),
  section VARCHAR(50),

  -- AI analysis
  confidence SMALLINT NOT NULL DEFAULT 0 CHECK (confidence >= 0 AND confidence <= 100),
  applies_to TEXT,
  triggers JSONB DEFAULT '[]',
  excerpt TEXT,
  full_text TEXT,
  reasoning TEXT,
  regulation_summary JSONB,
  source VARCHAR(50) DEFAULT 'recall_search',

  -- CRUD fields (user-editable)
  status requirement_compliance_status NOT NULL DEFAULT 'pending',
  priority requirement_priority DEFAULT 'medium',
  notes TEXT,

  -- Audit
  discovered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  modified_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_requirements_company_agency ON requirements(company_id, agency);
CREATE INDEX IF NOT EXISTS idx_requirements_company_status ON requirements(company_id, status);
CREATE INDEX IF NOT EXISTS idx_requirements_discovery ON requirements(discovery_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_requirements_unique ON requirements(discovery_id, citation);

-- Add comment for documentation
COMMENT ON TABLE requirements IS 'Normalized requirements from discoveries, with CRUD support for status/priority/notes';
