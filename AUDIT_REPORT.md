# ZB Smart Gizmo — Code & Repository Audit Report

Date: 2026-07-07 (second pass added 2026-07-07)
Scope: full project folder (`zb_smart_gizmo/` source, `Release/`, `backups/`, root docs and assets).
This is an audit only for the findings below; fixes for confirmed items were applied afterward on
branch `cleanup/audit-code-cleanup` (see `CLEANUP_PLAN.md` completion log for commit hashes). All
findings were confirmed by reading the files and/or grepping the codebase — nothing here is guessed.

Legend: **High** = release/security/correctness risk. **Medium** = real maintenance or trust risk,
not currently breaking normal use. **Low** = cosmetic/noise, safe to defer.

---

## High severity

### H1. `EW.lic` is an unrelated third-party license file shipped to every customer
- **Where:** `EW.lic` (project root), and byte-identical copies (confirmed same MD5 hash) in
  `Release/ZB_Smart_Gizmo_RBZ/zb_smart_gizmo/EW.lic`, `Release/ZB_Smart_Gizmo_RBZ_Minimal/.../EW.lic`,
  `Release/ZB_Smart_Gizmo_RBZ_LegacyID/.../EW.lic`, `Release/ZB_Smart_Gizmo_RBZ_LegacyID_Minimal/.../EW.lic`,
  and `backups/2026-05-06_release-ready-checkpoint/EW.lic`.
- **What it is:** its content is a license grant/signature block (`LICENSE trmbldg ... customer=ZBELLBOUND ...
  sig="60P0451..."`) for some third-party build/licensing tool — not SketchUp, not this extension.
- **Confirmed:** `grep -r "EW.lic\|\.lic"` across the entire project returns **zero** references from any
  `.rb` file. The extension never reads this file at runtime (verified against `loader.rb`, `gizmo.rb`,
  `overlay.rb`, `observer.rb`, `utils.rb`, `native_backend.rb`).
- **Why it matters:** an unused, private third-party license/signature file is being bundled into every
  shipped `.rbz` and copied into every backup. If this repo is pushed to the public GitHub remote as-is
  (there is no `.gitignore`, see L-of-High below), this file and its signature become public.
- **Recommended safe fix:** confirm with the tool vendor/build process whether this file is required
  at build time only (not runtime). If not required for the shipped extension, remove it from
  `zb_smart_gizmo/` and from every `Release/*` folder before the next package build, and stop copying
  it in whatever script/manual step produces the release folders.

### H2. No `.git` and no `.gitignore` anywhere in the project
- **Where:** confirmed via `find . -name ".git*"` and `find . -iname "*.gitignore*"` — no matches.
  The task's environment also reports "Is a git repository: false" for this working copy.
- **Why it matters:** the working folder contains `backups/` (2.7 MB of duplicated source + a full
  duplicated `EW.lic`), `Release/` (4.2 MB of built `.rbz` binaries and 4 near-duplicate unpacked release
  trees), and large binary design assets (`Icon/icon.png` ~450 KB, duplicated again under
  `zb_smart_gizmo/Resources/icon.png`). None of this belongs in source control history. Without a
  `.gitignore`, a first `git add .` on this folder would commit all of it, bloating the repo permanently
  (build artifacts in git history cannot be easily un-bloated later without a history rewrite).
- **Recommended safe fix:** before connecting this folder to the GitHub repo, add a `.gitignore` that
  excludes `Release/*.rbz`, the unpacked `Release/*_RBZ*/` trees (these are build output, reproducible
  from `zb_smart_gizmo/`), `backups/` (working snapshots, not source-of-truth), and `EW.lic` (per H1).
  See `CLEANUP_PLAN.md` for the exact ruleset proposed.

