# ZB Smart Gizmo — Cleanup Plan

This plan turns the confirmed findings in `AUDIT_REPORT.md` into a safe, ordered set of changes.
**Nothing in this plan has been applied yet.** Each item is scoped to be its own small,
reviewable commit, in dependency order (repo hygiene first, then code-level fixes, then
doc/asset tidying). No behavior changes are proposed anywhere in this plan — every fix is either
a repo-hygiene change, a dead-code/doc-comment correction, or an error-handling correction on a
path that currently has no correct behavior to preserve (it currently raises the wrong exception).

Two items (marked **[DECISION NEEDED]**) require the user to choose a direction before any file
is touched, because they affect what ships, not just cleanliness.

---

## Phase 0 — Decisions required before touching anything

- [ ] **[DECISION NEEDED] — H1 / EW.lic**: confirm whether `EW.lic` is required by any build/signing
  tool outside of what's visible in this repo. If not required, approve removing it from
  `zb_smart_gizmo/`, all `Release/*` folders, and future release builds.
- [ ] **[DECISION NEEDED] — M1 / native backend**: decide whether the C++ `NativeScaleBackend` path
  should be (a) wired in properly, or (b) removed as dead code. This changes what ships in the
  non-Minimal release, so it needs sign-off either way.
- [ ] **[DECISION NEEDED] — H4 / `zb_smart_gismo.rbz`**: confirm the "LegacyID" build is intentional
  (kept for users who installed under the old extension id) and approve moving/labeling it so it's
  not mistaken for the primary build.

## Phase 1 — Repository hygiene (no code touched)

1. **Add `.gitignore`** covering, at minimum:
   - `Release/*.rbz`
   - `Release/*_RBZ*/` (unpacked release trees — reproducible from `zb_smart_gizmo/`)
   - `backups/`
   - `EW.lic` (pending Phase 0 decision; safe to ignore regardless of removal decision)
   - Editor/OS cruft (`.DS_Store`, `Thumbs.db`) as standard hygiene.
   This is additive only — it does not delete or move anything, just stops future `git add` from
   picking up build output and backups.
2. **Add `Release/README.md`** explaining the 4 release-folder variants and 2 loose `.rbz` files:
   what each is for, and which one is the current Extension Warehouse submission candidate.
   Depends on the Phase 0 / H4 decision.
3. **Add `backups/README.md`** with a one-line description per existing dated snapshot folder
   (what milestone it represents). Purely additive documentation, no restructuring of existing backups.

## Phase 2 — Stale documentation corrections

4. **Update or archive `WAREHOUSE_SUBMISSION_CHECKLIST.md`** (H3): correct the `zb_smart_gismo` →
   `zb_smart_gizmo` file references, remove/resolve the `TT_Lib2` open item (already resolved in
   code — no external `TT_Lib2` dependency exists), and either check off or remove the items that
   are already done (rbz creation exists). If the user wants to preserve the original as a historical
   record, move it to `docs/archive/` instead of editing in place, and write a small current-state
   checklist alongside it.
5. **Add a one-line "planning document" disclaimer** to the top of `ZB_Smart_Gizmo_Launch_Checklist.md`
   and `ZB_Smart_Gizmo_Project_Launch_Plan.md` (M5) noting that the trial/licensing mechanism they
   describe is not yet implemented in code. Text-only change, no restructuring.

## Phase 3 — Code-level fixes (behavior-preserving)

6. **Fix the broken rescue handler in `RotateGizmo#project_to_segment`** (M2,
   `zb_smart_gizmo/gizmo.rb:1907-1912`): remove the four `p` debug dumps and the out-of-scope
   `line` reference; replace with a single `warn(...)` call consistent with the
   `warn_overlay_issue` pattern already used in `observer.rb` and `overlay.rb`. This only changes
   behavior on a path that currently raises the *wrong* exception (`NameError` instead of the
   original `ArgumentError`) — after the fix it will correctly re-raise the original error, which
   is what the `raise` at the end of the block already signals was intended.
7. **Fix or remove the undefined `TT.object_id_hex` call** (M3, `zb_smart_gizmo/gizmo.rb:888-891`):
   either implement `TT.object_id_hex` in `utils.rb` (e.g. `format('0x%016x', object.object_id)`)
   or simplify `Axis#inspect` to not reference it. Zero-risk since nothing currently calls
   `.inspect` on an `Axis`.
8. **Remove the stale `@deprecated Unfinished` tag** on `RotateGizmo` (L1,
   `zb_smart_gizmo/gizmo.rb:1472`). Comment-only change.
9. **Remove the 4 commented-out `# puts` debug lines** in `Manipulator#onMouseMove` (L5,
   `zb_smart_gizmo/gizmo.rb:217-220`). Comment-only change.

## Phase 4 — Asset/file tidy-up (lowest priority, do last)

