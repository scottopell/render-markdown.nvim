---
artifact: branch synced with upstream/main through v8.12.0
created: 2026-04-15
priority: p2
status: ready
---

# Sync fork with upstream, resolve table parser refactors

## Summary

Upstream (MeanderingProgrammer/render-markdown.nvim) has moved 48 commits ahead since our fork diverged, spanning three releases (v5.0.1, v8.11.0, v8.12.0). Most are low-risk, but a cluster of upstream refactors to the table parsing classes will conflict with our `build_row_line()` / `process_cell_content()` work.

## Context

### High-conflict upstream commits (all touch `lua/render-markdown/render/markdown/table.lua`)

- `4e14c0e` chore: refactor classes used for table parsing
- `bd482f9` chore(refactor): store node associated with columns when parsing tables
- `fcea077` chore(refactor): separate table delimiter from overall column metadata
- `8951960` chore(refactor): update table class names used while parsing
- `2247dcd` feat: improve table start column tracking
- `9075055` fix: remove pipe_table.filler config and RenderMarkdownTableFill highlight (breaking-ish: affects anything referencing config.filler)
- `687de72` chore: store inline virtual text directly in context
- `4ae2f2e` chore: more concise return in render setup methods

The class-restructuring commits (4e14c0e, bd482f9, fcea077, 8951960) will likely require rewriting our `build_row_line`, `process_cell_content`, `get_inline_elements`, and `apply_conceal` against the new table class shape. `2247dcd` may overlap with our byte-vs-display-column logic.

### Lower-risk upstream commits worth picking up

Bug fixes:
- `f128369` conceal padding in multi-backtick code spans (CommonMark)
- `c7188a8` + `2c56346` nested headings / heading padding inside block quotes
- `35c1925` handle footnotes in `link_reference_definition` nodes
- `1c95813` handle rendering empty buffers

Features (nice-to-have):
- `48934b4` math superscript + footnote body transformer
- `477997f` disable code based on languages
- `996ec12` priority option for signs/dashes
- `ae89236` link.highlight_title option

## Done When

- Fork's `main` contains upstream `main` up through `0fd43fb` (or latest at sync time)
- Our hscroll, buffer_state, clock, and debounce work is preserved
- All tests green: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" -c qa`
- Manual verification: scroll a table with emoji + bold + italic + code spans; inline styling survives the overlay

## Notes

Approach options:
- **Merge upstream into main.** Preserves our commit history; merge commit documents the sync. Conflicts resolved once in the merge.
- **Rebase our work on upstream.** Linear history; rewrites every one of our commits against the new table class shape. Higher per-commit effort but cleaner log.

The merge approach is almost certainly right here — the commits touching table.lua are not logically independent, they share the hscroll infrastructure context. Rebasing would mean repeatedly re-resolving against an evolving base.

Recommended attack order:
1. Merge upstream/main into main, accept conflicts in table.lua
2. Port `build_row_line` / `process_cell_content` against the new class shape (new field names, new metadata split)
3. Run test suite; fix regressions
4. Manual hscroll smoke test with emoji + inline styling
