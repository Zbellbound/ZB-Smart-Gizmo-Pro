# ZB Smart Gizmo Pro Manual

ZB Smart Gizmo Pro adds an in-viewport move, rotate, and scale gizmo for SketchUp selections. It is designed for fast regular transforms, exact numeric input, pivot control, and Smart Scale behavior for supported grouped/component objects.

## Move

- Drag an axis arrow to move on one axis.
- Drag a plane square to move on two axes while locking the third.
- Drag the center pivot to reposition the gizmo pivot.
- Click a move arrow for exact input.
- Move input can use a distance or an absolute world target on the active axis.

### Move/Copy Array

- Click a move arrow, choose `Copy` mode, enter the movement distance, then enter a plain copy
  count such as `3` (no `x` prefix) in the `Number of copies` field -- it always opens blank.
- Creates that many equally spaced copies along the clicked axis; the original stays in place.
  Entering `3` creates 3 copies plus the unchanged original (4 objects total).
- Groups and components only -- loose geometry, locked, or glued selections are not supported.
- The complete array is removed with a single Undo.

### Ctrl-Drag Internal Array

1. Select one or more groups/components.
2. Hold `Ctrl` and drag a Gizmo move arrow to create a copy, then release the mouse -- this is the
   ordinary Ctrl-drag copy and works exactly as before if you stop here.
3. Immediately type `/3` (or `3/`) in Measurements.
4. The complete distance between the original and the dragged copy divides into 3 equal spaces:
   the dragged copy stays exactly where it was and counts as the last of the 3 copies, and 2 new
   copies fill the space before it.

Example: a `3000mm` drag with `/3` places copies at `1000mm`, `2000mm`, and `3000mm` from the
original.

- `/N` is the primary syntax; `N/` is also accepted. Whole numbers `1`-`1000` only, with optional
  surrounding whitespace -- `/0`, negative, decimal, `/` alone, or a value over `1000` shows a
  concise message and changes nothing.
- Typing a different `/N` while the window is still open (e.g. `/4` right after `/3`) replaces the
  array with `N` total copies instead of adding another array. Typing an ordinary distance instead
  still re-edits the dragged copy's position, same as before this feature existed.
- Clicking elsewhere, starting another drag, pressing `Esc`, or switching tools ends the
  array-input window.
- Groups and components only, the same restriction as Move/Copy Array above. If the Ctrl-dragged
  selection includes unsupported or glued geometry, `/N` shows a message and leaves the single
  Ctrl-drag copy untouched instead of copying part of the selection.
- The whole session -- the drag-and-copy plus every `/N` edit made to it -- is one Undo.

### Ctrl-Drag External Array

1. Select one or more groups/components.
2. Hold `Ctrl` and drag a Gizmo move arrow to create a copy, then release the mouse -- this is the
   same ordinary Ctrl-drag copy as above.
3. Immediately type `x3` in Measurements.
4. The complete dragged distance repeats 3 times: the dragged copy stays exactly where it was and
   counts as copy 1, and 2 more copies are added beyond it at the same spacing.

Example: a `1000mm` drag with `x3` places copies at `1000mm` (the dragged copy), `2000mm`, and
`3000mm`.

- `x3` is the primary syntax; `3x` is also accepted, matching SketchUp's own documented
  external-array input convention. Both are case-insensitive (`X3`/`3X` work too). Whole numbers
  `1`-`1000` only, with optional surrounding whitespace -- `x0`, negative, decimal, `x` alone, or
  a value over `1000` shows a concise message and changes nothing.
- Typing a different `xN` while the window is still open (e.g. `x4` right after `x3`) replaces the
  array with `N` total copies instead of adding another array.
- Switching between the internal (`/N`) and external (`xN`) syntax also replaces the array:
  entering `/3` then `x3` leaves only the external array in place, and `x3` then `/3` leaves only
  the internal one. Either way the dragged copy always stays fixed exactly where it was dragged to.
- Clicking elsewhere, starting another drag, pressing `Esc`, or switching tools ends the
  array-input window -- same as the internal array.
- Groups and components only, the same restriction as the internal array above. An unsupported or
  glued selection shows a message and leaves the single Ctrl-drag copy untouched.
- The whole session -- the drag-and-copy plus every `xN`/`/N` edit made to it -- is one Undo.

## Rotate

