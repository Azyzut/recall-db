-- Migration 008: Add requirementId to documents table for per-requirement file uploads
ALTER TABLE documents ADD COLUMN IF NOT EXISTS "requirementId" UUID REFERENCES requirements(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_documents_requirement_id ON documents("requirementId");
