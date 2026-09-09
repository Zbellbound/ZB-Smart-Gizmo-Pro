# ZB Smart Gizmo 1.2.1 — Extension Warehouse Submission Package

Date: 2026-08-18, finalized 2026-08-19
Source: git `main`, commit `a9df90840b338aec1cb96ab2c4d71309f82c748e` ("Prepare 1.2.1 release: dev
RuboCop-SketchUp gate, version bump, icon fix"). The working-tree changes described below (in the
"Working-tree changes" section, kept as a historical record of this preparation pass) have since
been committed as that commit.
Final package: `Release/ZB_Smart_Gizmo_1.2.1_Warehouse_Final.rbz`
Final SHA-256: `ad8267933bae0adfe4c4c690d5960880a577c2b8c49658b6c2477f3213b7e253`

This is a new, version-specific record for 1.2.1. It does not edit or supersede
`WAREHOUSE_SUBMISSION_1.2.0.md`, which remains an unmodified historical record of the 1.2.0
submission preparation.

---

## What changed since 1.2.0

**Bug fix:** `GizmoOverlay#on_transform` (in `zb_smart_gizmo/overlay.rb`) called a method,
`smart_scale_log`, that was never defined anywhere in the codebase. Whenever Smart Scale was
enabled and a drag's stretch-profile computation failed or returned nothing usable (e.g. a
Dynamic Component built from curved/turned geometry with no straight edges or nested sub-parts —
common for legs, posts, and balusters), that missing method raised an uncaught `NoMethodError`,
aborting the drag handler before it could fall through to the normal scale transform. Symptom:
dragging the gizmo's Z handle appeared to do nothing on affected objects, while a direct
`instance.transform!` or another tool's scale worked fine. Fixed by defining `smart_scale_log`
(gated behind `DEBUG_MODE`, matching the existing `warn_overlay_issue` pattern) so the designed
fallback path actually runs. Covered by a new regression suite (`test/`, 14 cases, not shipped in
the package).

**Icon:** `Resources/icon.png` regenerated directly from `Resources/icon.svg` (the actual
transparent source of truth). The previous `icon.png` had no alpha channel (PNG color type 2,
flattened white background) — dormant in practice since `icon.svg`/`icon.pdf` are always preferred
by `command_icon_path` when present, but incorrect as a fallback asset. New file: 2394×2269,
RGBA, confirmed via rendered-pixel alpha-channel inspection (not just the file header) to be
genuinely transparent, same design (verified: red accent and black glyph both present and
correctly colored — an early PyMuPDF-rendered draft lost the red because the renderer doesn't
resolve `<defs><style>` CSS class selectors in the SVG; caught by visual inspection before use,
and worked around only in the *rendering input*, not in the shipped `icon.svg`, which is
byte-for-byte unchanged).

**Package hygiene:** `Resources/cursor.pdf` — confirmed unreferenced by any shipped `.rb` file —
is excluded from this package. It remains in source (`zb_smart_gizmo/Resources/cursor.pdf`,
git-tracked, unchanged) pending a documented decision on whether to wire it up or remove it; this
release makes no decision on that beyond not shipping it.

**Dev tooling:** a dev-only `.rubocop.yml` was added at the repo root (never shipped — excluded by
construction, see package contents below). No `.rubocop.yml` existed before this release; running
RuboCop-SketchUp without it previously produced misleading results (a false `FileStructure` error
and version-compatibility false positives against the wrong `TargetSketchUpVersion`).

---

## Package verification

### Structure

- **Root loader:** `zb_smart_gizmo.rb` present at the package root.
- **Matching support folder:** `zb_smart_gizmo/`, name matches the root loader's basename.
- **Package contents (9 files):**
  ```
  zb_smart_gizmo.rb
  zb_smart_gizmo/gizmo.rb
  zb_smart_gizmo/loader.rb
  zb_smart_gizmo/observer.rb
  zb_smart_gizmo/overlay.rb
  zb_smart_gizmo/utils.rb
  zb_smart_gizmo/Resources/icon.pdf
  zb_smart_gizmo/Resources/icon.png
  zb_smart_gizmo/Resources/icon.svg
  ```
  No `Features.md`/`Manual.md` (not part of this candidate's scope), no `cursor.pdf` (unreferenced,
  see above), no dev tooling, no `test/`, no `.git`.

### Version

- `PLUGIN_VERSION = '1.2.1'` in `zb_smart_gizmo.rb`, matches `extension.version` at registration
  (single source of truth — confirmed by grep, no other `1.2.0`/hardcoded version string remains
  anywhere in shipped source).

### Naming / registration