### H3. `WAREHOUSE_SUBMISSION_CHECKLIST.md` is stale and misrepresents current project state
- **Where:** `WAREHOUSE_SUBMISSION_CHECKLIST.md`, dated 2026-04-24.
  - Lines 8–9, 20–21: documents the root package as `zb_smart_gismo.rb` / `zb_smart_gismo\` — the
    **old, misspelled** name. The current source root is `zb_smart_gizmo.rb` / `zb_smart_gizmo/`
    (confirmed: `zb_smart_gizmo.rb:12` sets `PLUGIN_ID = 'zb_smart_gizmo'`).
  - Lines 35–38: lists "Decide how to handle `TT_Lib2`" as an open item and states "the extension
    currently requires `TT_Lib2` in `zb_smart_gismo\loader.rb`." **Confirmed false for current source**:
    `grep -r "TT_Lib" zb_smart_gizmo/` returns zero matches. The current `zb_smart_gizmo/utils.rb`
    vendors its own minimal `TT` module (`Length`, `Locale`, `SketchUp`, `Point3d`, `Geom3d`) with no
    external dependency.
  - Line 26: "Create the final `.rbz` archive" is listed as an open checkbox, but `Release/` already
    contains 4 built variants and 2 `.rbz` archives dated 2026-06-18 — nearly two months after this
    checklist's date.
  - Line 3 hardcodes the author's local OneDrive path:
    `C:\Users\Peter Hauge\OneDrive - Compass Fairs\Documents\Playground\ZB_Smart_Gizmo`.
- **Why it matters:** if this checklist is ever used as a live release gate again, it will send a
  maintainer to re-litigate an already-resolved dependency question and to look for a nonexistent
  `zb_smart_gismo.rb` root file. It's currently a historical snapshot masquerading as an active checklist.
- **Recommended safe fix:** either update the checklist in place to reflect current file names and
  the resolved `TT_Lib2` question, or rename/move it to something like `docs/archive/2026-04-24-warehouse-checklist.md`
  and write a short current one. Do not delete outright without the user's sign-off — it may have
  historical value.

### H4. `Release/zb_smart_gismo.rbz` is the newest build in the tree and uses a different extension ID, but its purpose isn't documented anywhere
- **Where:** `Release/zb_smart_gismo.rbz` (built 2026-06-18 07:07:00) vs. `Release/ZB_Smart_Gizmo.rbz`
  (built 2026-06-18 05:54:00) — the "gismo" file is the more recent of the two loose `.rbz` files sitting
  directly in `Release/`.
- **Confirmed via unzip:** `Release/zb_smart_gismo.rbz` contains `zb_smart_gismo.rb` with
  `PLUGIN_ID = 'zb_smart_gismo'` and `SketchupExtension.new(PLUGIN_NAME, 'zb_smart_gismo/loader')`
  (registers under a **different** extension id/path than the primary `zb_smart_gizmo` build). This
  matches the intent of the separately-organized `Release/ZB_Smart_Gizmo_RBZ_LegacyID/` folder (kept for
  users who installed under the old "gismo" id, so they get an update rather than a duplicate install) —
  but this loose file sits unlabeled at the top level of `Release/`, not inside a folder that says
  "LegacyID", and it is the newest-timestamped file in the whole `Release/` directory.
- **Why it matters:** if the intent is "ship the LegacyID build to existing gismo-named installs and the
  normal build to everyone else," that's a reasonable strategy, but nothing documents it. A future
  maintainer (or Peter in six months) could easily upload the wrong file to the Extension Warehouse
  listing by picking "the newest one," which is the legacy-ID build.
- **Recommended safe fix:** move `Release/zb_smart_gismo.rbz` into (or generate it from)
  `Release/ZB_Smart_Gizmo_RBZ_LegacyID/` and add a one-paragraph `Release/README.md` explaining which
  of the 6 artifacts in that folder is the one to upload where, and why the LegacyID variant exists.

---

## Medium severity

### M1. `zb_smart_gizmo/native_backend.rb` and the entire `native/` C++ backend are dead code
- **Where:** `zb_smart_gizmo/native_backend.rb` (147 lines, defines `ZBSmart::Gizmo::NativeScaleBackend`)
  plus `zb_smart_gizmo/native/build_macos.sh`, `native/build_windows_msys2.sh`, `native/README.md`,
  `native/src/scale_engine.cpp`, `native/src/ruby_bridge.cpp`.
- **Confirmed:** `zb_smart_gizmo/loader.rb:44-47` requires exactly four files —
  `zb_smart_gizmo/utils`, `zb_smart_gizmo/observer`, `zb_smart_gizmo/overlay`, `zb_smart_gizmo/gizmo` —
  and never `zb_smart_gizmo/native_backend`. A full-project grep for `NativeScaleBackend`,
  `ScalePlusPlusNative`, and `compute_scale` shows the only matches are inside `native_backend.rb`
  itself and the C++ sources — no caller anywhere in `gizmo.rb`, `overlay.rb`, `observer.rb`, or
  `utils.rb`. There are also no compiled `mac/` or `win/` binary folders under `native/` for it to load
  even if it were required (`native_backend.rb:113-118` expects
  `native/mac/scaleplusplus_native.bundle` / `native/win/scaleplusplus_native.so`, neither of which exist
  in the tree).
- **Why it matters:** this is a genuinely unused, unreachable module and an entire orphaned C++ build
  pipeline shipping in every non-Minimal release (`Release/ZB_Smart_Gizmo_RBZ/` includes it;
  `Release/ZB_Smart_Gizmo_RBZ_Minimal/` correctly excludes it, confirming someone already noticed this
  distinction when making the "Minimal" variant but didn't remove it from the main one). It adds
  ~4 KB of Ruby plus a C++ source tree to every full release for a feature path that can never execute.
- **Recommended safe fix:** this is a product decision, not just cleanup — either (a) wire
  `native_backend.rb` into `loader.rb` and `overlay.rb`'s smart-scale math if the C++ acceleration is
  still wanted, or (b) if the pure-Ruby `SmartScaleApplier` path in `overlay.rb` is now the permanent
  implementation, delete `native_backend.rb` and `native/` from the main source tree (they'd remain
  recoverable from `backups/` and git history). Do not delete silently — flag to the user for a decision
  since it changes what ships, even though it changes zero runtime behavior either way.

### M2. Rescue handler in `RotateGizmo#project_to_segment` will itself raise, masking the real error
- **Where:** `zb_smart_gizmo/gizmo.rb:1879-1913`.
  ```ruby
  1879  def project_to_segment(view, x, y, segment)
  ...
  1890    (0...segment.size - 1).each do |i|
  1891      line = segment[i, 2]
  ...
  1906    closest_point
  1907  rescue ArgumentError => e
  1908    p ray
  1909    p plane
  1910    p mouse_line
  1911    p line
  1912    raise
  1913  end
  ```
