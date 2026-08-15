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
export const headerTheme = new Rox.RoxString('default', ['default', 'smb']);
