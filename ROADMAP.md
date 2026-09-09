# ZB Smart Gizmo Pro — Roadmap

This file did not previously exist; created as part of the 2026-07-07 audit
(`AUDIT_REPORT.md`, `CLEANUP_PLAN.md`). It tracks forward-looking, non-urgent items that came out
of the audit but are bigger than a single cleanup commit — decisions and follow-up work rather
than immediate fixes. Update it as items are resolved or new ones surface.

## Open decisions carried over from the audit

- **Native Smart Scale backend (`zb_smart_gizmo_pro/native_backend.rb` + `native/`)**: currently
  unreachable dead code (see `AUDIT_REPORT.md` M1). Decide whether to finish wiring it in as a
  performance path for Smart Scale, or retire it in favor of the existing pure-Ruby
  `SmartScaleApplier` (`overlay.rb`). Until decided, do not add new functionality on top of the
  native path — the Ruby path is what actually ships and runs today.
- **Legacy extension ID strategy (`zb_smart_gismo` vs `zb_smart_gizmo_pro`)**: there is a real,
  reasonable case for keeping a "LegacyID" build for users who installed under the old misspelled
  name before the rename. Formalize this as a documented, permanent part of the release process
  (see `CLEANUP_PLAN.md` Phase 0/1) rather than an undocumented loose file, so it survives the
  next person who touches the release pipeline.
- **Trial/licensing feature**: `ZB_Smart_Gizmo_Project_Launch_Plan.md` describes a 14-day trial
  with Smart Scale locking after expiry. No such gating exists in code today. If this is still the
  intended go-to-market plan, it needs to be scoped and built before submission; if the plan has
  changed, the docs should be updated to match reality.

## Housekeeping to revisit periodically

- Re-run a naming-drift check (`gizmo` vs `gismo`, version strings) before every release build,
  since the audit found the last stale-documentation drift (`WAREHOUSE_SUBMISSION_CHECKLIST.md`)
  went unnoticed for roughly two months after the rename.
- Once `.gitignore` is in place (`CLEANUP_PLAN.md` Phase 1), confirm new `Release/` and `backups/`
  output never gets accidentally staged — a periodic `git status` check before committing is
  sufficient, no tooling needed for a project this size.
- Revisit whether `backups/` should be pruned on a rolling basis (e.g. keep last N snapshots)
  once a `backups/README.md` manifest exists and it's clear what can be safely discarded.

## Non-goals for now

- No rewrite of `gizmo.rb` or `overlay.rb` is planned. Both are large but functioning; the audit
  found no correctness defect in the core move/rotate/scale interaction logic itself, only in a
  handful of isolated debug/error-handling lines (see `AUDIT_REPORT.md` M2, M3).
- No changes to the public-facing feature set (`Features.md`, `Manual.md`) are implied by this
  roadmap — it is about process and repo hygiene, not new functionality.