- **Confirmed:** `line` (line 1891) is first assigned **inside** the `.each do |i| ... end` block
  (lines 1890-1905) and is never declared in the enclosing method scope before that block. In Ruby,
  a variable first assigned inside a block is local to that block. The `rescue` clause at line 1907 is
  in the enclosing method's scope, not the block's, so `line` is out of scope there.
- **Why it matters:** if `project_to_segment` ever hits the `ArgumentError` this rescue is meant to
  catch and log, line 1911 (`p line`) will itself raise `NameError: undefined local variable or method
  'line'`, which replaces the original `ArgumentError` with a confusing, unrelated exception — and the
  four `p` calls dump raw `Geom::Point3d`/array data straight to the Ruby console in front of end users
  before that happens. This is exactly the kind of debug-leftover error handling the task asked to look for.
- **Recommended safe fix:** remove the four `p` debug lines entirely (or replace with a single
  `warn("[ZB Smart Gizmo] project_to_segment failed: #{e.message}")` matching the `warn_overlay_issue`
  pattern already used elsewhere in `observer.rb:145-152` and `overlay.rb:517-524`), and drop the
  reference to the out-of-scope `line` variable. This is a pure error-handling fix with no behavior
  change to the success path.

### M3. `Axis#inspect` calls an undefined method
- **Where:** `zb_smart_gizmo/gizmo.rb:888-891`, inside `class Axis` (class body runs from
  `gizmo.rb:804` to its matching `end`).
  ```ruby
  def inspect
    hex_id = TT.object_id_hex(self)
    "#<#{self.class.name}:#{hex_id} #{@direction}>"
  end
  ```
- **Confirmed:** the project's vendored `TT` module (`zb_smart_gizmo/utils.rb:1-105`) defines only
  `TT::Length`, `TT::Locale`, `TT::SketchUp`, `TT::Point3d`, and `TT::Geom3d`. No `object_id_hex` method
  exists anywhere in the project (`grep -rn "object_id_hex"` returns only this one call site, no
  definition).
- **Why it matters:** any code path that calls `.inspect` on an `Axis` instance (Ruby's default
  `p`/`pp`, IRB/console inspection, or certain exception-formatting paths that call `.inspect` on
  objects in a backtrace) will raise `NoMethodError: undefined method 'object_id_hex' for TT:Module`.
  Low likelihood of being hit in normal use (nothing in the shipped code currently calls `.inspect` on
  an `Axis`), but it's a live landmine for whoever next adds a debug `p axis` while working in this area.