- Drag a rotate ring to rotate around that axis.
- Click a rotate ring to enter an exact angle.
- Drag-rotate snaps to the `Rotate Snap Increment` preference, `5` degrees by default.
- Rotate feedback uses a minimal arc display instead of a large filled wheel.
- Arrow-key rotate can be enabled or disabled in Preferences.

## Arrow-Key Rotate

Arrow-key rotate works while hovering the gizmo.

- `Left Arrow`: rotate by the configured left step, default `-90` degrees.
- `Right Arrow`: rotate by the configured right step, default `90` degrees.
- `Up Arrow`: rotate by the configured up step, default `180` degrees.
- `Down Arrow`: rotate by the configured down step, default `-180` degrees.

Preferences include two axis behavior settings:

- `Remember Last Rotate Axis = Yes`: arrow keys use the last rotate ring axis you used.
- `Remember Last Rotate Axis = No`: arrow keys always use the selected `Fixed Rotate Axis`.
- `Fixed Rotate Axis`: choose `X`, `Y`, or `Z`.
- The fixed rotate axis defaults to `Z`.

Use `Remember Last Rotate Axis = No` and `Fixed Rotate Axis = Z` if you mostly want arrow keys to rotate around the default vertical Z axis.

## Scale

- Drag a scale handle for live scaling.
- Click a scale handle for exact input.
- Single-axis scale supports exact target-length style input.
- Popup input accepts configured default units and explicit units.
- Popup input supports additive expressions such as `+100`, `+100+6+5`, `600+100`, `600mm+100mm`, and `24in+2in`.
- If an expression starts with `+` or `-`, the currently shown value is used as the base.
- While a single-axis Scale handle is active, the Measurements box shows the resulting real-world
  dimension for that axis as a number (for example `50.8`), not an internal scale multiplier --
  using the model's own unit, precision, and locale settings, with the unit suffix omitted from
  the result. You can still type explicit units in Scale expressions, e.g. `600mm`.
- Entering `/2` divides the currently displayed dimension by 2 -- for example, typing `/2` when the
  box reads `50.8` changes it to `25.4`. `/3`, `/4`, and so on work the same way, and the
  divisor must be greater than zero. This only applies to Scale input; it is not the same as the
  Ctrl-drag internal copy-array `/N` (see Ctrl-Drag Internal Array above), which divides a dragged
  copy distance rather than a Scale dimension.
- Entering `x2` (or `X2`) multiplies the currently displayed dimension by 2 -- typing `x2` when the
  box reads `25.4` changes it to `50.8`. Decimal multipliers such as `x1.5` work too, and the
  multiplier must be greater than zero. Works the same in ordinary Scale and Smart Scale, in the
  click-handle dialog and in a Measurements re-edit after dragging.
- Quick reference: in Scale, `/2` halves and `x2` doubles the current dimension. During a Ctrl-drag
  Move, `x2` instead creates an external copy array (see Ctrl-Drag External Array above) -- same
  `x`/`X` syntax, different meaning, decided entirely by which handle you're using.

## Smart Scale

Smart Scale is a structure-aware alternative to normal SketchUp scale.

- It tries to preserve detailed end regions and stretch the middle span.
- It works best on grouped/component objects such as tables, frames, cabinets, windows, and nested assemblies.
- Nested group/component structures are supported better than exploded loose geometry.
- If the object has no useful structure to preserve, scaling may behave more like default scale.

## Pivot

- Drag the center pivot control to reposition the gizmo origin.
- Pivot dragging uses SketchUp input-point inference, so it can snap to model geometry.
- Right-click while hovering the gizmo for pivot commands: `Reset Pivot To Selection Center`,
  `Set Pivot To Model Axes Origin`, and `Set Pivot To Object Origin` (only offered when exactly
  one group/component is selected).

## Preferences

Preferences are available from:

`Extensions > ZB Smart Gizmo Pro > Settings > Preferences...`

Available settings include:

- handle size
- pivot size
- scale input unit
- Smart Scale mode
- arrow-key rotate on or off
- remember last rotate axis on or off
- fixed rotate axis
- rotate snap increment
- arrow-key rotate step values

## Workflow Tips

- Press `M` to switch to SketchUp's native Move tool and temporarily hide the gizmo.
- The gizmo is designed to work with normal selection and orbit workflows.
- Keep objects grouped/componentized for the best Smart Scale result.
- For native background right-click and double-click behavior, click outside the gizmo itself.
