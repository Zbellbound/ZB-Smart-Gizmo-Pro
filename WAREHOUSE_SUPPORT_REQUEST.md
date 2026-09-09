# Extension Warehouse Support Request — "Unrelated branches" error

**Extension name:** ZB Smart Gizmo
**Version:** 1.2.0
**Error received:** "Unrelated branches"

## Summary

We are receiving an "Unrelated branches" rejection when submitting ZB Smart Gizmo 1.2.0 to the
Extension Warehouse. We have tested two different package variants and both are rejected with the
same error. We'd like help understanding what this message refers to for our specific listing/account,
since we've been unable to find documentation on it.

## Packages tested

1. **`ZB_Smart_Gizmo_1.2.0_Warehouse.rbz`** — root loader `zb_smart_gizmo.rb`, extension folder
   `zb_smart_gizmo/`, extension ID `zb_smart_gizmo`.
2. **`ZB_Smart_Gizmo_1.2.0_Warehouse_LegacyID.rbz`** — same code, repackaged with root loader
   `zb_smart_gismo.rb`, extension folder `zb_smart_gismo/`, and extension ID `zb_smart_gismo` (an
   older technical ID this extension may have been registered under previously), on the chance the
   rejection was related to a naming/ID change. Both packages were rejected with the identical
   "Unrelated branches" message.

## What we've verified on our end

Both packages were audited directly (contents extracted and inspected, not assumed):

- Each package contains exactly **one** root loader file and **one** matching extension folder.
- Each package registers the extension exactly **once** — one `SketchupExtension.new` call and one
  `Sketchup.register_extension` call, with no duplicates.
- No duplicate or secondary extensions are defined anywhere in either package.
- Neither package contains development artifacts, documentation files, an `archive/` folder, or
  backup files — both are stripped down to only the Ruby source and resource files needed to run the
  extension.
- No GitHub Release or any GitHub-hosted artifact is involved in either submission — both `.rbz`
  files were built directly from local source and uploaded independently.

## What we're asking

Since the error persists across both an ID-preserving and an ID-changed package, we'd like to
confirm:

1. What "Unrelated branches" specifically checks for on Trimble's side (e.g. extension ID history,
   developer account/listing linkage, code-signing state, or something else).
2. Whether our account or an existing listing already has prior submission history under either the
   `zb_smart_gizmo` or `zb_smart_gismo` extension ID that this new upload is being compared against.
3. What information from our side (developer account details, listing ID, or a specific rejection
   log/reference number) would help Trimble diagnose this further.

Thank you for your help.