- **Recommended safe fix:** either implement `TT.object_id_hex` in `utils.rb` (e.g.
  `format('0x%016x', object.object_id)`), or simplify `inspect` to drop the hex id and use the default
  Ruby inspect formatting. Either is a self-contained, zero-risk change since `inspect` isn't called by
  any other code path today.

### M4. Four parallel Release build variants with no README explaining which is authoritative
- **Where:** `Release/ZB_Smart_Gizmo_RBZ/`, `Release/ZB_Smart_Gizmo_RBZ_Minimal/`,
  `Release/ZB_Smart_Gizmo_RBZ_LegacyID/`, `Release/ZB_Smart_Gizmo_RBZ_LegacyID_Minimal/`, plus 2 loose
  `.rbz` files directly in `Release/`.
- **Confirmed:** `ZB_Smart_Gizmo_RBZ` and `ZB_Smart_Gizmo_RBZ_Minimal` are byte-identical to current
  source for all shared files; `_Minimal` variants additionally omit `native/`, `native_backend.rb`,
  `Features.md`, and `Manual.md`. The `LegacyID` variants use `zb_smart_gismo` naming (see H4). Nothing
  in `Release/` documents this 4-way split or which one is meant for Extension Warehouse submission
  vs. direct distribution.
- **Why it matters:** release-readiness risk — a future packaging step has no written source of truth
  for "which folder do I zip and upload."
- **Recommended safe fix:** add `Release/README.md` documenting the purpose of each variant (see H4 fix).

### M5. Launch/business docs describe a trial-and-licensing feature that doesn't exist in the code
- **Where:** `ZB_Smart_Gizmo_Launch_Checklist.md` and `ZB_Smart_Gizmo_Project_Launch_Plan.md` both
  describe a 14-day trial with Smart Scale locking after expiry.
- **Confirmed:** no licensing/trial-gating code exists anywhere in `zb_smart_gizmo/*.rb` — `grep`
  for `trial`, `license`, `expir` (stem) across `zb_smart_gizmo/` returns no matches in the `.rb` files.
- **Why it matters:** these docs are forward-looking business plans, which is fine, but if used to judge
  "are we ready to ship" they'd be misleading — they describe a gating mechanism that isn't built.
- **Recommended safe fix:** no code change needed. Add a one-line status note at the top of both docs
  (e.g. "Planning document — trial/licensing described here is not yet implemented in code") so nobody
  mistakes the plan for the current state.

### M6. `backups/` has no manifest describing what each snapshot is or why it was kept
- **Where:** `backups/zb_smart_gismo.rb`, `backups/2026-05-06_release-ready-checkpoint/`,
  `backups/Release/`.
- **Confirmed:** `backups/zb_smart_gismo.rb` and `backups/2026-05-06_release-ready-checkpoint/zb_smart_gismo.rb`
  both declare `PLUGIN_VERSION = '1.1.0'` vs. the current `1.1.1` in `zb_smart_gizmo.rb:14` — consistent
  with being older snapshots, but there is no `README`/manifest in `backups/` recording which snapshot
  maps to which milestone.
- **Why it matters:** low urgency, but as more backups accumulate without a manifest, they become
  undated, undifferentiated clutter that nobody can safely delete later because nobody remembers what's in them.
- **Recommended safe fix:** add a one-line `backups/README.md` noting what each dated folder represents,
  going forward. Do not restructure existing backups.

---

## Low severity

### L1. Stale "`@deprecated Unfinished`" tag on an actively-used class
- **Where:** `zb_smart_gizmo/gizmo.rb:1472-1474`.
  ```ruby
  # @deprecated Unfinished
  # @since 2.7.0
  class RotateGizmo
  ```
- **Confirmed:** `RotateGizmo` is instantiated and actively driven at `gizmo.rb:849`
  (`@rotate_gizmo = RotateGizmo.new(...)`) and implements the full rotate-ring drag, angle snapping, and
  arrow-key rotate feature described in `Manual.md`'s "Rotate" section — it is core, shipped
  functionality, not unfinished or deprecated.
- **Why it matters:** purely a misleading doc-comment; a future maintainer skimming the file could
  assume this class is safe to delete or ignore.
- **Recommended safe fix:** delete the stale `@deprecated Unfinished` line.

### L2. 92 leftover `@since 2.7.0` YARD tags don't correspond to this project's versioning
- **Where:** throughout `zb_smart_gizmo/gizmo.rb` (92 occurrences via grep count).
- **Why it matters:** the project's actual version is tracked as `PLUGIN_VERSION = '1.1.1'`
  (`zb_smart_gizmo.rb:14`); "2.7.0" doesn't match any version scheme used elsewhere in the project and
  looks like inherited boilerplate from the example/template this code originated from. Harmless, but
  noisy and potentially confusing if someone greps for "2.7.0" expecting it to mean something.
