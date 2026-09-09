# Extension Warehouse Rejection — Diagnosis and Fix Plan

Date: 2026-07-07
Scope: diagnosis only, per instruction. **No code has been modified. No RBZ has been rebuilt.**
Every claim below was checked fresh against current source and the actual current `Release/*.rbz`
files — prior verification passes were not assumed correct and were re-run from scratch.

---

## A. VERSION

### What's actually in current source

`zb_smart_gizmo.rb:14`:
```ruby
PLUGIN_VERSION   = '1.2.0'.freeze
```
`zb_smart_gizmo.rb:26`:
```ruby
extension.version     = PLUGIN_VERSION
```

Both confirmed by direct read of the file on `main`, just now.

### What's inside the actual RBZ files currently in `Release/`

Extracted and checked all three fresh:

| Package | Root file | `PLUGIN_VERSION` |
|---|---|---|
| `Release/ZB_Smart_Gizmo_1.2.0.rbz` | `zb_smart_gizmo.rb` | `'1.2.0'` |
| `Release/ZB_Smart_Gizmo_1.2.0_Warehouse.rbz` | `zb_smart_gizmo.rb` | `'1.2.0'` |
| `Release/ZB_Smart_Gizmo_1.2.0_Warehouse_LegacyID.rbz` | `zb_smart_gismo.rb` | `'1.2.0'` |

**All three read `1.2.0`. None contain `1.1.0`.**

### Project-wide search for `1.1.0`, `1.1.1`, `1.2.0`

- `1.2.0` — appears in current source and all three current `Release/*.rbz` files (expected).
- `1.1.1` — appears only in `archive/legacy_release/zb_smart_gismo.rbz` (the stray file explicitly
  marked "do not use or distribute" in an earlier pass) and in historical audit docs
  (`AUDIT_REPORT.md`) describing past state. Not in any file named `zb_smart_gizmo.rb`.
- `1.1.0` — **not found in any currently-existing file anywhere in this project.** The only place
  `1.1.0` is known to have existed was `backups/zb_smart_gismo.rb` and
  `backups/2026-05-06_release-ready-checkpoint/zb_smart_gismo.rb` — both already deleted in an
  earlier cleanup pass, and both used the **old `gismo` spelling**, not `zb_smart_gizmo.rb`.

### Conclusion: how the reviewer could have seen `1.1.0`

**No file matching the reviewer's exact citation — `zb_smart_gizmo.rb` (correct spelling) reporting
`1.1.0`— exists anywhere in this project, current or historical, that I can find.** The closest
historical match (`1.1.0`) was always under the misspelled `zb_smart_gismo.rb` filename, never
`zb_smart_gizmo.rb`.

This is not something a source-code fix can resolve, because there is nothing to fix in the source —
current code is unambiguously `1.2.0` everywhere it's checked, including inside the exact package
files sitting in `Release/` right now. The most plausible explanation is that **the reviewer's
tooling evaluated a different (older, or cached) upload than the 1.2.0 package actually intended for
this submission** — see the unifying hypothesis at the end of this document, which ties this finding
together with B and E below.

---

## B. REGISTER_EXTENSION ERROR

### The cited trace, checked against current source

```
Plugins/zb_smart_gizmo.rb:31 in register_extension
Plugins/zb_smart_gizmo.rb:31 in module:Gizmo
Plugins/zb_smart_gizmo.rb:8 in module:ZBSmart
Plugins/zb_smart_gizmo.rb:7 in <top (required)>
```

Current `zb_smart_gizmo.rb`:
```
 7: module ZBSmart
 8:   module Gizmo
...
31:      Sketchup.register_extension(extension, true)
```

**Lines 7, 8, and 31 match exactly.** The trace shape is fully consistent with our current file.

### What runs at registration time — confirmed exhaustively

`zb_smart_gizmo.rb` requires only two standard SketchUp bootstrap files at top level
(`extensions.rb`, `sketchup.rb`, lines 4–5). It does **not** require `loader.rb` or anything
downstream (`utils.rb`, `observer.rb`, `overlay.rb`, `gizmo.rb`) at this point — those are only
loaded lazily later, when SketchUp actually activates the extension via the path registered on the
`SketchupExtension` object (`'zb_smart_gizmo/loader'`, line 25). **Confirmed by reading the file: no
`require`/`Sketchup.require` for any of those files appears anywhere in `zb_smart_gizmo.rb`.**

