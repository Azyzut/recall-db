// Migration runner for the Recall Tracker schema.
//
// Runs as a Kubernetes Job before any service starts, and is the first link in
// the deploy chain. Applies every .sql file in migrations/ in filename order,
// exactly once, recording what it applied in a schema_migrations table.
//
// Design notes:
//
//   - Each file runs inside its own transaction, so a failure leaves the
//     database at the last good migration rather than half-applied. Files that
//     manage their own transactions (000_baseline.sql opens with BEGIN) are
//     detected and run without an outer wrapper.
//   - Idempotent by record, not by guesswork: re-running is a no-op, so the Job
//     is safe to retry and safe to run on every deploy.
//   - Waits for the database rather than failing fast. In a cluster the Job may
//     start before Postgres accepts connections.
//
// Deliberately dependency-free beyond `pg`, and run directly under Node's type
// stripping — no build step.

import { readdir, readFile } from 'node:fs/promises';
import { seed } from './seed.ts';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const { Client } = pg;

const MIGRATIONS_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'migrations');
const CONNECT_RETRIES = Number(process.env.DB_CONNECT_RETRIES ?? 30);
const CONNECT_DELAY_MS = Number(process.env.DB_CONNECT_DELAY_MS ?? 2000);

function connectionConfig() {
  const connectionString = (process.env.DATABASE_URL || '').replace(/[?&]sslmode=[^&]*/g, '');
  if (!connectionString) {
    console.error('[migrate] DATABASE_URL is not set.');
    process.exit(1);
  }
  return {
    connectionString,
    ssl: process.env.DATABASE_SSL === 'disable' ? false : { rejectUnauthorized: false },
  };
}

async function connectWithRetry(): Promise<pg.Client> {
  for (let attempt = 1; attempt <= CONNECT_RETRIES; attempt++) {
    const client = new Client(connectionConfig());
    try {
      await client.connect();
      console.log('[migrate] Connected.');
      return client;
    } catch (error) {
      await client.end().catch(() => {});
      const message = error instanceof Error ? error.message : String(error);
      if (attempt === CONNECT_RETRIES) {
        console.error(`[migrate] Could not connect after ${CONNECT_RETRIES} attempts: ${message}`);
        process.exit(1);
      }
      console.log(`[migrate] Database not ready (attempt ${attempt}/${CONNECT_RETRIES}): ${message}`);
      await new Promise(resolve => setTimeout(resolve, CONNECT_DELAY_MS));
    }
  }
  throw new Error('unreachable');
}

async function main() {
  const client = await connectWithRetry();

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename    TEXT PRIMARY KEY,
        applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const applied = new Set(
      (await client.query<{ filename: string }>('SELECT filename FROM schema_migrations'))
        .rows.map(r => r.filename)
    );

    const files = (await readdir(MIGRATIONS_DIR))
      .filter(f => f.endsWith('.sql'))
      .sort();

    if (files.length === 0) {
      console.error(`[migrate] No .sql files found in ${MIGRATIONS_DIR}`);
      process.exit(1);
    }

    let count = 0;

    for (const filename of files) {
      if (applied.has(filename)) {
        console.log(`[migrate] skip     ${filename} (already applied)`);
        continue;
      }

      const sql = await readFile(join(MIGRATIONS_DIR, filename), 'utf8');

      // Files that open their own transaction must not be wrapped in another.
      const selfManaged = /^\s*BEGIN\s*;/im.test(sql);

      console.log(`[migrate] apply    ${filename}`);
      try {
        if (!selfManaged) await client.query('BEGIN');
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [filename]);
        if (!selfManaged) await client.query('COMMIT');
        count++;
      } catch (error) {
        if (!selfManaged) await client.query('ROLLBACK').catch(() => {});
        console.error(`[migrate] FAILED   ${filename}`);
        console.error(error instanceof Error ? error.message : error);
        process.exit(1);
      }
    }

    // Demo accounts, after the schema exists. No-op without SEED_PASSWORD.
    await seed(client);

    console.log(
      count === 0
        ? '[migrate] Up to date, nothing to apply.'
        : `[migrate] Applied ${count} migration${count === 1 ? '' : 's'}.`
    );
  } finally {
    await client.end().catch(() => {});
  }
}

main().catch(error => {
  console.error('[migrate] Unhandled error:', error);
  process.exit(1);
});