- **Recommended safe fix:** low priority; safe to strip in a dedicated pass, or leave alone — flagging
  for awareness rather than urging action.

### L3. Duplicate, unreferenced icon assets at the project root
- **Where:** `Icon/icon.png`, `Icon/icon.svg`, `Icon/icon.pdf` (project root).
- **Confirmed:** the extension's actual icon lookup (`zb_smart_gizmo.rb:474-487`,
  `command_icon_path`) only ever builds paths under `File.join(PATH, 'Resources', ...)`, i.e.
  `zb_smart_gizmo/Resources/icon.{png,svg,pdf}`. A grep for `Icon/` across `zb_smart_gizmo/` returns no
  matches — the root `Icon/` folder is not used by any code path.
- **Why it matters:** ~530 KB of duplicated binary assets with no reference; harmless but adds clutter
  and confusion about which icon is "the" icon.
- **Recommended safe fix:** confirm with the user whether `Icon/` is a design-source folder (kept
  intentionally outside the shipped `Resources/`) or a stale duplicate, and either document its purpose
  or remove it.

### L4. Three unreferenced design-concept SVGs at project root
- **Where:** `gizmo_known_style_options.svg`, `gizmo_style_concepts.svg`, `gizmo_style_concepts_v2.svg`
  (project root).
- **Confirmed:** none of these are referenced by any `.rb` file, and none are part of the shipped
  `zb_smart_gizmo/` folder or any `Release/*` artifact.
- **Why it matters:** harmless scratch/design files sitting in the project root rather than a `design/`
  subfolder; minor tidiness issue.
- **Recommended safe fix:** move to a `design/` folder, or leave as-is if actively used for ongoing
  style decisions — no functional risk either way.

### L5. Commented-out debug `puts` lines
- **Where:** `zb_smart_gizmo/gizmo.rb:217-220`, inside `Manipulator#onMouseMove`'s hotfix comment block
  (`# puts 'Out of state!'`, `# puts flags`, `# puts @active_axis.id`, `# puts '> Restore!'`).
- **Why it matters:** already inert (commented out), purely cosmetic noise.
- **Recommended safe fix:** remove next time this method is touched for another reason; not worth a
  standalone commit.

### L6. Redundant business-planning docs
- **Where:** `ZB_Smart_Gizmo_Launch_Checklist.md` and `ZB_Smart_Gizmo_Project_Launch_Plan.md`.
- **Why it matters:** heavy content overlap (same pricing tiers, same trial language, same positioning) —
  not a contradiction, just duplication across two documents.
- **Recommended safe fix:** optional consolidation; no urgency, no code impact.

---

---

## Second pass (2026-07-07): additional code-correctness findings

Found while independently re-reading `gizmo.rb` and `overlay.rb` in full, after the first pass's
doc/repo-hygiene fixes had already landed. All four items below have since been fixed on
`cleanup/audit-code-cleanup` — see `CLEANUP_PLAN.md`'s completion log for commit hashes.

### H5 (fixed). `ScaleGizmo#onLButtonUp` always returned `nil`, silently breaking gizmo state tracking
- **Where:** `zb_smart_gizmo/gizmo.rb:2139-2156` (pre-fix line numbers).
- **Confirmed:** the method's `if @interacting ... else ... end` correctly computed `true`/`false`,
  but an unconditional `@pt_mouse = nil` statement placed *after* the `if/else` was the method's
  actual last expression, so the method always returned `nil`.
- **Why it matters:** `Axis#onLButtonUp` (`gizmo.rb:994-1010`) depends on this return value —
  `elsif can_scale && @scale_gizmo.onLButtonUp(...)`. With the return always falsy, this branch
  never matched, so `Axis#onLButtonUp` fell through to its final `else` and returned `false` after
  every scale-handle drag. `Manipulator#onLButtonUp` only clears `@active_axis`/`@active_plane`
  when an axis's `onLButtonUp` returns `true`, so `@active_axis` was never cleared after a scale
  drag — leaving `Manipulator#active?` (and everything downstream that reads it:
  `GizmoOverlay#active_gizmo?`, `#gizmo_hovering?`, `#mouse_over?`) stuck reporting "interaction
  still active" until an unrelated move/rotate interaction happened to reset it.
