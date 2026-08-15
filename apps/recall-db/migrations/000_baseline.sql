-- Migration 000 — Baseline schema
--
-- Reconstructed from packages/shared/src/db.ts, which is the authoritative
-- description of this schema: it is what Kysely issues queries against.
--
-- Why this file exists. Migration 001 is absent from the repository, so
-- companies, users, discoveries and documents were created by no committed
-- migration. Worse, 002 and 003 disagree with each other and with the code:
-- 002 creates snake_case columns (discovery_id, company_id, applies_to) while
-- 003 adds camelCase ones ("appliesTo", "discoveredAt") and indexes
-- "discoveryId", which 002 never created. There are no RENAME statements
-- anywhere. Running 002-009 against an empty database does not reproduce the
-- schema the application expects.
--
-- This file therefore supersedes 001-003 for a fresh database. Apply it on its
-- own, then 004 onward. Against the existing shared RDS, do not run it at all —
-- every statement is guarded, but it is intended for new databases.
--
--   psql "$DATABASE_URL" -f migrations/000_baseline.sql
--
-- Column names are quoted camelCase throughout, matching the Kysely types.
-- Postgres folds unquoted identifiers to lower case, so the quoting is load
-- bearing — without it every query in the application fails.

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================================
-- Enums
-- =============================================================================

