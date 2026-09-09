# ZB Smart Gizmo Pro Features

## Overview

ZB Smart Gizmo Pro is a SketchUp transform extension that adds an interactive viewport gizmo for:

- move
- rotate
- scale
- pivot editing
- exact numeric input
- Smart Scale for supported objects

It is designed to combine direct viewport interaction with precise typed values.

## Core transform tools

### Move

- Drag axis arrows to move along `X`, `Y`, or `Z`.
- Click an axis arrow to open a numeric move dialog.
- Move arrow size is adjustable from Preferences.
- Default move/scale handle size is `80` pixels.
- Move dialog supports:
  - distance input
  - optional target world coordinate on the clicked axis
  - a `Mode: Move / Copy` selector
  - a `Number of copies` field, used when Mode is `Copy`; always blank when the dialog opens --
    it is never prefilled or remembered from a previous entry
- Example:
  - click `Z`
  - enter a distance
  - or enter `Target world Z`
- Move/Copy array:
  - switch Mode to `Copy` and enter how many copies to create, e.g. `3` (no `x` prefix -- just
    the number)
  - the original selection stays in place; that many new equally-spaced copies are created along
    the clicked axis at `1x`, `2x`, ... `Nx` the entered distance, preserving each source's own
    rotation, scale, and mirroring
  - entering `3` creates 3 copies (4 objects total including the original)
  - accepts whole positive numbers only, `1`-`1000`, with optional surrounding whitespace (e.g.
    ` 3 `); a blank field, zero, negative, decimal, or an `x`-prefixed value (`x3`) is rejected
    with the message "Enter a whole number from 1 to 1000." and changes nothing -- in Move mode
    the field is ignored entirely, whatever it contains
  - works with multi-selection and negative distances, same as an ordinary move
  - the whole array is one undo step
  - supports groups and components only (the only entity types with a documented duplication
    method in the SketchUp Ruby API); a selection containing loose edges/faces, a locked
    group/component, or a component glued to another entity is rejected up front with a message
    and no model change -- ordinary Move is unaffected and still works on any entity type
- Ctrl-drag internal array:
  - select one or more groups/components, hold `Ctrl`, drag a move arrow to create a copy, and
    release the mouse -- this ordinary Ctrl-drag copy is unchanged from before
  - immediately type `/3` (or `3/`) in Measurements: the complete dragged distance divides into
    3 equal spaces, creating 2 new copies between the original and the copy the drag already made
    -- that dragged copy stays exactly where it was, always counting as the final copy
  - e.g. a `3000mm` drag with `/3` places copies at `1000mm`, `2000mm`, and `3000mm` from the
    original; `/1` removes any copies added this way, leaving just the single dragged copy
  - typing a different `/N` afterward (e.g. `/4` after `/3`) replaces the array with `N` total
    copies rather than adding to it; typing an ordinary distance instead still re-edits the
    dragged copy's position as before
  - accepts whole numbers `1`-`1000` only, with optional surrounding whitespace; `/0`, negative,
    decimal, or malformed input (or over `1000`) shows a concise message and changes nothing
  - supports groups and components only, same restriction as Move/Copy array; an unsupported or
    glued selection shows a message and leaves the single Ctrl-drag copy intact
  - clicking elsewhere, starting another drag, or changing tools ends the array-input window
  - the whole session -- the drag-and-copy plus every `/N` edit made to it -- is one undo step
