# ZB Smart Gizmo 1.2.0 — Resubmission Report

Date: 2026-08-11
Source: `main` @ `88de8fa` (includes both targeted rescue-logging fixes)
Package: `Release/ZB_Smart_Gizmo_1.2.0_Warehouse_Resubmission.rbz`

This document covers the targeted fixes made in response to the second Extension Warehouse
rejection, the newly built resubmission package, and its full verification. **Nothing has been
submitted to Extension Warehouse and no GitHub Release was created — this is preparation only.**

---

## Reviewer rejection points (this round)

1. **Version mismatch** — Warehouse reported the submitted code registers `1.1.0`, while the listing
   said `1.2.0`. Reviewer cited `zb_smart_gizmo.rb` — `PLUGIN_VERSION` / `extension.version`.
2. **Ruby Console errors on install:**
   ```
   Plugins/zb_smart_gizmo.rb:31 in register_extension
   Plugins/zb_smart_gizmo.rb:31 in module:Gizmo
   Plugins/zb_smart_gizmo.rb:8 in module:ZBSmart
   Plugins/zb_smart_gizmo.rb:7 in <top (required)>
   ```
3. **Reviewer note:** license checks should be inside core business methods rather than a separate
   `licensed?` method that could be overridden.
4. **Reviewer note:** avoid silent rescue blocks that swallow errors.
5. **Reviewer note:** prefer vector toolbar icons — SVG on Windows, PDF on Mac — rather than PNG.

Full diagnosis for all five points: `WAREHOUSE_REJECTION_FIX_PLAN.md`. Summary of what that
diagnosis found, before describing what was actually changed:

- **Points 1, 2, and 5** were not reproducible against current source or any current package —
  current code and all current `Release/*.rbz` files already read `1.2.0` everywhere checked, the
  register_extension code path contains nothing that can raise on its own, and the icon logic
  already prefers SVG on Windows / PDF on Mac. These three findings were independently consistent
  with one explanation: the review evaluated an older or cached artifact, not the actual 1.2.0
  package. That is a hypothesis about the Warehouse review process, not something a code change can
  fix — see `WAREHOUSE_SUPPORT_REQUEST.md`, still open, for the question sent to Trimble about this.
- **Point 3** (licensing) does not apply — no licensing/trial code exists anywhere in this codebase
  (confirmed via grep across all 6 shipped Ruby files), so there is nothing to restructure. No
  licensing code was added.
- **Point 4** (silent rescues) was the one point with a real, fixable target: 2 of the 19 `rescue`
  clauses in the codebase logged weakly or not at all. Those are the fixes made this round.

---

## Fixes made

### 1. `overlay.rb:390` — commit [`88d8382`]

`GizmoOverlay#onMouseMove`'s rescue block dumped the raw exception via bare `p e` (no context, no
backtrace) instead of using the project's established logging pattern.

```diff
     rescue StandardError => e
-      p e
+      warn_overlay_issue('handle mouse move', e)
       @model.tools.pop_tool if active_itself?
     end
```

`warn_overlay_issue` (already defined in this same class) logs the action, exception class, message,
and full backtrace via `warn`. No control-flow change — the tool is still popped off the stack under
the same condition as before.

### 2. `overlay.rb:1625` — commit [`88de8fa`]

`GizmoOverlay#dynamic_component_observer` rescued `StandardError` and returned `nil` with **zero**
logging — the one fully silent rescue in the codebase. The sibling method directly below it,
`dynamic_component_entity?`, already logs the equivalent failure for the same optional Dynamic
Components integration.

```diff
       $dc_observers.get_latest_class
-    rescue StandardError
+    rescue StandardError => e
+      warn_overlay_issue('read dynamic component observer', e)
       nil
     end
```

Return value (`nil` on failure) is unchanged — callers are unaffected. Only the logging behavior
changed.

