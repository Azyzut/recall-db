-- Give the seeded companies a geographic spread, so a region-based target group
-- in Feature Management has something to select.
--
-- All three seeded companies were west coast (OR, WA, CA), which made a "us-east"
-- target group impossible to demonstrate — every rule matched everybody or nobody.
-- Northwind moves to New York and Harborline to Massachusetts, leaving Tidepool in
-- California: two east, one west.
--
-- Why a migration and not just an edit to src/seed.ts. The seed's company block is
-- create-only: it selects on "normalizedWebsite" and skips the insert entirely when
-- a row comes back, so editing the seed changes nothing on a database that has
-- already been seeded. Only the password is re-applied on every run. src/seed.ts is
-- updated too, for databases that do not exist yet — migrations run BEFORE seed()
-- in migrate.ts, so on a fresh database this statement matches no rows and the seed
-- is what puts the right value in.
--
-- Matched on "normalizedWebsite" rather than "companyName", because that is the key
-- the seed itself uses and it is not something an attendee can edit from the UI.
--
-- NOTE: this is a starting value, not a fixed one. Running a discovery overwrites
-- "state" with the Distribution Region chosen in the form (see
-- packages/shared/src/services/company.ts). A company that has run a discovery holds
-- whatever region was selected then, not what this migration set.

UPDATE companies SET state = 'NY'
 WHERE "normalizedWebsite" = 'northwind-devices.example.com';

UPDATE companies SET state = 'MA'
 WHERE "normalizedWebsite" = 'harborline-foods.example.com';
