# ZB Smart Gizmo Warehouse Submission Checklist

Date: 2026-04-24 (corrected 2026-07-07 — see note below)
Workspace: project root (path omitted; see project README/VCS remote for location)

> **Note (2026-07-07):** this checklist was written before the project was renamed from
> `zb_smart_gismo` to `zb_smart_gizmo`, and before the `TT_Lib2` dependency below was removed. The
> file/folder names and dependency section have been corrected in place to match current source;
> the original, uncorrected checkboxes are preserved in `backups/` snapshots predating the rename.
> See `AUDIT_REPORT.md` (H3) and `CLEANUP_PLAN.md` for the audit that identified the drift.

## Current package status

- [x] Root loader file exists: `zb_smart_gizmo.rb`
- [x] Matching support folder exists: `zb_smart_gizmo`
- [x] Code is namespaced
- [x] Extension metadata is registered through `SketchupExtension`
- [x] Non-root Ruby files are loaded with `Sketchup.require`
- [x] Built-in manual/help is available from the extension menu
- [ ] Ruby syntax check passes for all extension `.rb` files — not re-verified as part of this
      cleanup pass; re-check before next submission.

## Release package status

- [x] Clean release package folder created under `Release\ZB_Smart_Gizmo_RBZ`
- [x] Release package contains only:
  - `zb_smart_gizmo.rb`
  - `zb_smart_gizmo\`
- [x] Development backups and session notes are kept outside the release package
- [x] `.rbz` archives have since been created (see `Release\README.md` for the current 4 variants
      and their status)

## Remaining manual submission steps

- [ ] Upload the `.rbz` to the SketchUp signing / Extension Warehouse flow
- [ ] Choose whether to encrypt non-root Ruby files during signing
- [ ] Add listing screenshots
- [ ] Add listing description / changelog text
- [ ] Add support URL or support email in the Extension Warehouse profile/listing
- [ ] Rebuild `.rbz` archives from the current cleaned source before submission (see
      `Release\README.md` — existing archives predate the 2026-07-07 cleanup)

## Dependency review

- [x] `TT_Lib2` dependency resolved — the extension no longer requires the external `TT_Lib2`
      library. `zb_smart_gizmo\utils.rb` vendors a minimal internal `TT` module
      (`Length`, `Locale`, `SketchUp`, `Point3d`, `Geom3d`) with no external dependency. Confirmed
      via `grep -r "TT_Lib" zb_smart_gizmo/` returning no matches.

## Warehouse notes

- SketchUp Help: Extension signing/encryption
  - <https://help.sketchup.com/en/extension-warehouse/extension-encryption-and-signing>
- SketchUp Help: Extension development best practices
  - <https://help.sketchup.com/sv/extension-warehouse/extension-development-best-practices>

## Suggested final pre-submit smoke test

Test these in SketchUp before packaging:

- [ ] Toggle gizmo on/off
- [ ] Move arrows and plane handles
- [ ] Rotate ring drag and rotate dialog input
- [ ] Scale dialog exact input
- [ ] Smart Scale on a simple grouped object
- [ ] Smart Scale on a nested grouped table/frame
- [ ] Native Move handoff with `M`
- [ ] Right-click context menu only on gizmo
- [ ] Manual opens from `Extensions > ZB Smart Gizmo > Settings > Manual`
