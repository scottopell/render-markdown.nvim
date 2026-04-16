---
artifact: single merged branch with horizontal scroll + inline styling
created: 2026-04-15
priority: p1
status: ready
---

# Reconcile horizontal scroll branches

## Summary

Two branches implement horizontal scroll table rendering with different approaches:

- `claude/triage-branches-gRg6h`: `buffer_state` lifecycle management, clock injection, debounce trailing edge, basic hscroll overlays (single-highlight). No inline styling.
- `feat/ignore-horizontal-scroll`: hscroll overlays with REQ-HST-004 inline styling (bold/italic/code via treesitter queries, multi-chunk `virt_text`). Uses old `M.cache[buf]` pattern (leaks). Has spEARS specs.

Both fix the byte-vs-display-column bug and the `buf=0` test helper bug, but via different code paths.

## Context

The triage branch has the better infrastructure (buffer_state, clock, debounce). The feature branch has the better rendering (inline styling preservation). Need to combine: take buffer_state/clock/debounce from triage, then port `process_cell_content()` and its treesitter inline queries on top.

Key conflicts expected in:
- `lua/render-markdown/render/markdown/table.lua` (both modify `build_row_line`)
- `lua/render-markdown/lib/str.lua` (both modify `sub()`)
- `tests/hscroll_spec.lua` (both add tests)
- `tests/util.lua` (both add helpers)

## Done When

- Single branch with all of: buffer_state, clock, debounce, hscroll with inline styling
- All tests pass
- No duplicate/dead code from the merge
