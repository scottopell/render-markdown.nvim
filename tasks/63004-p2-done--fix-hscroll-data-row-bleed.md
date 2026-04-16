---
artifact: scrolled overlay extmark anchored at byte col for display col leftcol
created: 2026-04-15
priority: p2
status: done
---

# Fix: scrolled overlay byte-col placement (reframed from data-row bleed)

## Summary

This task was originally opened ("fix data-row overlay bleed when scrolled")
based on a sub-agent's Layer 2 regression test that fired on
`demo/newspaper-table.md` at `leftcol=111`. On investigation, the reported
symptom turned out to be **correct rendering**: the text that looked like
a leak was the legitimate content of that cell at that scroll position,
and the 2 leading screen columns that looked like missing overlay were
the `signcolumn = auto` gutter (the plugin places heading signs elsewhere
in the buffer, which causes neovim to display the signcolumn window-wide).

Investigation surfaced a real but unrelated bug in the same area, which
this task now covers and closes: a byte-vs-display column error in the
extmark placement for scrolled overlays.

## What the real bug was

`Render:row()` and `Render:delimiter()` in
`lua/render-markdown/render/markdown/table.lua` passed `leftcol` directly
as the `col` parameter to `nvim_buf_set_extmark`. `leftcol` is a display
column; extmark `col` is a byte offset. For rows whose source contains
multi-byte glyphs (emoji, CJK) before `leftcol`, the two diverge and the
mark was placed at a byte position corresponding to a display column
strictly less than `leftcol`. Neovim then clipped the overlay's leading
display columns offscreen, producing a visible overlay shifted right by
the drift amount.

This was invisible to every existing Layer 1 assertion (which only
checked overlay content and widths, not byte positions) and invisible to
Layer 2 assertions (because the shifted-then-clipped overlay has the
same right edge as a correctly-placed one — the visible grid lies when
the pipeline has compensating clips).

## Fix

- Added `str.col_to_byte(s, display_col)` — inverse of the existing
  `str.byte_to_col`. Pure, used in `lib/str.lua`.
- `Render:row()` and `Render:delimiter()` now convert `leftcol` to a
  byte offset via `str.col_to_byte(node.text, leftcol)` before placing
  the extmark.
- `Render:border()` did not need the fix — it only emits full-row
  overlays on empty adjacent lines (guarded by `str.width(target) == 0`),
  so there's no multi-byte content to cause drift.

## Test coverage

- `tests/hscroll_mark_placement_spec.lua` — Layer 1 assertions against
  the extmark's byte col for ASCII-only, single-emoji, variation-
  selector-emoji, and compound-emoji rows. Verifies byte_col =
  leftcol + drift for each case. Would have failed before the fix.

## Allium spec

- Invariant I7 (`OverlayMarkAtDisplayColByteOffset`) added to
  `specs/horizontal-scroll.allium`.
- History section updated with bug #3 and a note explaining why Layer 2
  alone cannot catch this class of bug.

## Lessons

1. Layer 2 (screen grid) is not always authoritative for rendering
   bugs. An overlay placed at the wrong byte col produces an
   offscreen-clipped visible result that looks identical to a correct
   placement on the rendered grid. The byte-level assertion is
   authoritative; the grid is secondary.
2. A Layer 2 assertion requires a known-good reference. Without one,
   the test encodes a guess. The regression test that was removed as
   part of this task fell into exactly that trap.
3. Signcolumn shifts the entire text area right by 2 columns whenever
   ANY sign exists in the buffer under `signcolumn = 'auto'`. Easy to
   mistake this gutter for missing overlay.

The visual-testing skill's anti-patterns section now includes both of
these points.
