# ZB Smart Gizmo 1.2.0 — Extension Warehouse Submission Package

Date: 2026-07-07
Source: `main` @ tagged commit `9cc9deb` (tag `v1.2.0`)
Package: `Release/ZB_Smart_Gizmo_1.2.0.rbz`

This document verifies the package against Extension Warehouse packaging requirements, then
provides ready-to-paste submission text and a pre-submission checklist. No GitHub Release was
created and nothing has been published — this is preparation only.

---

## 1–2. Package verification

### Structure

- **Root loader:** `zb_smart_gizmo.rb` present at the package root. ✅
- **Matching support folder:** `zb_smart_gizmo/` present, name matches the root loader's basename
  (`SUPPORT_NAMESPACE = File.basename(__FILE__, '.*')`, i.e. it's derived from the filename, not
  hardcoded — renaming risk is structurally prevented). ✅
- **Package contents (12 files, verified via `unzip -l`):**
  ```
  zb_smart_gizmo.rb
  zb_smart_gizmo/Features.md
  zb_smart_gizmo/gizmo.rb
  zb_smart_gizmo/loader.rb
  zb_smart_gizmo/Manual.md
  zb_smart_gizmo/observer.rb
  zb_smart_gizmo/overlay.rb
  zb_smart_gizmo/utils.rb
  zb_smart_gizmo/Resources/cursor.pdf
  zb_smart_gizmo/Resources/icon.pdf
  zb_smart_gizmo/Resources/icon.png
  zb_smart_gizmo/Resources/icon.svg
  ```
- **Zip path separators:** confirmed forward-slash (`/`) throughout, not backslash — required for
  correct extraction on macOS as well as Windows. ✅
- **No unnecessary/legacy content:** no `EW.lic` (unrelated third-party license file, previously
  removed from source), no native C++ backend (`native_backend.rb`/`native/`, archived out of the
  shipped folder, confirmed dead code — never `require`d), no stray `gismo`-misspelled files. ✅

### Naming consistency

- `PLUGIN_ID = 'zb_smart_gizmo'`, root file `zb_smart_gizmo.rb`, support folder `zb_smart_gizmo/` —
  all consistent. Grepped the entire package for the old misspelling (`gismo`): zero matches. ✅

### Version

- `PLUGIN_VERSION = '1.2.0'` in `zb_smart_gizmo.rb:14`, matches the `extension.version` assignment
  used for `SketchupExtension#version` at registration. Matches the git tag `v1.2.0` and this
  package's filename. ✅

### Loader / extension registration

- `zb_smart_gizmo.rb` requires `extensions.rb`/`sketchup.rb`, wraps everything in
  `module ZBSmart; module Gizmo; ... end; end` (no top-level namespace pollution), and guards
  registration with `unless file_loaded?(__FILE__)` to prevent duplicate registration on reload. ✅
