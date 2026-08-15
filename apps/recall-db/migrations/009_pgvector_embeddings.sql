-- Migration 009: pgvector foundation for compliance agent semantic search
-- Requires pgvector 0.8.0+ (available on RDS PostgreSQL 15.14)

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Layer 1: Regulation summary embeddings (on existing requirements table)
ALTER TABLE requirements ADD COLUMN IF NOT EXISTS embedding vector(1024);

-- 3. Layer 2: Individual obligation embeddings (extracted from possibleObligations JSONB)
CREATE TABLE IF NOT EXISTS obligation_embeddings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "requirementId" UUID NOT NULL REFERENCES requirements(id) ON DELETE CASCADE,
  "companyId" UUID NOT NULL,
  "obligationIndex" INTEGER NOT NULL,
  "obligationText" TEXT NOT NULL,
  embedding vector(1024),
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE ("requirementId", "obligationIndex")
);

-- 4. Layer 3: Document chunk embeddings
CREATE TABLE IF NOT EXISTS document_chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "documentId" UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  "companyId" UUID NOT NULL,
  "chunkIndex" INTEGER NOT NULL,
  "chunkText" TEXT NOT NULL,
  embedding vector(1024),
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE ("documentId", "chunkIndex")
);

-- 5. Document-level embedding for small docs
ALTER TABLE documents ADD COLUMN IF NOT EXISTS embedding vector(1024);

-- 6. Chat message enhancements for compliance agent
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS "conversationId" UUID;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS "toolCalls" JSONB;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS "tokenUsage" JSONB;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS "latencyMs" INTEGER;

-- 7. HNSW indexes for vector similarity search (cosine distance)
CREATE INDEX IF NOT EXISTS idx_requirements_embedding_hnsw
  ON requirements USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_obligation_embeddings_hnsw
  ON obligation_embeddings USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding_hnsw
  ON document_chunks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_documents_embedding_hnsw
  ON documents USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

-- 8. B-tree indexes for multi-tenant filtering (filter by companyId BEFORE vector scan)
CREATE INDEX IF NOT EXISTS idx_obligation_embeddings_company
  ON obligation_embeddings ("companyId");

CREATE INDEX IF NOT EXISTS idx_document_chunks_company
  ON document_chunks ("companyId");

-- 9. GIN indexes on new JSONB columns in chat_messages
CREATE INDEX IF NOT EXISTS idx_chat_messages_tool_calls
  ON chat_messages USING GIN ("toolCalls");

CREATE INDEX IF NOT EXISTS idx_chat_messages_token_usage
  ON chat_messages USING GIN ("tokenUsage");

-- 10. Conversation grouping index
CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation
  ON chat_messages ("conversationId", "createdAt");
