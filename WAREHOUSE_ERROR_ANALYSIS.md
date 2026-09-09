# Extension Warehouse "Unrelated branches" Rejection — Analysis

Date: 2026-07-07
Package audited: `Release/ZB_Smart_Gizmo_1.2.0_Warehouse.rbz` (the strict 10-file package, extracted
fresh and audited from scratch — not assumed from memory).

**Important caveat up front:** "Unrelated branches" is not a documented SketchUp Extension
Warehouse validation message I have verified knowledge of. I don't have access to the Warehouse's
internal validation logic or to your developer account/listing history, so section 7 below is
clearly labeled as a hypothesis, not a confirmed fact — everything in sections 1–6 is, by contrast,
directly verified against the actual package contents.

---

## 1. Root loader file name

`zb_smart_gizmo.rb` — present, single file, correct name. ✅

## 2. Extension folder

`zb_smart_gizmo/` — present, name matches the root loader's basename exactly
(`SUPPORT_NAMESPACE = File.basename(__FILE__, '.*')` derives it from the filename rather than a
separate hardcoded string, so the two structurally cannot drift apart). ✅

## 3. `SketchupExtension` registration — exact values found

```ruby
extension = SketchupExtension.new(PLUGIN_NAME, 'zb_smart_gizmo/loader')
extension.version     = PLUGIN_VERSION
extension.copyright   = PLUGIN_COPYRIGHT
extension.creator     = PLUGIN_CREATOR
extension.description = PLUGIN_DESC
```

| Field | Value |
|---|---|
| Extension name | `ZB Smart Gizmo` |
| Loader path | `zb_smart_gizmo/loader` (resolves to `zb_smart_gizmo/loader.rb`, present) |
| Creator | `Peter Zbel / Zbellbound` |
| Version | `1.2.0` |
| Description | `Interactive transform gizmo overlay for SketchUp with Smart Scale for structured objects.` |
| Copyright | `Copyright (c) Peter Zbel / Zbellbound` |
| Extension ID (`PLUGIN_ID`) | `zb_smart_gizmo` |

All five `PLUGIN_*` constants are defined exactly once, in `zb_smart_gizmo.rb`, and referenced by
name everywhere else — no duplicated or conflicting literal values found anywhere else in the
package (checked every `Copyright`/`Creator`/`Vendor` string occurrence). ✅

## 4. Module namespaces

Every `module` declaration in the package, with file:line:

```
zb_smart_gizmo.rb:7        module ZBSmart
zb_smart_gizmo.rb:8          module Gizmo
zb_smart_gizmo/loader.rb:4   module ZBSmart
zb_smart_gizmo/loader.rb:14    module Gizmo
zb_smart_gizmo/gizmo.rb:5    module ZBSmart::Gizmo
zb_smart_gizmo/observer.rb:1 module ZBSmart::Gizmo
zb_smart_gizmo/overlay.rb:4  module ZBSmart::Gizmo
zb_smart_gizmo/overlay.rb:116  module SmartScaleApplier   (nested inside ZBSmart::Gizmo)
zb_smart_gizmo/utils.rb:1    module ZBSmart::Gizmo
zb_smart_gizmo/utils.rb:2      module TT                 (nested)
zb_smart_gizmo/utils.rb:113     module ShapeGeom          (nested)
zb_smart_gizmo/utils.rb:229     module ClickDetection     (nested)
zb_smart_gizmo/utils.rb:251     module TransformCallbacks (nested)
```

- **One clean top-level namespace:** everything lives under `ZBSmart::Gizmo` (or `ZBSmart` with a
  nested `Gizmo`, which is the same namespace, just written the long way in two files). ✅
