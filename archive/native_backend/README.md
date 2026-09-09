# Archived: native Smart Scale backend

This folder was moved out of `zb_smart_gizmo/` on 2026-07-07 as part of the approved cleanup
pass (see `../../AUDIT_REPORT.md` finding M1 and `../../CLEANUP_PLAN.md`).

## Why it's here instead of in the shipped extension

`native_backend.rb` defines `ZBSmart::Gizmo::NativeScaleBackend`, a wrapper intended to call an
optional compiled C++ acceleration path (`native/src/scale_engine.cpp`, `native/src/ruby_bridge.cpp`)
for Smart Scale's scale-factor math, falling back to a pure-Ruby implementation
(`ruby_compute_scale`) when no compiled binary is present.

At the time of the audit, `zb_smart_gizmo/loader.rb` only requires `utils`, `observer`, `overlay`,
and `gizmo` — it never requires `native_backend`, and no other file in the extension calls
`NativeScaleBackend`, `ScalePlusPlusNative`, or `compute_scale`. No compiled `mac/`/`win/` binaries
existed in the tree for it to load even if it were wired in. Smart Scale's actual, currently-shipping
implementation is the pure-Ruby `SmartScaleApplier` module in `zb_smart_gizmo/overlay.rb`, which does
not depend on this code at all.

Moving this folder out of `zb_smart_gizmo/` changes **nothing at runtime** — the code was
unreachable before the move and remains unreachable now, just outside the folder that gets zipped
into a release. It is kept here (not deleted) in case the native acceleration path is picked back up
later; see `ROADMAP.md` for the open decision on whether to finish wiring it in or retire it for good.

## Contents

- `native_backend.rb` — the Ruby wrapper (moved from `zb_smart_gizmo/native_backend.rb`)
- `native/` — the C++ source and build scripts (moved from `zb_smart_gizmo/native/`)