- `SketchupExtension.new(PLUGIN_NAME, 'zb_smart_gizmo/loader')` correctly points at
  `zb_smart_gizmo/loader.rb`, which in turn uses `Sketchup.require` (not `require_relative` or any
  absolute path) to load `utils`, `observer`, `overlay`, `gizmo` in dependency order. Confirmed no
  `require_relative` or hardcoded absolute paths anywhere in the package (these would break on a
  real user's install path). ✅
- All of `extension.version`, `.copyright`, `.creator`, `.description` are set from named constants
  (`PLUGIN_VERSION`, `PLUGIN_COPYRIGHT`, `PLUGIN_CREATOR`, `PLUGIN_DESC`), not inline literals — one
  source of truth. ✅

### Resources

- `Resources/icon.png`, `icon.svg`, `icon.pdf`, `cursor.pdf` all present and included in the package.
- `command_icon_path` (in `zb_smart_gizmo.rb`) is platform-aware: prefers `.pdf`/`.svg` on macOS,
  falls back to `.svg` then `.png` elsewhere — all three formats it can reference are present. ✅
- **Note:** `icon.png` is 1224×1248px (461 KB) and is used directly as both `cmd.small_icon` and
  `cmd.large_icon` for the toolbar/menu command. This works (SketchUp downsamples it), but it's a
  much larger source image than a toolbar icon needs — flagged in the checklist below as worth a
  pre-submission look, not a blocking defect.

### Compatibility

- `MINIMUM_VERSION = 23` with an explicit runtime check in `zb_smart_gizmo/gizmo.rb`
  (`if Sketchup.version.to_i < MINIMUM_VERSION`) that shows a clear message box rather than failing
  silently or throwing an error on older SketchUp versions. ✅

### Ruby syntax

- `ruby -c` passes on all 6 packaged `.rb` files (`zb_smart_gizmo.rb`, `gizmo.rb`, `loader.rb`,
  `observer.rb`, `overlay.rb`, `utils.rb`). ✅ (This closes the one open item from
  `WAREHOUSE_SUBMISSION_CHECKLIST.md`'s "Current package status" section.)

**Verdict: package structure, naming, version, loader/registration, resources, and compatibility all
check out. No blocking issues found — nothing here required a rebuild.**

One documentation accuracy note, unrelated to packaging: `Features.md` (bundled in the package)
states the rotate ring has its own independently adjustable size with a distinct 80px default.
Checked against the source — there is no separate rotate-ring-size preference; the rotate ring
shares the single `gizmo_size` preference (default 150px, clamped 80–320px) with the move/scale
handles. The submission copy below does not repeat this specific claim. Consider correcting
`Features.md` before or shortly after this submission (not a packaging blocker).

---

## 3. Extension Warehouse submission text

### Title

```
ZB Smart Gizmo
```

### Short description

*(for the one-line/summary field, ~150 characters)*

```
Interactive move, rotate, scale, and pivot gizmo for SketchUp, with Smart Scale for structure-aware scaling of frames, tables, and assemblies.
```

### Full description

```
ZB Smart Gizmo replaces separate Move, Rotate, and Scale tools with a single interactive
viewport gizmo, so you can transform objects without switching tools or losing your
selection.

KEY CAPABILITIES

Move, Rotate, Scale — in one gizmo
- Drag axis arrows to move, rotate rings to rotate, and scale handles to resize along X, Y,
  or Z.
- Click any handle to open a numeric input dialog for exact values instead of dragging.
- Drag a plane handle to move along two axes at once while locking the third.
- Reposition the gizmo's pivot by dragging its center control, with SketchUp's own
  point inference for snapping to model geometry.

Smart Scale
- A structure-aware alternative to normal scaling. Instead of uniformly stretching an
  entire object, Smart Scale tries to protect detailed ends and stretch the middle span —
  ideal for frames, window and door assemblies, tables, and similar structured objects.
- Works on groups, components, and nested group/component structures. Falls back to
  standard scaling automatically when an object has no useful structure to preserve.

Precise numeric input, without leaving the viewport
- Every handle supports exact typed values: distances, target world coordinates, angles,
  and scale factors.
- Scale input accepts relative expressions (e.g. +100, 600mm+100mm) and explicit units.
- Full support for SketchUp's Measurements box for re-editing your last transform.

Fits your existing workflow
- Press M at any time to hand off to SketchUp's native Move tool without losing your
  Measurements input.
- Switch between Global and Object/Local orientation modes depending on how you want the
  gizmo aligned.
- Right-click the gizmo for quick pivot and orientation options — right-clicking elsewhere
  behaves like normal SketchUp.
- A full built-in manual is available from the extension's Settings menu.

Adjustable to your scene
- Handle and pivot sizes are adjustable from Preferences.
- Configure your preferred scale input unit, Smart Scale on/off, and arrow-key rotate
  behavior (including step sizes and snap increment).

Requires SketchUp 2023 or later.
```

### Key features

*(bulleted, for the "features" field if the listing form has one)*

```
- Combined Move / Rotate / Scale viewport gizmo
- Smart Scale — structure-aware scaling for frames, tables, and assemblies
- Exact numeric input on every handle (distance, angle, scale, world coordinates)
- Two-axis plane-move handles
- Draggable, snappable pivot control with quick reset options
- Global and Object/Local orientation modes
- Native Move tool handoff (press M) with Measurements input preserved
- Adjustable handle and pivot sizes
- Configurable scale units and rotate snap/step behavior
- Built-in manual accessible from the extension menu
```

### Installation notes

```
1. Download ZB_Smart_Gizmo_1.2.0.rbz.
2. In SketchUp, open Extensions > Extension Manager (Window > Extension Manager on some
   versions).
3. Click "Install Extension" and select the downloaded .rbz file.
4. Restart SketchUp if prompted.
5. The gizmo toggles on automatically when you select an object. Use
   Extensions > ZB Smart Gizmo to access Preferences, the built-in Manual, and About.

Requires SketchUp 2023 or later.
```

### Release notes — 1.2.0

```
1.2.0 is a reliability and quality release. It includes several confirmed bug fixes,
performance improvements to the interactive gizmo, and a substantial internal cleanup, with
no changes to existing features or workflows.

Bug fixes:
- Fixed an issue where finishing a scale-handle drag could leave the gizmo's internal state
  incorrectly marked as active, which could cause inconsistent behavior on the next
  interaction.
- Fixed an error-handling path in the rotate handle that could show a confusing, unrelated
  error instead of the actual problem in certain edge-case geometry during a rotate drag.
- Fixed a latent error in an internal debugging code path for the axis handles.

Performance improvements:
- Reduced repeated recalculation of on-screen handle geometry during mouse movement and
  drawing.
- Reduced unnecessary allocation during interactive dragging and drawing, improving
  responsiveness.
- Reduced repeated internal settings lookups during move and plane-drag operations.

Also included: consolidated duplicated internal logic across the move, rotate, scale, and
plane-move handles, and removal of unused legacy code and files. This release has passed
full manual validation in SketchUp before submission.

No changes to saved preferences, file formats, or existing workflows — fully backward
compatible with models and settings from earlier versions.
```

### Compatibility text

```
Requires SketchUp 2023 or later (Windows and macOS). No third-party Ruby library
dependencies. No changes to file formats or saved preferences from previous versions —
safe to update from any earlier 1.x release.
```

### Keywords / tags

```
gizmo, transform, move, rotate, scale, pivot, smart scale, viewport tool, precision input,
productivity, modeling tool
```

---

## 4. Pre-submission checklist

- [ ] **Signing / encryption** — decide whether to encrypt non-root Ruby files during
      SketchUp's signing step (open since the original checklist; see
      `WAREHOUSE_SUBMISSION_CHECKLIST.md` "Dependency review" section and the SketchUp Help link
      below). Not a code issue — a one-time choice made during the Warehouse upload flow itself.
- [ ] **Screenshots / icons** — prepare Warehouse listing screenshots (separate from the in-package
      toolbar icon). Consider whether the bundled `icon.png` (1224×1248px, noted above) should be
      resized/optimized for its toolbar use before or independently of this submission.
- [ ] **Compatibility versions** — confirm the exact list of SketchUp versions to declare in the
      listing form matches the code's actual floor (`MINIMUM_VERSION = 23`, i.e. SketchUp 2023) —
      don't just copy the "2023+" wording without checking the current dropdown options Warehouse
      offers, in case they've changed since the linked help docs were written.
- [ ] **Support / contact URL** — add a support URL or support email to the Extension Warehouse
      profile/listing (open item carried over from `WAREHOUSE_SUBMISSION_CHECKLIST.md`). The About
      dialog currently shows `www.zbellbound.com` with no dedicated support address — decide if
      that's the URL to list or if a support-specific contact should be used instead.
- [ ] **Privacy / license info** — confirm what the Warehouse listing form requires for
      privacy-policy and license-type fields. Verified via grep across the entire package: no
      `Net::HTTP`, `open-uri`, or any other network-call pattern anywhere in the source — the
      extension makes no network requests and collects no user data, so this should be
      straightforward to state in the listing.
- [ ] **Manual SketchUp validation passed** — ✅ already confirmed complete (per your prior
      message); this package (`Release/ZB_Smart_Gizmo_1.2.0.rbz`) was built from the tagged,
      manually-tested `v1.2.0` commit.

---

## Reference

- SketchUp Help — Extension signing/encryption:
  <https://help.sketchup.com/en/extension-warehouse/extension-encryption-and-signing>
- SketchUp Help — Extension development best practices:
  <https://help.sketchup.com/sv/extension-warehouse/extension-development-best-practices>