- **No unrelated legacy namespace found.** ✅
- **No stale `gismo` namespace or identifier anywhere in the package** (see section 5). ✅
- **No duplicate extension registration** — exactly one `Sketchup.register_extension` call and
  exactly one `SketchupExtension.new` call in the entire package (both in `zb_smart_gizmo.rb`,
  guarded by `unless file_loaded?(__FILE__)` so it can't double-register even on a Ruby reload). ✅

## 5. Search results for stale/unrelated identifiers

Searched every file in the actual `.rbz` (not the wider repo) for each term:

| Term | Result |
|---|---|
| `gismo` (case-insensitive) | **Zero matches** |
| `smart_dimension`, `smart_dimensions`, `zb_smart_dimension` | **Zero matches** |
| `TT_Lib` | **Zero matches** |
| Any other `'zb_...'`-style literal besides `PLUGIN_ID` | Only `'zb_smart_gizmo_manual'` — an
  `UI::HtmlDialog` `preferences_key` (used to remember the Manual window's size/position between
  sessions). Unrelated to extension identity/registration; a normal, expected string. |
| `require_relative`, hardcoded absolute paths, or any `require`/`Sketchup.require` not pointing at
  `zb_smart_gizmo/...` or the two standard SketchUp bootstrap files (`extensions.rb`, `sketchup.rb`) | **None found** |

No BOM, no non-ASCII characters, no encoding anomalies in any of the 6 Ruby files (checked with
`file` and a byte-level non-ASCII scan). Line endings are a harmless mix of CRLF/LF across files —
not a plausible cause of a "branches" rejection and not something SketchUp's Ruby loader is
sensitive to.

## 6. Multiple independent plugin branches / duplicate registrations

**Confirmed: no.** There is exactly one `SketchupExtension`, one `PLUGIN_ID`, one root loader, and
one namespace tree. Nothing in this package defines a second, independent extension, a second
`Sketchup.register_extension` call, or a second unrelated top-level module. This specific package is
internally consistent and singular.

---

## 7. Most likely cause of "Unrelated branches" (hypothesis, needs your confirmation)

Since the package itself is clean by every check above, the most plausible explanation isn't inside
this .rbz at all — it's a mismatch between this package's identity and whatever the Extension
Warehouse already has on file for your developer account/listing.

**This project was renamed mid-history.** Confirmed from this repo's own audit trail
(`AUDIT_REPORT.md`, `CLEANUP_PLAN.md`, `WAREHOUSE_SUBMISSION_CHECKLIST.md`'s original, uncorrected
text): the extension originally shipped under the misspelled name **`zb_smart_gismo`** — root file
`zb_smart_gismo.rb`, folder `zb_smart_gismo/`, and (going by the same naming convention this project
uses throughout) almost certainly `PLUGIN_ID = 'zb_smart_gismo'` at that time. It was later renamed
to the correctly-spelled **`zb_smart_gizmo`** used in the package audited above. The project
deliberately kept "LegacyID" build variants (`PLUGIN_ID = 'zb_smart_gismo'`) specifically so existing
installs under the old name would receive updates rather than being treated as a new, separate
install — see `ROADMAP.md`'s open item on this exact question.

**The hypothesis:** if your Extension Warehouse developer account already has an existing listing —
even an incomplete draft — created under the old `zb_smart_gismo` name/ID, then uploading this
package (root file, folder, and extension ID all renamed to `zb_smart_gizmo` simultaneously) would
present the Warehouse with a package whose identity doesn't match anything it has on record for that
listing. A rejection phrased as "unrelated branches" is consistent with a version-control-style
check that expects a new upload to be a continuation of the same tracked identity, and instead sees
what looks like a completely different extension.

**What I can't verify myself:** whether such a listing/draft actually exists on your account, and
under which exact ID. That can only be checked in your SketchUp Developer Center account — I don't
have access to it.

### Please confirm one of the following

1. **Yes, I already have an Extension Warehouse listing (even a draft) under the old
   `zb_smart_gismo` name/ID.** → The fix is to either (a) submit under that same old ID to preserve
   continuity with the existing listing (using a rebuilt `LegacyID` package — see
   `archive/legacy_release/`), or (b) explicitly start this as a *new* listing in the Warehouse
   submission flow rather than an update to the old one, if you want to fully retire the old ID.
2. **No, this is a genuinely first-time submission, no prior listing exists under any name.** → The
   ID mismatch theory doesn't apply, and the cause is something outside this package that I'd need
   more information to diagnose (e.g. the exact Warehouse account/listing state at the moment of
   rejection, or whether "Unrelated branches" is verbatim text vs. a paraphrase of a longer message —
   the exact wording and any surrounding text from the rejection would help narrow this down
   further).

---

## Proposed fix (pending your answer above)

**Do not change any code** — every check in sections 1–6 came back clean; there is no code-level
defect to fix in `zb_smart_gizmo.rb` or `zb_smart_gizmo/`.

- **If scenario 1 applies:** rebuild a strict, docs-free package (same 10-file structure as this
  one) from the `LegacyID` source instead (`PLUGIN_ID = 'zb_smart_gismo'`, root file
  `zb_smart_gismo.rb`, folder `zb_smart_gismo/`), so the upload's identity matches what the Warehouse
  already has on file. This would need code from `archive/legacy_release/` or a fresh regeneration
  of that variant — flagging this as a real code/packaging change, not something to do silently.
- **If scenario 2 applies:** the current `zb_smart_gizmo`-named package should be fine identity-wise,
  and the actual cause needs to be re-diagnosed from the Warehouse's exact rejection text and
  account state, not from anything in this package.

No code has been changed. Waiting for your confirmation before proposing (let alone making) any
further change.
