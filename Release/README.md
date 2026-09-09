# Release folder

This README was added 2026-07-07 as part of the audit cleanup (see `../AUDIT_REPORT.md` H4/M4 and
`../CLEANUP_PLAN.md`) to document what's in here. Updated 2026-07-07 after the 1.2.0 release build,
then again after the folder was cleaned up post-release.

## Current contents

**Updated 2026-09-09** — a new-identity Extension Warehouse candidate has been created for
`ZB Smart Gizmo Pro`:

- **`ZB_Smart_Gizmo_Pro_1.5.3_Warehouse_Candidate.rbz`** (196,416 B) — new Extension Warehouse
  identity candidate. Root loader `zb_smart_gizmo_pro.rb`, support folder `zb_smart_gizmo_pro/`,
  `PLUGIN_NAME = 'ZB Smart Gizmo Pro'`, `PLUGIN_ID = 'zb_smart_gizmo_pro'`, namespace
  `Zbellbound::SmartGizmoPro`, overlay ID `zbellbound.smart_gizmo_pro.overlay`. 9 entries. Passed
  `ruby -c`, the full Ruby regression suite, source RuboCop-SketchUp, and extracted-candidate
  RuboCop-SketchUp/FileStructure checks. Still requires independent read-only audit and real
  SketchUp manual testing before upload.
  `ead763862b04fd3436b9dd46d60186cc8062536b504275037bca2c72a140deb9`

**Updated 2026-09-07** — 1.5.3 is the current approved/published production package for the
original `ZB Smart Gizmo` identity. It adds the installed version number to the built-in About
dialog (`Extensions > ZB Smart Gizmo > Settings > About`): its first line now reads
`"ZB Smart Gizmo 1.5.3"` instead of just the name, built dynamically from
`PLUGIN_NAME`/`PLUGIN_VERSION` so future version bumps appear there automatically with no code
change. `PLUGIN_NAME` (`ZB Smart Gizmo`) and `PLUGIN_ID` (`zb_smart_gizmo`) are unchanged, and every
settings key continues to live under the same preferences section as every prior release -- this is
a documentation/visibility change only, with no functional change to Move, Rotate, Scale, Smart
Scale, or copy-array behavior.