- Ctrl-drag external array:
  - same Ctrl-drag-and-release as the internal array above, but immediately type `x3` (or `3x`,
    `X3`, `3X` -- case-insensitive, matching SketchUp's own external-array input convention)
  - repeats the complete dragged distance that many times: the dragged copy stays exactly where
    it was and counts as copy 1, with 2 more copies added beyond it at the same spacing
  - e.g. a `1000mm` drag with `x3` places copies at `1000mm` (the dragged copy), `2000mm`, and
    `3000mm`; `x1` removes any copies added this way, leaving just the single dragged copy
  - typing a different `xN` afterward (e.g. `x4` after `x3`) replaces the array with `N` total
    copies rather than adding to it
  - switching between the two array syntaxes also replaces the array: `/3` then `x3` leaves only
    the external array in place, and `x3` then `/3` leaves only the internal one -- both always
    keep the dragged copy fixed exactly where it was dragged to
  - accepts whole numbers `1`-`1000` only, with optional surrounding whitespace; `x0`, negative,
    decimal, or malformed input (or over `1000`) shows a concise message and changes nothing
  - supports groups and components only, same restriction as the internal array; an unsupported
    or glued selection shows a message and leaves the single Ctrl-drag copy intact
  - clicking elsewhere, starting another drag, pressing Esc, or changing tools ends the
    array-input window
  - the whole session -- the drag-and-copy plus every `xN`/`/N` edit made to it -- is one undo step

### Rotate

- Drag rotate rings to rotate around `X`, `Y`, or `Z`.
- Click a rotate ring to open an angle dialog.
- Type an exact angle value.
- Rotate feedback uses a cleaner minimal arc-based display instead of a large filled wheel.
- Rotate ring size follows the same adjustable handle-size preference as the move arrows and
  scale handles (there is no separate rotate-only size setting).
- Arrow-key rotate shortcuts can be enabled in preferences.
- Arrow-key rotate works while hovering the gizmo.
- Arrow-key rotate can either remember the last used rotate axis or use a fixed axis.
- Fixed arrow-key rotate axis supports `X`, `Y`, or `Z`.
- Fixed arrow-key rotate defaults to `Z`.
- If remember-last-axis is enabled and no rotate axis has been used yet, the fallback axis is `Z`.
- Rotate snap increment is configurable in preferences.

### Scale

- Drag scale handles to scale along a chosen axis.
- Click a scale handle to open a numeric scale dialog.
- Scale handle size follows the same adjustable preference as the move arrows.
- Default move/scale handle size is `80` pixels.
- Single-axis scale supports exact target-length style input.
- Popup input supports configured default units and explicit units.
- Popup input also supports relative expressions such as:
  - `+100`
  - `+100+6+5`
  - `600+100`
  - `600mm+100mm`
  - `24in+2in`

If an expression starts with `+` or `-`, the currently shown value is used as the base.

## Smart Scale

Smart Scale is a structure-aware alternative to normal SketchUp scale.

### What Smart Scale does

- Preserves structure when possible instead of uniformly stretching everything.
- Tries to protect detailed ends/corners and stretch from the middle span.
- Supports:
  - frame-like groups
  - components
  - nested grouped/component structures
  - basic plain-geometry fallback on simple shapes

### Smart Scale behavior

- Live drag scaling
- Exact numeric popup input
- Measurements box re-edit
- Shared Smart Scale pipeline for drag and typed input

### Smart Scale notes

- Best suited for structured objects such as frames, windows, tables, and similar assemblies.
- Plain geometry can fall back to a simpler scale mode when there is no useful structure to preserve.
- Copied Dynamic Components are handled more safely by uniquing the copied component tree before Smart Scale works on it.

## Pivot editing

- Drag the center pivot control to reposition the gizmo origin.
- Pivot dragging uses SketchUp's input-point inference under the cursor, so the gizmo center can snap to model geometry while repositioning.
- Context menu options include:
  - reset pivot to selection center
  - set pivot to model origin
  - set pivot to object origin

## Orientation modes

- Global orientation
- Object/local orientation

This lets the gizmo align either to world axes or to the selected object’s axes.

## Plane handles

- Plane move handles support constrained movement on:
  - `XY`
  - `YZ`
  - `XZ`

This allows moving on two axes while locking the third.

## Selection and visibility behavior

- Gizmo appears for the current selection.
- Clicking empty space clears selection and hides the gizmo.
- Selecting a new object brings the gizmo back.
- Right-click gizmo menu appears only when right-clicking on the gizmo.
- Double-click and non-gizmo right-click are left to normal SketchUp behavior.
- Toggle on/off now actively refreshes the overlay if needed, which helps recover the gizmo in older files/scenes.

## Native tool compatibility

- Pressing `M` switches to native Move.
- Gizmo stays out of the way while native Move is active.
- This preserves SketchUp Measurements input such as `/2` after native Move.
- Returning to normal selection/orbit use lets the gizmo become available again.

## Preferences

Preferences are available from:

- `Extensions > ZB Smart Gizmo Pro > Settings > Preferences...`

Current preferences include:

- handle size (shared by move arrows, scale handles, and rotate rings)
- pivot size
- scale input unit
- Smart Scale mode
- arrow-key rotate enabled/disabled
- arrow-key rotate remember-last-axis enabled/disabled
- fixed arrow-key rotate axis
- rotate snap increment (degrees)
- arrow-key rotate shortcut step values

Default visual sizing:

- handle size (move arrows, scale handles, and rotate rings): `80` pixels, clamped between
  `80` and `320` pixels

Boolean-style settings are presented as dropdowns.

## Built-in help

The extension includes a built-in manual available from:

- `Extensions > ZB Smart Gizmo Pro > Settings > Manual`

This provides quick guidance for:

- move
- rotate
- scale
- Smart Scale
- preferences
- workflow tips

## Toolbar and menu

- The extension includes a toolbar command/button for toggling the gizmo.
- Extension commands are also available under:
  - `Extensions > ZB Smart Gizmo Pro`

## About

About is available from:

- `Extensions > ZB Smart Gizmo Pro > Settings > About`

It shows:

- Developer: Peter Zbel
- Website: www.zbellbound.com

## Numeric input workflows

### Move

- distance entry
- world-axis target entry
- Move/Copy array (plain `Number of copies` count), one undo step
- Ctrl-drag internal array (`/N` or `N/` typed right after a Ctrl-drag copy), one undo step
- Ctrl-drag external array (`xN`, `Nx`, case-insensitive, typed right after a Ctrl-drag copy),
  one undo step; switching between `/N` and `xN` replaces the array

### Rotate

- angle popup dialog
- Measurements box support
- optional arrow-key step rotation

### Scale

- popup exact value
- target-length style input on single axis
- relative popup expressions
- Measurements re-edit

## Manual-friendly summary

ZB Smart Gizmo Pro combines viewport interaction and precision input:

- direct drag handles
- exact popup values
- Measurements box re-edit
- pivot control
- adjustable handle size (shared by move, scale, and rotate)
- local/global orientation
- Smart Scale for supported objects
- native SketchUp tool compatibility
- built-in manual/help

## Current notes

- Default Scale and Smart Scale are different:
  - Default Scale applies normal uniform SketchUp scaling.
  - Smart Scale tries to preserve object structure when possible.
- Smart Scale is most useful on supported structured objects.
- Dynamic Components have special behavior and require more care than ordinary groups/components.
