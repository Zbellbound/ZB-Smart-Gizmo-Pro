# ZB Smart Gizmo Pro 1.5.3 - Warehouse Checklist

Date: 2026-09-09
Candidate: `Release/ZB_Smart_Gizmo_Pro_1.5.3_Warehouse_Candidate.rbz`
SHA-256: `ead763862b04fd3436b9dd46d60186cc8062536b504275037bca2c72a140deb9`

## Completed Automated Gates

- [x] New root loader name: `zb_smart_gizmo_pro.rb`
- [x] New matching support folder: `zb_smart_gizmo_pro/`
- [x] New product name: `ZB Smart Gizmo Pro`
- [x] New technical ID: `zb_smart_gizmo_pro`
- [x] New Ruby namespace: `Zbellbound::SmartGizmoPro`
- [x] New overlay ID: `zbellbound.smart_gizmo_pro.overlay`
- [x] Extensionless `SketchupExtension.new` loader path: `zb_smart_gizmo_pro/loader`
- [x] Extensionless internal `Sketchup.require` calls
- [x] Package contains exactly 9 approved entries
- [x] Package excludes tests, docs, dev tooling, caches, source-control metadata, and unrelated assets
- [x] `ruby -c` passes for packaged Ruby files
- [x] Full Ruby regression suite passes
- [x] RuboCop-SketchUp source gate passes
- [x] RuboCop-SketchUp extracted-candidate FileStructure gate passes

## Still Required

- [ ] Independent read-only release audit, preferably by Claude, against the exact candidate RBZ
- [ ] Clean install into a SketchUp profile with no prior Pro install
- [ ] Ruby Console silence during install and normal use
- [ ] Toolbar/menu/manual/about verification under `ZB Smart Gizmo Pro`
- [ ] Move, rotate, scale, Smart Scale, pivot, and copy-array smoke tests
- [ ] Picker empty-space test
- [ ] Undo/Redo verification for primary actions
- [ ] Smart Scale Dynamic Component repro confirmation
- [ ] Final checksum confirmation immediately before upload