- **`ZB_Smart_Gizmo_1.5.3_Warehouse_Final.rbz`** (194,467 B) — **the approved 1.5.3 release
  artifact.** Built from commit `a4e48c6` ("Bump version to 1.5.3, mark Release/README.md 1.5.3 as
  production candidate"), which merges `fix/about-version-display` (merge commit `6f92b14`) into
  `main`. 9 entries. Passed the full automated release gate (187 tests, 0 failures; `ruby -c`;
  both RuboCop-SketchUp gates; package-structure, namespace/registration, preference-namespace,
  console-output, and DEV/stale-label audits) and manual real-SketchUp installation and live-use
  testing of this exact package (empty Ruby Console; About dialog correctly and dynamically shows
  `ZB Smart Gizmo 1.5.3`; existing v1.5.2 preferences preserved). Tagged `v1.5.3` and published as
  a GitHub release, with the published asset independently re-downloaded and re-verified against
  this size/hash afterward. Not yet submitted to the Extension Warehouse (pending resolution of a
  portal authorization issue with Trimble support).
  `13b95ef3f826ab536df214a33ea47c4d6008c252cb322205861227a11f1ba1a9`
- **`README.md`** — this file.

The previous **1.5.2** release (`ZB_Smart_Gizmo_1.5.2_Warehouse_Final.rbz`,
`65ce753275b8145b06da395c5b9a75d8189de9c11986e3a9319df099cb4f0332`) has been removed from this
folder now that 1.5.3 is approved. It is not lost: 1.5.2 stays tagged `v1.5.2` and published as its
own GitHub release (untouched by this cleanup) if that exact package is ever needed again.

The **1.5.1** release (`ZB_Smart_Gizmo_1.5.1_Warehouse_Final.rbz`,
`0b214135de25f8a4a85bf8cb3cd3e0a0d89cb6adfc1b601e85270e34f95e2fbe`) was removed from this folder
the same way when 1.5.2 was approved, and stays tagged `v1.5.1` and published as its own GitHub
release.

The **1.5.0** release (`ZB_Smart_Gizmo_1.5.0_Warehouse_Final.rbz`,
`06e4b473a17202ada57b2fc2657e0441ae41a44b37829a3baa2e62950e6d3e2a`) was removed from this folder
the same way when 1.5.1 was approved, and stays tagged `v1.5.0` and published as its own GitHub
release.

The **1.3.0** release (`ZB_Smart_Gizmo_1.3.0_Warehouse_Final.rbz`,
`f2f2c5bcb0a203e8270de4a9988334da5d8c632f953f3f9a8cbd29042e99ae21`) and the local-only
1.3.0-based Ctrl-drag-array development/test build were removed from this folder in the same way
when 1.4.0 was approved. It, too, stays tagged `v1.3.0` and published as its own GitHub release.

The removed 1.2.0-era, 1.2.1-candidate, and 1.2.1 `.rbz` files (none ever tracked in git, none ever
submitted or published to Extension Warehouse) are still described, by filename and former
SHA-256, in the historical narrative docs that reference them
(`../WAREHOUSE_REJECTION_FIX_PLAN.md`, `../WAREHOUSE_ERROR_ANALYSIS.md`,
`../WAREHOUSE_SUPPORT_REQUEST.md`, `../WAREHOUSE_RESUBMISSION_REPORT.md`,
`../WAREHOUSE_SUBMISSION_1.2.1.md`, `../WAREHOUSE_SUBMISSION_CHECKLIST_1.2.1.md`) — those records
are unaffected by this cleanup and remain the source of truth for that history.

See "Cleanup" below for what used to be here (pre-1.2.0) and why it's gone — that section is
historical and unrelated to the current files listed above.

## Cleanup (2026-07-07, post-1.2.0)

This folder previously held a 4-variant pre-cleanup packaging split (a `1.1.1` build, its unpacked
source tree, a trimmed "Minimal" variant, and two "LegacyID" variants registering under the old
`zb_smart_gismo` id) plus a stray legacy `.rbz`. All of that predated this project's audit/cleanup
effort and was superseded once `ZB_Smart_Gizmo_1.2.0.rbz` was built from the cleaned source. It was
removed to keep this folder to just the current official package plus this README:

- `ZB_Smart_Gizmo.rbz` (the superseded `1.1.1` build) — deleted.
- `ZB_Smart_Gizmo_RBZ/`, `ZB_Smart_Gizmo_RBZ_Minimal/` (unpacked pre-cleanup source trees) —
  deleted.
- `ZB_Smart_Gizmo_RBZ_LegacyID/`, `ZB_Smart_Gizmo_RBZ_LegacyID_Minimal/` (unpacked `gismo`-id
  builds) — deleted.

None of the above were tracked in git (all were covered by `.gitignore`'s `Release/*.rbz` and
`Release/*_RBZ*/` rules) and none were referenced by any code in the project — confirmed via
project-wide grep before deletion. The already-archived stray `zb_smart_gismo.rbz` (see "Archived —
do not use" below) is unaffected by this cleanup; it was moved out of this folder earlier and was
never a candidate for deletion here.

**Open decision carried forward:** whether to keep maintaining a "LegacyID" (`zb_smart_gismo`)
dual-extension-id release strategy for users who installed under the old name is still unresolved
— see `../ROADMAP.md`. If revived, that build should be regenerated fresh from current source
rather than resurrecting the deleted pre-cleanup folders.

## Archived — do not use

A stray `zb_smart_gismo.rbz` file previously sat loose in this folder. It was the
newest-timestamped build in the whole tree at the time, making it easy to mistake for the primary
release, and had no labeling explaining its "gismo" id. Per the user's explicit instruction, it was
moved to `../archive/legacy_release/` and must not be used or distributed. See that folder's README
for details.

## Extension Warehouse submission

Signing, encryption choice, listing assets, and the support-URL/privacy-field decisions are still
separately pending — see `../WAREHOUSE_SUBMISSION_CHECKLIST.md` and
`../WAREHOUSE_SUBMISSION_1.2.0.md`.
