-- Migration 004: Add accessToken column to companies table
-- Replaces email-based anonymous access with secure UUID tokens

-- Step 1: Add nullable column
ALTER TABLE companies ADD COLUMN "accessToken" VARCHAR(36) UNIQUE;

-- Step 2: Create index for fast lookups
CREATE INDEX idx_companies_access_token ON companies ("accessToken");

-- Step 3: Backfill existing rows with UUIDs
UPDATE companies SET "accessToken" = gen_random_uuid()::text WHERE "accessToken" IS NULL;

-- Step 4: Make NOT NULL now that all rows have values
ALTER TABLE companies ALTER COLUMN "accessToken" SET NOT NULL;