- **Confirmed no other instance of this pattern**: checked every `onLButtonUp`/`onLButtonDown`/
  `onMouseMove` in both files (23 methods total) — `ScaleGizmo#onLButtonUp` was the only one with a
  trailing statement after its `if/else`.
- **Fix applied:** capture the `if/else` result in a local variable, reset `@pt_mouse` after
  (unchanged relative to `clicked?`, which still reads `@pt_mouse` before it's cleared), then
  return the captured result explicitly.

### L7 (fixed). Second stale `@deprecated Unfinished` tag, on `ScaleGizmo`
- **Where:** `zb_smart_gizmo/gizmo.rb:2018` (pre-fix). Same issue as L1, but on a different class —
  the first pass only caught `RotateGizmo`'s copy of this tag.
- **Confirmed:** `ScaleGizmo` is actively instantiated (`gizmo.rb:870`) and gated by real
  `can_scale` logic in `Axis#onLButtonDown`/`onMouseMove` — not unfinished or deprecated.
- **Fix applied:** removed the stale tag line.

### M7 (fixed). Whole dead "session-based" Smart Scale application path (~220 lines)
- **Where:** `zb_smart_gizmo/overlay.rb` — `build_smart_scale_session`, `ensure_smart_scale_session`,
  `smart_scale_session_matches?`, `smart_scale_reedit_session`, `smart_scale_session_active?`,
  `apply_smart_scale_factor`, `apply_smart_scale_live`, `apply_smart_scale_exact`, plus two helpers
  used only by this cluster: `collect_root_raw_vertex_entries`, `collect_direct_smart_scale_instances`.
- **Confirmed:** project-wide grep found no caller for any of these outside the cluster itself. The
  `@smart_scale_session` ivar they wrote was read only by `smart_scale_session_active?`, itself
  uncalled. This was an older, single-ratio implementation of Smart Scale apply, superseded by the
  per-gesture-state path actually wired into `bind_gizmo_callbacks`
  (`SmartScaleGestureState`/`SmartScaleApplier.apply!`/`ensure_smart_scale_gesture(_states)`), which
  is untouched and remains the live implementation.
- **Fix applied:** removed all 10 methods. `reset_smart_scale_session` was deliberately left in
  place (still called from the live gesture flow) since it now just resets an ivar nothing reads —
  harmless bookkeeping, not a bug, and removing its 5 call sites in hot interaction code wasn't
  worth the added risk for a purely cosmetic gain.

### L8 (fixed). Unused `smart_scale_child_instances` wrapper
- **Where:** `zb_smart_gizmo/overlay.rb:1628-1630` (pre-fix). A thin wrapper around
  `child_instances_for_entities(smart_scale_entities(entity))` with no callers anywhere.
  `child_instances_for_entities` itself remains in active use elsewhere.
- **Fix applied:** removed.

---

## Explicitly checked and found OK (no finding)

- `Features.md` vs `Manual.md`: cross-checked Smart Scale description, rotate arrow-key defaults, and
  preference lists — consistent with each other and with the actual `open_preferences` implementation
  in `zb_smart_gizmo.rb:75-136`.
- `ScaleGizmo` (`gizmo.rb:2028-2446`): initially suspected dead code by a first pass, but confirmed
  **actively instantiated and used** at `gizmo.rb:870` (`@scale_gizmo = ScaleGizmo.new(...)`) and gated
  by `can_scale` logic in `Axis#onLButtonDown`/`onMouseMove` (`gizmo.rb:974-1053`). Not a finding.
- `rescue StandardError` blocks in `observer.rb:80-83, 97-100` and `overlay.rb:1484-1487, ...`:
  all route through `warn_overlay_issue`, which logs class/message/backtrace via `warn` rather than
  silently swallowing. This is a reasonable, consistent pattern — not flagged as a gap.
- Extension registration / namespace safety: `zb_smart_gizmo.rb:7-9` wraps everything in
  `module ZBSmart; module Gizmo; ...; end; end`, `file_loaded?`/`file_loaded` guards are present at both
  the top-level loader (`zb_smart_gizmo.rb:24,37`) and the menu/toolbar registration
  (`zb_smart_gizmo.rb:510,522`), preventing duplicate menu items or duplicate observer attachment on
  re-load. No namespace pollution found (no top-level constants/methods defined outside `ZBSmart::Gizmo`).
