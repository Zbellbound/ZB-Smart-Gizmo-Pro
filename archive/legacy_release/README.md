# Archived: stale `zb_smart_gismo.rbz` build

Moved out of `Release/` on 2026-07-07 per the user's explicit decision during the audit cleanup
(see `../../AUDIT_REPORT.md` H4 and `../../CLEANUP_PLAN.md`).

**Update 2026-08-19:** the `zb_smart_gismo.rbz` binary itself has been deleted from this folder as
part of the post-1.2.1 project cleanup (it was never tracked in git and was not referenced by any
shipped source, test, or build instruction). This README, and the historical LegacyID decision
record below, are retained — nothing about the open LegacyID decision is resolved or affected by
removing the binary.

## Do not use or distribute this file (historical binary, since removed)

This archive was `zb_smart_gismo.rbz` — a build that registered under the old, misspelled extension
id `zb_smart_gismo` (`PLUGIN_ID = 'zb_smart_gismo'`, `SketchupExtension.new(PLUGIN_NAME,
'zb_smart_gismo/loader')`) rather than the current, correct `zb_smart_gizmo`. It was the
newest-timestamped file anywhere in `Release/` at the time of the audit, which made it easy to
mistake for the primary build.

`Release/ZB_Smart_Gizmo_RBZ_LegacyID/` and `Release/ZB_Smart_Gizmo_RBZ_LegacyID_Minimal/` used to
contain the same "gismo" extension id, organized as clearly-labeled unpacked source trees, but were
deleted 2026-07-07 as part of the post-1.2.0 `Release/` cleanup (see `../../Release/README.md`)
since they predated the project's cleanup and were never regenerated. Whether that LegacyID
strategy (kept so users who installed under the old id get an update rather than a duplicate
install) should continue at all is still an open decision — see `../../ROADMAP.md`. This specific
loose `.rbz`, however, has no such labeling and is not to be built from, used, or uploaded anywhere.
Future releases should only be produced from `zb_smart_gizmo.rb` / `zb_smart_gizmo/`, using the
`zb_smart_gizmo` extension identifier.
