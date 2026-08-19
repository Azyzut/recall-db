// Demo accounts, so a freshly migrated database is usable without every attendee
// registering first.
//
// SECURITY: seeding is SKIPPED unless LOGIN_PASSWORD is set. No password, no
// accounts. The hash is computed at runtime, so no credential is committed — these
// repos are templates attendees copy, and a bcrypt hash in git is a published
// password. The app is reachable on a public hostname, so a known password in the
// repository would be an open door.
//
// Idempotent: re-running changes nothing. Keyed on company website and user email.
//
// Three companies, one per companySize bucket in packages/shared/src/fm/setup.ts:
//   >= 500 enterprise, >= 100 mid-market, otherwise small
// Feature Management targeting rules can key on that property, so a single bucket
// would leave a rule impossible to demonstrate.
//
// All data is fictional. example.com is reserved by RFC 2606 and cannot be
// registered, so these can never collide with a real company.
import type { Client } from 'pg';
import bcrypt from 'bcryptjs';

const SALT_ROUNDS = 10;

interface SeedCompany {
  website: string;
  companyName: string;
  naicsCode: string;
  employeeCount: number;
  state: string;
  email: string;
  bucket: string;
}

const COMPANIES: SeedCompany[] = [
  {
    website: 'https://northwind-devices.example.com',
    companyName: 'Northwind Devices',
    naicsCode: '339112',            // Surgical and Medical Instrument Manufacturing
    employeeCount: 1200,
    state: 'OR',
    email: 'enterprise@example.com',
    bucket: 'enterprise',
  },
  {
    website: 'https://harborline-foods.example.com',
    companyName: 'Harborline Foods',
    naicsCode: '311999',            // All Other Miscellaneous Food Manufacturing
    employeeCount: 250,
    state: 'WA',
    email: 'midmarket@example.com',
    bucket: 'mid-market',
  },
  {
    website: 'https://tidepool-supply.example.com',
    companyName: 'Tidepool Supply Co',
    naicsCode: '423450',            // Medical Equipment Merchant Wholesalers
    employeeCount: 45,
    state: 'CA',
    email: 'small@example.com',
    bucket: 'small',
  },
];

const normalize = (url: string) =>
  url.replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/\/$/, '').toLowerCase();

export async function seed(client: Client): Promise<void> {
  const password = process.env.LOGIN_PASSWORD;
  if (!password) {
    console.log('[seed] LOGIN_PASSWORD not set — skipping demo accounts.');
    console.log('[seed] Attendees will need to register an account manually.');
    return;
  }

  const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
  let created = 0;

  for (const c of COMPANIES) {
    // ON CONFLICT is not usable here: normalizedWebsite has a NON-unique index
    // (see 000_baseline.sql), so there is no constraint to conflict on.
    const existing = await client.query<{ id: string }>(
      'SELECT id FROM companies WHERE "normalizedWebsite" = $1 LIMIT 1',
      [normalize(c.website)],
    );

    let companyId = existing.rows[0]?.id;
    if (!companyId) {
      // discoveredBy is the enum discovered_by_type, which allows exactly
      // 'ANONYMOUS' and 'PAID_USER' (000_baseline.sql:34). A seeded account has a
      // real login, so PAID_USER is the honest value — and inventing a third one
      // fails at insert with:
      //   invalid input value for enum discovered_by_type: "..."

      const inserted = await client.query<{ id: string }>(
        `INSERT INTO companies
           (website, "normalizedWebsite", "companyName", "naicsCode",
            "employeeCount", state, "contactEmail", "discoveredBy")
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'PAID_USER')
         RETURNING id`,
        [c.website, normalize(c.website), c.companyName, c.naicsCode,
         c.employeeCount, c.state, c.email],
      );
      companyId = inserted.rows[0].id;
      console.log(`[seed] company  ${c.companyName} (${c.employeeCount} employees, ${c.bucket})`);
    }

    // A company with no discoveries row is a state the app cannot reach on its own:
    // /api/compliance/me returns 404 for it, and the matrix has nothing to render.
    // The worker always creates this row before scanning, so seeding one puts the
    // account in the same shape a real discovery would.
    //
    // Requirements are left empty on purpose. Fabricating compliance obligations
    // would put invented regulatory text in front of customers; the attendee
    // populates it for real with "Find More Recalls" in Module 06.
    const discovery = await client.query<{ id: string }>(
      'SELECT id FROM discoveries WHERE "companyId" = $1 LIMIT 1',
      [companyId],
    );
    if (discovery.rows.length === 0) {
      await client.query(
        `INSERT INTO discoveries ("companyId", agency, requirements, metadata)
         VALUES ($1, 'FDA', '[]'::jsonb, $2::jsonb)`,
        [companyId, JSON.stringify({ seeded: true, note: 'Empty discovery so the matrix loads; run a discovery to populate.' })],
      );
      console.log(`[seed] discovery for ${c.companyName} (empty; run a discovery to populate)`);
    }

    const user = await client.query<{ id: string }>(
      'SELECT id FROM users WHERE email = $1 LIMIT 1',
      [c.email.toLowerCase()],
    );
    if (user.rows.length === 0) {
      await client.query(
        `INSERT INTO users (email, "passwordHash", "companyId", "isAnonymous")
         VALUES ($1, $2, $3, FALSE)`,
        [c.email.toLowerCase(), passwordHash, companyId],
      );
      console.log(`[seed] user     ${c.email} -> ${c.companyName}`);
      created++;
    } else {
      // Keep the password in step with LOGIN_PASSWORD, so rotating it actually works.
      await client.query('UPDATE users SET "passwordHash" = $1, "companyId" = $2 WHERE email = $3',
        [passwordHash, companyId, c.email.toLowerCase()]);
    }
  }

  console.log(created > 0
    ? `[seed] ${created} demo account(s) created. Password: the LOGIN_PASSWORD value.`
    : '[seed] Demo accounts already present; passwords refreshed.');
}
