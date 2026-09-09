# ZB Smart Gizmo Pro 1.5.3 - Extension Warehouse Candidate

Date: 2026-09-09
Package: `Release/ZB_Smart_Gizmo_Pro_1.5.3_Warehouse_Candidate.rbz`
SHA-256: `ead763862b04fd3436b9dd46d60186cc8062536b504275037bca2c72a140deb9`

This is a new Extension Warehouse identity, not an update package for the existing `ZB Smart Gizmo`
listing. The new identity is intentionally separated at the package path, root loader name,
support-folder name, technical ID, overlay ID, preferences section, menu label, toolbar label, and
Ruby namespace.

## New Identity

- Product name: `ZB Smart Gizmo Pro`
- Root loader: `zb_smart_gizmo_pro.rb`
- Support folder: `zb_smart_gizmo_pro/`
- Technical ID: `zb_smart_gizmo_pro`
- Ruby namespace: `Zbellbound::SmartGizmoPro`
- Overlay ID: `zbellbound.smart_gizmo_pro.overlay`
- Version: `1.5.3`

## Candidate Contents

The candidate RBZ was built from the current working tree and contains exactly these 9 entries:

```text
zb_smart_gizmo_pro.rb
zb_smart_gizmo_pro/gizmo.rb
zb_smart_gizmo_pro/loader.rb
zb_smart_gizmo_pro/observer.rb
zb_smart_gizmo_pro/overlay.rb
zb_smart_gizmo_pro/utils.rb
zb_smart_gizmo_pro/Resources/icon.pdf
zb_smart_gizmo_pro/Resources/icon.png
zb_smart_gizmo_pro/Resources/icon.svg
```

The package excludes tests, documentation, development files, temporary files, caches,
source-control metadata, RuboCop configuration, and unrelated assets.

## Automated Verification

- `ruby -c` passed for all 6 packaged Ruby files and all Ruby tests.
- Full Ruby regression suite passed: 187 runs, 1555 assertions, 0 failures, 0 errors, 0 skips.
- Source RuboCop-SketchUp pass passed: 6 files inspected, no offenses.
- Extracted candidate RuboCop-SketchUp/FileStructure pass passed: 6 files inspected, no offenses.
- Extracted candidate syntax pass passed for all 6 packaged Ruby files.

## Required Next Steps

This candidate still needs an independent read-only release audit and real SketchUp manual testing
before it should be called Extension Warehouse-ready.
