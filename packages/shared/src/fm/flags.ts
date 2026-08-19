// @ts-ignore — @types/rox-node is v5, runtime is v6
import Rox from 'rox-node';

// ── Boolean flags (kill switches) ──────────────────────────────
export const featureFlags = {
  recallAdvisor:    new Rox.Flag(false),   // AI compliance agent
  exportPdf:        new Rox.Flag(false),   // PDF export
  calendarView:     new Rox.Flag(false),   // Calendar view
  errorState:       new Rox.Flag(false),   // Demo kill switch — force a 404 on login
};

// ── Number configs (remote tuning) ─────────────────────────────
export const configFlags = {};

// ── String variant (target-group targeting) ────────────────────
// @ts-ignore — RoxString exists in rox-node v6
// DO NOT DELETE A FLAG IN CLOUDBEES FEATURE MANAGEMENT TO "RESET" IT.
// Deletion is irreversible and reserves the name — an SDK cannot recreate it, and
// reusing the name requires a CloudBees Support request. That is how the previous
// A flag registered with two variants cannot later be widened to four; deleting it
// to force re-registration destroys the name for the whole organisation.
//
// A flag's variant list is fixed at first registration. Get it right before the
// first deploy, or ship a new flag name.
//
// Four variants, matching matrixThemeConfigs in apps/web-ui/app/matrix/page.tsx
// and navThemeConfigs in apps/web-ui/components/Navbar.tsx. `dark` and `branded`
// were styled but unreachable: the flag offered only two variants, so nothing
// could ever select them.
//
// The variant list MUST match the browser-side declaration in
// apps/web-ui/components/providers/FMProvider.tsx. Rox registers variants from
// whichever SDK connects, and a mismatch means the options differ depending on
// which service reported last.
export const headerTheme = new Rox.RoxString('default', ['default', 'dark', 'smb', 'branded']);
