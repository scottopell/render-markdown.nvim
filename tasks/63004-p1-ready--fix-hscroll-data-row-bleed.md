---
artifact: data-row overlay covers full visible width at any leftcol
created: 2026-04-15
priority: p1
status: ready
---

# Fix: data-row overlay bleeds buffer text when scrolled

## Summary

When a pipe table is horizontally scrolled so that `leftcol > 0`, data-row overlays are clipped too short and buffer text leaks through on the right. The header row, delimiter row, and bottom border all render correctly — only data rows are affected.

Reproduces with `tests/hscroll_newspaper_spec.lua` (added in the same commit as this task).

## Context

The regression came in with the horizontal-scroll table work on the reconciled branch (merged as `de241ea`). It was invisible to the existing proptest-style assertions in `hscroll_spec.lua` and `hscroll_edge_spec.lua` because those tests work at Layer 1 (extmark widths via `util.assert_fullline_widths_strict`). The extmarks look correct — their widths are equal and the alignment math is fine. The bug is at Layer 2 (screen grid): the overlay extmark is shorter than the visible screen area, so the buffer text to the right of the overlay shows through.

The screen-level failure on `demo/newspaper-table.md` at `leftcol=111`:
```
row 5:   No UI indicators for "new content available" │
```
That fragment is the tail of the "Notes" cell on row 110 (REQ-NP-003), leaking through the partially-covered data-row overlay.

Likely suspects in `lua/render-markdown/render/markdown/table.lua`:
- `Render:row()` builds the scrolled overlay via `build_row_line(row, highlight)` then clips with `line:sub(trim_amount + 1, width)`. Width calculation uses `delim_cols` but the overlay's right extent may not match the screen's right extent.
- `build_row_line` pads each cell to `target_width` with `line:pad(fill)` but does not emit right-side filler past the last pipe. If the buffer row is longer than the composed overlay (e.g. because the raw row has trailing content past its computed width), buffer text past the overlay end is visible.
- Check the overlap between `row.node.start_col + row.node.text` width and the composed line width; they may diverge for rows whose source has more content than the delimiter's width accounts for.

## Done When

- `tests/hscroll_newspaper_spec.lua` passes
- Full hscroll suite still passes (`tests/hscroll_spec.lua`, `tests/hscroll_edge_spec.lua`)
- Manual verification: open `demo/newspaper-table.md`, scroll to col 111 with cursor on row 110 col 130, confirm no buffer text is visible past the overlay on any data row
- No regression in table_spec.lua or other table rendering tests

## Notes

The fix likely extends the overlay with right-side filler up to the full visible width (or uses `hl_eol = true` / `virt_text_pos = 'eol'` to paint to end of line), or changes the strategy from narrow virt_text to a `virt_lines`-based full replacement.

The regression test uses substring detection rather than whole-screen snapshot because the leak position is load-bearing for the assertion — a snapshot would pass/fail on unrelated rendering changes and wouldn't tell you *where* the leak is.