DO $$ BEGIN CREATE TYPE discovered_by_type AS ENUM ('ANONYMOUS', 'PAID_USER');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE agency_type AS ENUM ('FDA', 'CPSC');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE file_type AS ENUM ('PDF', 'XLSX', 'DOCX', 'TXT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE message_role AS ENUM ('USER', 'ASSISTANT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE custom_agency_type AS ENUM ('CITY', 'COUNTY', 'STATE', 'INTERNAL', 'OTHER');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE requirement_status AS ENUM ('ACTIVE', 'ARCHIVED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE override_status AS ENUM ('APPLICABLE', 'NOT_APPLICABLE', 'FLAGGED', 'DELETED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE admin_action AS ENUM ('MERGE_COMPANIES', 'EDIT_COMPANY', 'DELETE_COMPANY', 'EDIT_USER', 'DELETE_USER');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE target_type AS ENUM ('COMPANY', 'USER', 'DISCOVERY');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE memory_category AS ENUM ('facility', 'compliance', 'preference', 'process', 'personnel');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =============================================================================
-- Core tables
-- =============================================================================

CREATE TABLE IF NOT EXISTS companies (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  website             TEXT NOT NULL,
  "normalizedWebsite" TEXT NOT NULL,
  "companyName"       TEXT NOT NULL,
  "naicsCode"         TEXT NOT NULL,
  "discoveredBy"      discovered_by_type NOT NULL DEFAULT 'ANONYMOUS',
  "firstDiscoveredAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "lastUpdatedAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "websiteAnalysis"   JSONB,
  "employeeCount"     INTEGER,
  state               TEXT,
  "contactEmail"      TEXT,
  -- VARCHAR(36), not UUID: migration 004 backfills this with
  -- gen_random_uuid()::text and the Kysely type is Generated<string>.
  "accessToken"       VARCHAR(36) NOT NULL DEFAULT gen_random_uuid()::text,
  "mergedIntoId"      UUID REFERENCES companies(id) ON DELETE SET NULL,
  "mergedAt"          TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "isAnonymous"      BOOLEAN NOT NULL DEFAULT TRUE,
  "sessionToken"     TEXT,
  email              TEXT,
  "passwordHash"     TEXT,
  "stripeCustomerId" TEXT,
  "companyId"        UUID REFERENCES companies(id) ON DELETE SET NULL,
  "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "lastActiveAt"     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS discoveries (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId"    UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  agency         agency_type NOT NULL,
  requirements   JSONB NOT NULL DEFAULT '[]'::jsonb,
  metadata       JSONB,
  "discoveredAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "expiresAt"    TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS user_discoveries (
  "userId"      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "discoveryId" UUID NOT NULL REFERENCES discoveries(id) ON DELETE CASCADE,
  "triggeredAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY ("userId", "discoveryId")
);

CREATE TABLE IF NOT EXISTS documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "companyId"     UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "requirementId" UUID,
  filename        TEXT NOT NULL,
  "fileType"      file_type NOT NULL,
  "s3Key"         TEXT NOT NULL,
  "fileSizeBytes" BIGINT NOT NULL,
  "extractedText" TEXT,
  "uploadedAt"    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  "companyId"        UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  role               message_role NOT NULL,
  content            TEXT NOT NULL,
  "citedRegulations" JSONB,
  "citedDocuments"   JSONB,
  "toolCalls"        JSONB,
  model              TEXT,
  "tokenUsage"       JSONB,
  "latencyMs"        INTEGER,
  "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS custom_requirements (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "companyId"        UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  "createdByUserId"  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title              TEXT NOT NULL,
  agency             TEXT NOT NULL,
  "agencyType"       custom_agency_type NOT NULL,
  description        TEXT,
  "renewalDate"      DATE,
  "contactName"      TEXT,
  "contactEmail"     TEXT,
  "contactPhone"     TEXT,
  attachments        JSONB,
  status             requirement_status NOT NULL DEFAULT 'ACTIVE',
  "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS requirement_user_overrides (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "discoveryId"        UUID NOT NULL REFERENCES discoveries(id) ON DELETE CASCADE,
  "regulationCitation" TEXT NOT NULL,
  "userId"             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status               override_status NOT NULL,
  reason               TEXT,
  notes                TEXT,
  "createdAt"          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS admin_audit_log (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "adminUserId"  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action         admin_action NOT NULL,
  "targetType"   target_type NOT NULL,
  "targetId"     UUID NOT NULL,
  "beforeState"  JSONB,
  "afterState"   JSONB,
  reason         TEXT,
  "performedAt"  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- requirements is created here in the shape the application expects: quoted
-- camelCase throughout. This replaces migrations 002 and 003, which produce a
-- table the code cannot query.
CREATE TABLE IF NOT EXISTS requirements (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "discoveryId"         UUID REFERENCES discoveries(id) ON DELETE CASCADE,
  "companyId"           UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  citation              TEXT NOT NULL,
  title                 TEXT NOT NULL,
  name                  TEXT,
  agency                TEXT NOT NULL,
  part                  TEXT,
  section               TEXT,
  confidence            INTEGER,
  "appliesTo"           TEXT,
  triggers              JSONB NOT NULL DEFAULT '[]'::jsonb,
  excerpt               TEXT,
  "fullText"            TEXT,
  reasoning             TEXT,
  "regulationSummary"   JSONB,
  source                TEXT NOT NULL DEFAULT 'discovery',
  status                TEXT NOT NULL DEFAULT 'pending',
  priority              INTEGER,
  notes                 TEXT,
  "discoveredAt"        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "createdAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "modifiedByUserId"    UUID REFERENCES users(id) ON DELETE SET NULL,
  description           TEXT,
  "dueDate"             DATE,
  "assignedTo"          TEXT,
  "deletedAt"           TIMESTAMPTZ,
  "sortOrder"           INTEGER,
  "createdBy"           TEXT,
  "calendarTracking"    BOOLEAN NOT NULL DEFAULT FALSE,
  frequency             TEXT
);

-- Guarded: ADD CONSTRAINT has no IF NOT EXISTS, and this file must stay
-- re-runnable because the migration Job may execute against a database that is
-- already partly built.
DO $$ BEGIN
  ALTER TABLE documents
    ADD CONSTRAINT documents_requirement_fk
    FOREIGN KEY ("requirementId") REFERENCES requirements(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS user_memory (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category         memory_category NOT NULL,
  fact             TEXT NOT NULL,
  source           TEXT NOT NULL,
  "conversationId" TEXT,
  "createdAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updatedAt"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "expiresAt"      TIMESTAMPTZ
);

-- =============================================================================
-- Indexes
-- =============================================================================

-- Deliberately NOT unique. The website field is optional, and
-- normalizeWebsite('') returns an empty string rather than NULL, so every
-- company created without a website would collide on a unique index. The real
-- database had this constraint originally and it was dropped ad hoc via
-- scripts/drop-website-unique.mjs — this baseline reflects the corrected state
-- rather than reintroducing the bug.
CREATE INDEX IF NOT EXISTS idx_companies_normalized_website ON companies("normalizedWebsite");
CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_access_token       ON companies("accessToken");
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email                  ON users(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS        idx_users_company                ON users("companyId");
CREATE INDEX IF NOT EXISTS        idx_discoveries_company          ON discoveries("companyId");
CREATE INDEX IF NOT EXISTS        idx_requirements_company         ON requirements("companyId");
CREATE INDEX IF NOT EXISTS        idx_requirements_discovery       ON requirements("discoveryId");
CREATE INDEX IF NOT EXISTS        idx_documents_company            ON documents("companyId");
CREATE INDEX IF NOT EXISTS        idx_chat_messages_company        ON chat_messages("companyId");
CREATE INDEX IF NOT EXISTS        idx_user_memory_user             ON user_memory("userId");

COMMIT;

-- After this file, apply 005 onward:
--   for f in migrations/00[5-9]*.sql; do
--     docker exec -i recall-pg psql -U postgres -d recall < "$f"
--   done
--
-- Skip 002, 003 and 004 — this baseline supersedes all three. 004 in particular
-- will emit "already exists" errors for the accessToken column and its index,
-- because they are created here.
--
-- 005 through 008 are effectively no-ops (IF NOT EXISTS guarded, columns
-- already present), but harmless and cheap to run. 009 does the real remaining
-- work: the pgvector extension, embedding columns and indexes, the
-- obligation_embeddings and document_chunks tables, and the "conversationId"
-- column on chat_messages.