This means: at the exact moment this trace was captured, the *only* code that had executed is lines
1–31 of `zb_smart_gizmo.rb` itself — 8 constant assignments, a `SketchupExtension.new` call, four
attribute assignments, and the `Sketchup.register_extension` call. There is no custom logic, no
loop, no I/O, no external dependency in that path — every one of `PLUGIN_NAME`, `PLUGIN_VERSION`,
`PLUGIN_COPYRIGHT`, `PLUGIN_CREATOR`, `PLUGIN_DESC` is a plain frozen string literal assigned
directly above where it's used, so none of the four `extension.xxx =` assignments can raise.

### Why this doesn't point to a defect in our code

This is the single most standard, widely-used SketchUp extension registration idiom — the same
`SketchupExtension.new` → set 4 attributes → `Sketchup.register_extension` pattern used by
effectively every SketchUp extension. It is guarded by `unless file_loaded?(__FILE__)` (line 24),
which is the standard, correct idiom for preventing double registration on a Ruby reload. Nothing
about this code has changed in its structure across recent versions (see the version cross-check
below).

### Cross-check with finding A

The old, deleted `backups/zb_smart_gismo.rb` (version `1.1.0`) had the **identical line layout** —
`PLUGIN_VERSION` at line 14, `extension.version` at line 26, `Sketchup.register_extension` at line
31 (confirmed from this project's own earlier audit records, since the file itself is no longer
present to re-check directly). That means **a line-31 citation is consistent with either the current
1.2.0 file or the old 1.1.0 file** — the file's structural layout has apparently been stable across
versions. Combined with finding A, this strengthens rather than weakens the theory that the reviewer
evaluated an older artifact.

### Actual likely cause

I cannot reproduce a Ruby Console error from static analysis of `SketchUp.register_extension` — that
call is native SketchUp API code, not something in this repo. What I can say with confidence:

1. Nothing in the 31 lines that execute before this call can itself raise.
2. The most plausible trigger for an error happening **inside** `register_extension` (per the
   trace's innermost frame) is a **conflict at the SketchUp/Ruby environment level** — e.g. the
   review environment having a stale or conflicting prior install of this extension already
   registered (from an earlier submission attempt under a different version or the old `gismo` ID),
   given `PLUGIN_NAME = 'ZB Smart Gizmo'` is identical across every variant this project has ever
   produced. This is a hypothesis about the *review environment's state*, not a confirmed code
   defect — I want to be explicit that I cannot verify this without access to that environment.
3. **I have not added a rescue around this call**, per your instruction not to hide the error —
   doing so would suppress the diagnostic information needed to actually resolve this with Trimble.

---

## C. SILENT RESCUES

All 19 `rescue` clauses in the shipped source, found via `grep -rn "rescue" zb_smart_gizmo.rb
zb_smart_gizmo/*.rb` and individually inspected in full context:

### Should remain as-is (justified — 15 of 19)

| File:line | Pattern | Why it's fine |
|---|---|---|
| `gizmo.rb:1820` | `warn(...)` then `raise` | Logs and re-raises — does not swallow at all. |
| `observer.rb:80, 97, 110` | `warn_overlay_issue(action, e)` | Logs class/message/full backtrace via `warn`. |
| `overlay.rb:1110, 2306` | `UI.messagebox("...#{e.message}")` | Shown directly to the user, plus aborts the pending model operation cleanly. |
| `overlay.rb:1184, 1198` | `UI.messagebox('Invalid ...')` | Deliberate user-input validation (e.g. typing "abc" into a distance field) — not a bug being hidden. |
| `overlay.rb:1360, 1373, 1420` | `nil` (no message) | Intentional "parse, return nil on failure" sentinel; every call site checks the `nil` and shows its own message (confirmed by tracing callers). Standard Ruby idiom, equivalent to `Integer() rescue nil`. |
| `overlay.rb:1477, 1636, 1658, 1691, 1695` | `warn_overlay_issue(action, e)` | Logs class/message/backtrace. |
| `overlay.rb:2330` | `view.tooltip = 'Invalid length'` | Light-touch feedback for Measurements-box re-edit, matching native SketchUp's own inline (non-dialog) VCB error convention. |

### Should be changed — log the error (2 of 19)

**`overlay.rb:390-393`** (`GizmoOverlay#onMouseMove`):
```ruby
rescue StandardError => e
  p e
  @model.tools.pop_tool if active_itself?
end
```
This wraps the entire `onMouseMove` handler — a hot path called on every mouse pixel movement.
`p e` dumps the raw exception object to the console with no context (no `[ZB Smart Gizmo]` prefix,
no backtrace, no description of what failed) and execution continues as if nothing happened. This is
weaker than the `warn_overlay_issue` pattern already established and used consistently everywhere
else in this same class. **Proposed fix:** replace `p e` with a call to the existing
`warn_overlay_issue('handle mouse move', e)` helper (already defined in this same file at line 508),
for consistency with the rest of the class and to surface a proper diagnostic message instead of a
bare object dump.

**`overlay.rb:1625-1627`** (`GizmoOverlay#dynamic_component_observer`):
```ruby
rescue StandardError
  nil
end
```
Fully silent — no logging of any kind. The very next method in the file,
`dynamic_component_entity?` (line 1636), does the equivalent thing (queries the optional bundled
Dynamic Components integration) and correctly logs via `warn_overlay_issue`. **Proposed fix:** add
`warn_overlay_issue('read dynamic component observer', e)` (capturing `=> e`), matching the sibling
method immediately below it.

Both fixes are additive logging only — they do not change what gets returned or how control flow
proceeds, so they carry no behavior risk to the success path. Not implemented yet, per your
instruction to diagnose only.

---

## D. LICENSING

Searched the entire shipped source (`zb_smart_gizmo.rb` and all 5 files in `zb_smart_gizmo/`) for
`licens`, `trial`, `.expired?`, and `activation_key` (case-insensitive): **zero matches.**

**No licensing system, trial logic, or `licensed?` method exists anywhere in this codebase.**
Nothing was invented or added to check this — this is a direct grep result.

### Does the reviewer note apply?

**No, not to the current code.** The reviewer's note — "license checks should be inside core
business methods rather than relying on a separate `licensed?` method that could be overridden" — is
a defensive-coding recommendation that presupposes a licensing system exists to structure correctly.
Since this extension has no licensing/trial mechanism at all, there is nothing to restructure. This
note is either generic reviewer guidance that doesn't apply here, or (consistent with the pattern in
A/B) feedback generated against a different, unrelated codebase or an assumption about what the
extension does rather than an observation of this specific source.

**No licensing code should be added in response to this note** — the task explicitly says not to
invent licensing, and there's no existing implementation this note could reasonably be asking to
fix.

---

## E. ICONS

`zb_smart_gizmo/loader.rb:474-487`:
```ruby
def self.command_icon_path
  png = File.join(PATH, 'Resources', 'icon.png')
  svg = File.join(PATH, 'Resources', 'icon.svg')
  pdf = File.join(PATH, 'Resources', 'icon.pdf')
  if RUBY_PLATFORM.include?('darwin')
    return pdf if File.exist?(pdf)
    return svg if File.exist?(svg)
  end

  return svg if File.exist?(svg)
  return png if File.exist?(png)

  png
end
```
Used at `loader.rb:489-497` (`build_toggle_command`) to set both `cmd.small_icon` and
`cmd.large_icon` for the toolbar/menu toggle command.

### Confirmed behavior

- **macOS (`darwin`):** tries PDF first, then SVG. ✅ Matches "PDF on Mac."
- **Windows (and any non-darwin platform):** falls through the `if` block (does nothing there) and
  hits the shared fallback — **`return svg if File.exist?(svg)` is checked before PNG.** Since
  `icon.svg` is present in the package (confirmed in all 3 current `Release/*.rbz` files), **this
  code already returns SVG on Windows, not PNG.**
- **PNG is only ever reached if both SVG and PDF/SVG are missing from the package** — a defensive
  last-resort fallback that isn't actually exercised by any current package, since `icon.svg` and
  `icon.pdf` are both always bundled alongside `icon.png`.

### Is the reviewer's note valid for current code?