- `PLUGIN_ID = 'zb_smart_gizmo'`, root file `zb_smart_gizmo.rb`, support folder `zb_smart_gizmo/`
  — consistent, unchanged from 1.2.0.
- `SketchupExtension.new(PLUGIN_NAME, 'zb_smart_gizmo/loader')` — extensionless loader path,
  `PLUGIN_NAME` unchanged from every prior release.
- `OVERLAY_ID = 'zb_smart.gizmo.overlay'` — unchanged.

### Compatibility

- `MINIMUM_VERSION = 23` (SketchUp 2023), unchanged, with the existing runtime guard in
  `zb_smart_gizmo/loader.rb`.

### Gate results

See the pre-build gate report delivered alongside this document for the full RuboCop-SketchUp,
`ruby -c`, console-output, `Sketchup.require`/`.rbe`-compatibility, and package-hygiene results.
Summarized: no blockers found; full detail in that report, not duplicated here to avoid drift
between two copies of the same data.

---

## Final release status (2026-08-19)

The candidate described above was committed as `a9df908`, then rebuilt into the approved final
package. Per Peter:

- **Automated release gate:** passed (regression suite, `ruby -c`, RuboCop-SketchUp, package-content
  hygiene — all as summarized under "Gate results" above).
- **Independent Codex audit:** passed.
- **Manual real-SketchUp testing of this exact final RBZ**
  (`Release/ZB_Smart_Gizmo_1.2.1_Warehouse_Final.rbz`, SHA-256
  `ad8267933bae0adfe4c4c690d5960880a577c2b8c49658b6c2477f3213b7e253`): passed —
  - Smart Scale Dynamic Component Z-axis fix confirmed against a real Dynamic Component.
  - Undo/Redo confirmed clean for the tested actions.
  - Ruby Console remained empty throughout.

Package contents re-verified at 9 entries, matching the "Structure" section above exactly.

**Status: approved for Extension Warehouse submission preparation. Not yet submitted or
published.**

---

## Release notes — 1.2.1 (draft, for the Warehouse listing form)

```
1.2.1 is a bug-fix release.

Bug fixes:
- Fixed Smart Scale silently failing to resize certain structured objects (including Dynamic
  Components built from curved/turned geometry, such as legs, posts, and balusters) along the
  dragged axis when Smart Scale could not find a usable stretch profile. Affected objects now
  fall back correctly to a normal scale, matching the behavior of a direct transform.

No changes to saved preferences, file formats, or other existing workflows — fully backward
compatible with 1.2.0.
```

### Installation notes

```
1. Download ZB_Smart_Gizmo_1.2.1_Warehouse_Final.rbz (filename will change for the actual
   Warehouse-listed asset — this is the locally approved package prepared for submission).
2. In SketchUp, open Extensions > Extension Manager.
3. Click "Install Extension" and select the downloaded .rbz file.
4. Restart SketchUp if prompted.

Requires SketchUp 2023 or later.
```

---

## Working-tree changes (historical — committed as `a9df908`)

This section is kept as a record of what this preparation pass changed, relative to commit
`259c06b`. All of it was committed as `a9df908` ("Prepare 1.2.1 release: dev RuboCop-SketchUp gate,
version bump, icon fix"):

- `.rubocop.yml` — new, dev-only, not shipped.
- `zb_smart_gizmo.rb` — `PLUGIN_VERSION` bumped `'1.2.0'` → `'1.2.1'`.
- `zb_smart_gizmo/Resources/icon.png` — regenerated (see above).
- `WAREHOUSE_SUBMISSION_1.2.1.md` — this file, new.
- `WAREHOUSE_SUBMISSION_CHECKLIST_1.2.1.md` — new, see that file.
- `Release/README.md` — "Current contents" section updated to reflect the actual folder inventory;
  historical sections unchanged.

See "Final release status" above for what happened after this commit: the final package build,
gate/audit/manual-test results, and current approval status. This document still does not describe
a tagged or Warehouse-submitted release — only a locally approved package prepared for submission.

---

## Open items (not resolved by this candidate)

- Signing/encryption choice for the Warehouse upload flow — still undecided (carried over from
  1.2.0 prep).
- Support URL / support-email field for the Warehouse listing — still undecided.
- `cursor.pdf` — wire up or remove, decision still pending, explicitly out of scope for this
  release.
- The version/tag documentation drift identified across `Release/README.md` (958e604) /
  `WAREHOUSE_SUBMISSION_1.2.0.md` (9cc9deb) / the actual `v1.2.0` git tag (93c94df) is a 1.2.0-era
  historical discrepancy and is intentionally left uncorrected in those files — see the
  reconciliation report from this same preparation pass.