**Verification for both fixes:** `ruby -c zb_smart_gizmo/overlay.rb` → `Syntax OK` after each commit,
diffs reviewed to confirm each change was isolated to its target line(s), no other rescue clauses or
control flow touched.

No licensing code was added (point 3 does not apply). No change was made to version constants, icon
logic, or the registration code path — none of those had a confirmed defect to fix.

---

## Resubmission package build

Built fresh from `main` @ `88de8fa` (both fixes included), same strict 10-file structure used for
the prior Warehouse-targeted package — no docs, no `EW.lic`, no `archive/`, no old release folders,
current `zb_smart_gizmo` technical ID (not the legacy `zb_smart_gismo` ID).

### Exact packaged-version verification (from the rebuilt, re-extracted RBZ)

**`PLUGIN_VERSION` / `extension.version` source lines, read from inside the extracted package:**
```
zb_smart_gizmo.rb:14:    PLUGIN_VERSION   = '1.2.0'.freeze
zb_smart_gizmo.rb:26:      extension.version     = PLUGIN_VERSION
```

**Grep of the entire extracted package for all three version strings:**
| Search | Result |
|---|---|
| `1.1.0` | Zero matches |
| `1.1.1` | Zero matches |
| `1.2.0` | One match — `zb_smart_gizmo.rb:14` (the `PLUGIN_VERSION` declaration) |

**Exact file list (10 files):**
```
zb_smart_gizmo.rb
zb_smart_gizmo/gizmo.rb
zb_smart_gizmo/loader.rb
zb_smart_gizmo/observer.rb
zb_smart_gizmo/overlay.rb
zb_smart_gizmo/utils.rb
zb_smart_gizmo/Resources/cursor.pdf
zb_smart_gizmo/Resources/icon.pdf
zb_smart_gizmo/Resources/icon.png
zb_smart_gizmo/Resources/icon.svg
```
Forward-slash zip paths confirmed. No `.md` files, no `EW.lic`, no `gismo` string anywhere in the
package.

**`ruby -c` on all 6 extracted Ruby files:** all report `Syntax OK`.

**Fixes confirmed present in the extracted package:**
```
zb_smart_gizmo/overlay.rb:391:  warn_overlay_issue('handle mouse move', e)
zb_smart_gizmo/overlay.rb:1626: warn_overlay_issue('read dynamic component observer', e)
```

**Identity confirmed (single registration, current technical ID, not legacy):**
```
zb_smart_gizmo.rb:12: PLUGIN_ID        = 'zb_smart_gizmo'.freeze
zb_smart_gizmo.rb:25: extension = SketchupExtension.new(PLUGIN_NAME, 'zb_smart_gizmo/loader')
zb_smart_gizmo.rb:31: Sketchup.register_extension(extension, true)
```
Exactly one `SketchupExtension.new` and one `Sketchup.register_extension` call — no duplicates.

**Byte-identical check:** every packaged `.rb` file diffed against its `main`-branch source
counterpart — all clean (no differences).

### Exact SHA-256

```
7578fd522f87b4cd7c57c2460adc1547e023873523606f44f9045f6b9a39ef58
```

### Package filename

```
Release/ZB_Smart_Gizmo_1.2.0_Warehouse_Resubmission.rbz
```

Not tracked by git — matched by `.gitignore`'s `Release/*.rbz` rule (confirmed via
`git check-ignore -v`), same as every other `.rbz` in this project.

---

## Not done, per instruction

- Nothing was submitted to Extension Warehouse automatically.
- No GitHub Release was created.
- The legacy-ID (`zb_smart_gismo`) package was not used or rebuilt for this resubmission.
- No licensing code was added.
- `WAREHOUSE_SUPPORT_REQUEST.md`'s open question to Trimble about what "Unrelated branches" and the
  stale-version report actually mean for this account/listing is still unanswered and still relevant
  — this resubmission package doesn't resolve that question, since nothing in the diagnosis pointed
  to a fixable code cause for it.
