# ZB Smart Gizmo 1.2.1 — Extension Warehouse Submission Checklist

Date: 2026-08-18, finalized 2026-08-19
Companion to `WAREHOUSE_SUBMISSION_1.2.1.md`. New file for 1.2.1 — does not edit
`WAREHOUSE_SUBMISSION_CHECKLIST.md` (1.2.0-era, left unchanged as historical record).

## Source gates (see pre-build gate report for full detail)

- [x] `test/smart_scale_gizmo_test.rb` regression suite passes
- [x] `ruby -c` passes on all 6 shipped `.rb` files
- [x] RuboCop-SketchUp (`SketchupRequirements`/`SketchupDeprecations`/`SketchupBugs` = 0,
      `SketchupPerformance`/`SketchupSuggestions` reviewed) via the new `.rubocop.yml`
- [x] Version consistent: `PLUGIN_VERSION = '1.2.1'`, no stray `1.2.0` in shipped source
- [x] Technical ID / namespace / registration unchanged and stable (`PLUGIN_ID`, `OVERLAY_ID`,
      `SketchupExtension.new` loader path)
- [x] Console output: all `warn` sites gated behind `DEBUG_MODE = false`
- [x] `Sketchup.require`/`.rbe`-compatibility: no hardcoded `.rb`/`.rbe`/`.rbs` extensions, no
      `require_relative`, no bare `load`
- [x] Package-content hygiene: final RBZ contains exactly the 9 approved entries, no dev
      tooling, no test files, no `.git`
- [x] Independent Codex audit passed

## Package status

- [x] `Release/ZB_Smart_Gizmo_1.2.1_Warehouse_Final.rbz` built from commit `a9df908` (the working
      tree described in `WAREHOUSE_SUBMISSION_1.2.1.md`, since committed)
- [x] Final RBZ extracted to an isolated folder and re-verified: exactly the 9 approved entries,
      extracted contents byte-for-byte identical to the pre-commit Candidate build
- [x] SHA-256 recorded for the final package:
      `ad8267933bae0adfe4c4c690d5960880a577c2b8c49658b6c2477f3213b7e253`

## Remaining manual steps (need real SketchUp)

- [ ] Clean-install test: install into a profile with no prior version present
- [x] Ruby Console manual test: confirmed silent through install and normal use, against this
      exact final RBZ, per Peter
- [ ] Picker empty-space test: every tool/command, click on empty space, confirm no exception
- [x] Undo/Redo test: each primary action, then Undo/Redo via the Edit menu, confirmed one clean
      entry each, against this exact final RBZ, per Peter
- [x] Confirm the Smart Scale Z-axis fix against a real Dynamic Component (the original reported
      repro) — confirmed against this exact final RBZ, per Peter

**Package status: approved for Extension Warehouse submission preparation. Not yet submitted or
published.** Clean-install and picker empty-space testing remain outstanding (not covered by
Peter's manual-testing report for this release).

## Deferred / not part of this release

- [ ] Signing/encryption choice for the Warehouse upload flow
- [ ] Support URL / support-email for the Warehouse listing
- [ ] Listing screenshots and description (draft text is in `WAREHOUSE_SUBMISSION_1.2.1.md`)
- [ ] `cursor.pdf` — wire up or remove (currently: kept in source, excluded from package)
- [ ] Reconciling the 1.2.0-era tag/commit documentation drift (958e604 / 9cc9deb / 93c94df) — left
      as historical record, not corrected

## Reference

- SketchUp Help — Extension signing/encryption:
  <https://help.sketchup.com/en/extension-warehouse/extension-encryption-and-signing>
- SketchUp Help — Extension development best practices:
  <https://help.sketchup.com/sv/extension-warehouse/extension-development-best-practices>
- SketchUp Help — Extension Requirements:
  <https://ruby.sketchup.com/file.extension_requirements.html>