10. **Resolve duplicate `Icon/` folder** (L3): confirm with the user whether it's an intentional
    design-source folder or a stale duplicate of `zb_smart_gizmo/Resources/`; remove or document
    accordingly.
11. **Relocate the 3 loose design SVGs** (L4) into a `design/` subfolder, or leave in place if
    actively used — no functional impact either way.
12. **Optional: consolidate `ZB_Smart_Gizmo_Launch_Checklist.md` and
    `ZB_Smart_Gizmo_Project_Launch_Plan.md`** (L6) if the user wants to reduce duplication. Purely
    optional, no urgency.

---

## Suggested commit order

Each numbered item above should be its own commit, in the order listed (Phase 1 → 4), skipping any
item still blocked on a Phase 0 decision until that decision is made. Rationale for the ordering:

1. Repo hygiene first (`.gitignore`, README stubs) so nothing new gets accidentally committed while
   the rest of the cleanup is in progress.
2. Documentation corrections next, since they carry zero code risk and immediately stop misleading
   a future reader.
3. Code-level fixes third, each isolated to one file/method so they're trivially reviewable and
   revertible independently.
4. Asset/file tidy-up last, since it's the lowest-severity and most matter-of-taste category.

No item in this plan should be batched with another in the same commit — the point of the ordering
is that each commit is independently safe to review, merge, or roll back without touching the others.

---

## Completion log

Approved by the user on 2026-07-07. Each entry below records a cleanup task as it's completed,
with the commit hash that carries it (or "not tracked by git" where the file was already
`.gitignore`d and so produces no git diff).

- **H1 / EW.lic removed** — deleted from project root and from the 4 unpacked
  `Release/*/` source folders (`ZB_Smart_Gizmo_RBZ`, `ZB_Smart_Gizmo_RBZ_Minimal`,
  `ZB_Smart_Gizmo_RBZ_LegacyID`, `ZB_Smart_Gizmo_RBZ_LegacyID_Minimal`). Confirmed unused by any
  code before removal (see AUDIT_REPORT.md H1). `backups/` was left untouched, per Phase 1 rule
  not to restructure existing backups. `EW.lic` was already covered by `.gitignore`, so this
  deletion is not itself visible in a git diff — recorded here as the audit trail. **Not yet
  done:** the already-built `Release/ZB_Smart_Gizmo.rbz` binary (built 2026-06-18, before this
  cleanup) still contains the old `EW.lic` inside its zip and has not been rebuilt — it must be
  repackaged from the cleaned `zb_smart_gizmo/` source before the next distribution, since
  rebuilding/re-signing a release archive is a packaging action outside the scope of this
  cleanup pass.

- **M1 / native backend archived** — `zb_smart_gizmo/native_backend.rb` and
  `zb_smart_gizmo/native/` moved to `archive/native_backend/` (see the README added there for
  full rationale). Confirmed via grep before the move that `loader.rb` never required
  `native_backend`, and no other file in `zb_smart_gizmo/` referenced `NativeScaleBackend`,
  `ScalePlusPlusNative`, or the `native/` path — the code was unreachable before the move and
  remains unreachable after it. Nothing was deleted; the files are preserved at their new path
  for a future decision (see ROADMAP.md) on whether to finish or retire the native path. Future
  release packaging that zips `zb_smart_gizmo/` will no longer include this dead code.

- **H4 / stale `zb_smart_gismo.rbz` archived** — moved from `Release/zb_smart_gismo.rbz` to
  `archive/legacy_release/zb_smart_gismo.rbz`, per the user's explicit instruction not to use or
  distribute it. Added `Release/README.md` documenting the current 4 release variants and calling
  out this archival, and `archive/legacy_release/README.md` explaining why the file is quarantined.
  `.gitignore` updated to also exclude `archive/legacy_release/*.rbz` (same build-artifact
  treatment as the other release binaries, so the move doesn't newly commit a 545 KB binary).
  The `ZB_Smart_Gizmo_RBZ_LegacyID*` folders were left untouched — their disposition remains an
  open decision (see ROADMAP.md), separate from this specific stray file.

- **Phase 1.3 / `backups/README.md` added** — one-line-per-snapshot manifest describing what's in
  `backups/` today. Existing backup contents were not modified or restructured. `.gitignore`
  updated from `backups/` to `backups/*` + `!backups/README.md` so this one manifest file can be
  tracked in git while the actual backup contents stay untracked, per the original intent.

- **Phase 2.4 / `WAREHOUSE_SUBMISSION_CHECKLIST.md` corrected** — fixed the stale
  `zb_smart_gismo.rb`/`zb_smart_gismo\` references to the current `zb_smart_gizmo` naming, resolved
  the `TT_Lib2` open item (confirmed removed from source), updated release-package-status
  checkboxes to reflect that `.rbz` archives now exist, added a rebuild-before-submission note
  pointing at `Release/README.md`, and removed the hardcoded local workspace path from the header.
  A dated note at the top explains the correction and points to the original pre-rename version
  still preserved in `backups/`.

- **Phase 2.5 / planning-doc disclaimers added** — one-paragraph notes added to the top of
  `ZB_Smart_Gizmo_Launch_Checklist.md` and `ZB_Smart_Gizmo_Project_Launch_Plan.md` clarifying that
  the trial/licensing mechanism they describe (audit finding M5) has no corresponding
  implementation in the current codebase. Text-only; no restructuring of either document.

- **Phase 3.6 / broken rescue handler fixed** — `zb_smart_gizmo/gizmo.rb:1907-1912`
  (`RotateGizmo#project_to_segment`). Replaced 4 `p` debug dumps and a reference to `line` (a
  block-local variable out of scope in the rescue clause, which would have raised `NameError` and
  masked the original `ArgumentError`) with a single `warn(...)` call, then `raise` as before.
  Behavior change is confined to this already-broken error path: previously it would raise the
  wrong exception with no useful message; now it logs the real error and re-raises it correctly.
  The success path (no `ArgumentError`) is untouched. Not backported to the pre-existing
  `Release/*_RBZ*/` snapshots — those are documented in `Release/README.md` as needing a full
  rebuild from source before next distribution anyway.

