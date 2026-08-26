-- Migration 006: Performance indexes for faster queries
-- These indexes optimize the most common query patterns in the application

-- Index for company lookup by email (case-insensitive) - used in auth flows
CREATE INDEX IF NOT EXISTS idx_companies_contact_email_lower
  ON companies(LOWER("contactEmail"));

-- Composite index for requirements filtered by company and priority
CREATE INDEX IF NOT EXISTS idx_requirements_company_priority
  ON requirements("companyId", priority);

-- Composite index for requirements sorted by confidence within a discovery
CREATE INDEX IF NOT EXISTS idx_requirements_discovery_confidence
  ON requirements("discoveryId", confidence DESC, citation ASC);

-- Index for user lookup by email (case-insensitive) - used in auth flows
CREATE INDEX IF NOT EXISTS idx_users_email_lower
  ON users(LOWER(email));

-- Index for requirements filtered by company and status (common matrix page query)
CREATE INDEX IF NOT EXISTS idx_requirements_company_status
  ON requirements("companyId", status);

-- Index for requirements filtered by company and agency (tab switching)
CREATE INDEX IF NOT EXISTS idx_requirements_company_agency
  ON requirements("companyId", agency);