**Not as a description of a defect in the current logic** — the preference order already matches
what was requested (SVG on Windows, PDF on Mac, PNG only as an unused fallback). Only one hardcoded
icon reference exists in the entire codebase (`command_icon_path` itself); nothing elsewhere
bypasses it or forces PNG.

This is consistent with the same unifying hypothesis as A and B: if the reviewer's environment
evaluated an older snapshot of this code that predated this platform-aware SVG/PDF logic (i.e., a
version that referenced PNG unconditionally), they would see exactly the PNG-only behavior their
note describes — even though current code doesn't behave that way.

**No code change is proposed here** unless you want the defensive PNG fallback path removed entirely
(not recommended — it's a reasonable safety net if resources are ever accidentally omitted from a
future package, and removing it doesn't change today's actual behavior either way).

---

## Unifying hypothesis across A, B, and E

All three findings — wrong version reported (1.1.0 vs. actual 1.2.0), a registration-time trace
whose line numbers are ambiguous between old and current code, and icon behavior matching an
outdated pre-SVG/PDF version — are independently consistent with **the same explanation: the
Extension Warehouse review evaluated an older or cached submission artifact, not the 1.2.0 package
most recently prepared.** I want to be precise about confidence here: this is the best-supported
explanation given everything checked in this pass, but it is still a hypothesis about
Trimble/Warehouse-side state that I cannot directly verify — only Trimble can confirm what file their
review tooling actually processed. This is consistent with (and reinforces) the open questions
already sent in `WAREHOUSE_SUPPORT_REQUEST.md`.

---

## Summary table

| # | Reviewer comment | Confirmed root cause | Files/lines | Proposed fix | Risk | Verification method |
|---|---|---|---|---|---|---|
| A | Version mismatch (1.1.0 vs 1.2.0) | No file matching this citation exists in current or historical project state; current source and all 3 current packages read 1.2.0 everywhere checked | `zb_smart_gizmo.rb:14,26`; all `Release/*.rbz` | No code fix possible — request Trimble confirm which file/version their tooling evaluated | N/A | Already re-verified fresh in this pass; re-confirm by re-checking the exact file hash/version Trimble's tooling reports next round |
| B | Ruby Console error at registration | Trace matches current file's line numbers exactly, but that layout is unchanged since the old 1.1.0 code, so it doesn't distinguish old vs. new; no code before/at the call can raise | `zb_smart_gizmo.rb:7,8,25-31` | No code defect found to fix; do not add a rescue here (would hide the diagnostic) | N/A | Ask Trimble for the full, untruncated Ruby Console error message/class (the trace given is a backtrace, not the error itself) |
| C | Silent rescue blocks | 2 of 19 rescues log weakly (`p e`) or not at all (bare `nil`); other 17 already log via `warn_overlay_issue`, show user-facing messages, or intentionally return checked `nil` sentinels | `overlay.rb:390-393`, `overlay.rb:1625-1627` | Replace `p e` and bare `nil` with `warn_overlay_issue(...)` calls, matching the pattern already used by every sibling rescue in the same file | Low — additive logging only, no control-flow change | `ruby -c` after edit; manually trigger each path (mouse-move exception is hard to force; DC-observer path can be tested by toggling the bundled Dynamic Components extension) |
| D | Licensing structure | No licensing/trial code exists anywhere in the codebase | N/A (confirmed absent via grep) | No action — note doesn't apply; do not add licensing | N/A | Re-run the same grep after any future change that might introduce licensing |
| E | PNG icons instead of SVG/PDF | Current code already prefers SVG on Windows and PDF on Mac; PNG is an unused defensive fallback | `zb_smart_gizmo/loader.rb:474-487` | No fix needed for current behavior; optional: remove the unused PNG fallback (not recommended) | N/A if unchanged | Re-confirm `icon.svg`/`icon.pdf` presence in whatever package is next submitted |

---

## Stopped here, per instruction

No code modified, no RBZ rebuilt. Two concrete, low-risk fixes are ready to implement if you approve
(the two logging upgrades in C) — everything else in this rejection points away from a code defect
and toward the Warehouse review process itself, which needs Trimble's input to resolve (see
`WAREHOUSE_SUPPORT_REQUEST.md`).