- **Phase 3.7 / undefined `TT.object_id_hex` implemented** — added
  `zb_smart_gizmo/utils.rb:2-6` (`TT.object_id_hex(object)`, returning a zero-padded hex
  `object_id`), which `Axis#inspect` (`gizmo.rb:889`) already called but which never existed
  anywhere in the project. Confirmed via grep that `TT` is only ever called as `TT.method_name`
  (never `include`d/`extend`ed), so adding a `module_function` at the top of `TT` before the
  existing nested `Length`/`Locale`/etc. modules doesn't affect their independent
  `module_function` declarations. Zero risk: nothing in the shipped code currently calls
  `.inspect` on an `Axis`, so this only makes an already-dead call path work correctly instead of
  raising `NoMethodError` if it's ever hit.

- **Phase 3.8 / stale `@deprecated Unfinished` tag removed** — `gizmo.rb:1472`, on `RotateGizmo`.
  Confirmed the class is actively instantiated (`gizmo.rb:849`) and drives the shipped rotate-ring
  drag/snap/arrow-key behavior described in `Manual.md` — it is not deprecated or unfinished.
  Comment-only change.

- **Phase 3.9 / commented-out debug `puts` lines removed** — `gizmo.rb:217-220`, inside
  `Manipulator#onMouseMove`'s hotfix block. Lines were already inert (commented out); removed for
  noise reduction. No behavior change.

- **Phase 4.10 / duplicate `Icon/` folder archived** — moved root-level `Icon/icon.{png,svg,pdf}`
  to `archive/root_icon/` (L3). User had no preference on delete vs. archive; chose archive as the
  safer, reversible option consistent with how `native_backend` and the legacy `.rbz` were already
  handled in this cleanup. Confirmed no code referenced the root `Icon/` folder before moving it.

- **Phase 4.11 / design SVGs relocated** — moved `gizmo_known_style_options.svg`,
  `gizmo_style_concepts.svg`, `gizmo_style_concepts_v2.svg` from the project root into a new
  `design/` folder (L4). User had no preference; chose relocation (not deletion) since these may
  still be actively used for style decisions. Confirmed none were referenced by any code or
  release artifact before moving.

---

## Second pass (2026-07-07): additional code-correctness fixes

Done on branch `cleanup/audit-code-cleanup`, after the initial 14-commit cleanup above had already
been pushed. See `AUDIT_REPORT.md`'s "Second pass" section for full detail on each finding.

- **H5 (`b2243e4`)** — Fixed `ScaleGizmo#onLButtonUp` (`gizmo.rb`) always returning `nil` instead
  of `true`/`false`, which left `Manipulator#active?` stuck reporting an interaction as active
  after every scale-handle drag. Confirmed no other `onLButtonUp`/`onLButtonDown`/`onMouseMove`
  method (23 checked across both files) had the same trailing-statement pattern.
- **L7 (`ae9c521`)** — Removed a second stale `@deprecated Unfinished` tag, this time on
  `ScaleGizmo` (the first pass only caught `RotateGizmo`'s copy). Comment-only.
- **L8 (`a821770`)** — Removed the unused `smart_scale_child_instances` wrapper (`overlay.rb`),
  confirmed via grep to have no callers.
- **M7 (`88538df`)** — Removed an entire dead, superseded "session-based" Smart Scale application
  path (~220 lines across 10 methods in `overlay.rb`), confirmed via project-wide grep to have zero
  callers. The live gesture-state-based Smart Scale path
  (`SmartScaleGestureState`/`SmartScaleApplier.apply!`) was not touched.

`ruby -c` was run on every edited file after each commit in this pass; all passed.
