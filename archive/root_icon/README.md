# Archived: duplicate root-level icon assets

Moved out of the project root's `Icon/` folder on 2026-07-07 as part of the audit cleanup (see
`../../AUDIT_REPORT.md` L3 and `../../CLEANUP_PLAN.md`).

`icon.png`, `icon.svg`, and `icon.pdf` here duplicate
`zb_smart_gizmo/Resources/icon.{png,svg,pdf}`, which is what the extension actually loads
(`zb_smart_gizmo.rb:474-487`, `command_icon_path`, only ever builds paths under
`.../Resources/...`). No code referenced the root-level `Icon/` folder. Kept here rather than
deleted in case they're wanted as a design-source reference; safe to delete outright later if not.
