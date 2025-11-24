# Reader Width Feature - Executive Summary

## Requirements Summary

The reader_width feature provides a book-like reading experience for markdown files by constraining content to a comfortable column width (e.g., 80 characters) and centering it within wide editor windows. This solves the readability problem where markdown content stretches across the full width of modern widescreen displays, making lines too long to read comfortably.

Users can set `reader_width = 80` in their config to transform their markdown editing experience. Instead of reading 200+ character lines that require excessive eye movement, content is constrained to a readable width and centered on screen. Long lines automatically wrap at word boundaries, preserving readability without horizontal scrolling.

The feature is non-intrusive with a default of 0 (disabled), ensuring existing users see no behavior change until they opt in. Window options (wrap, linebreak, breakindent) are automatically configured when enabled and restored when disabled or in insert mode, respecting user preferences.

All prose and code elements (paragraphs, headings, code blocks) should be consistently centered for a unified reading experience. Tables are intentionally exempted to preserve their columnar structure, as wrapping table cells would destroy readability.

Current implementation successfully centers 4 of 6 element types (paragraphs, headings, code blocks, horizontal rules). Lists and blockquotes require additional implementation work to add margin support.

## Technical Summary

The reader_width feature uses a two-layer centering approach: window-level configuration via vim's `breakindentopt` and element-level virtual text padding.

**Architecture:** When reader_width is enabled, `config.lua` automatically adds window options (wrap, linebreak, breakindent) for comfortable text wrapping. The UI updater (`core/ui.lua`) calculates `center_offset = floor((window_width - reader_width) / 2)` and sets `breakindentopt = "shift:{center_offset}"`, which shifts all text including virtual text by the center offset.

**Element Rendering:** Individual renderers (paragraph, heading, code, dash) add virtual text padding of `center_offset + user_margin` at the start of each line. This provides the initial left offset for non-wrapped lines, while `breakindentopt shift:` ensures wrapped portions align correctly.

**Key Technical Decision:** Using `breakindentopt` for global centering rather than per-element padding provides consistency and efficiency. All content shifts uniformly, and vim handles wrapped line alignment automatically.

**Implementation Gaps:** Lists (`bullet.lua`) and blockquotes (`quote.lua`) lack the `left_margin` configuration mechanism needed for centering. Lists only have `left_pad` (inline padding around bullet icons), and blockquotes only overlay markers without margin support. Adding centering to these requires introducing margin configuration and virtual text padding at column 0.

**Width Constraint:** The `env.win.width()` helper returns `min(window_width, reader_width)` to constrain element rendering, though vim's text wrapping still occurs at window width, not reader_width.

## Status Summary

| Requirement | Backend | Frontend | Testing | Verification & Gaps |
|-------------|---------|----------|---------|---------------------|
| **REQ-RW-001:** Content Width Constraint | ✅ | N/A | ⚠️ Manual | `env.win.width()` constrains elements. Gap: No automated test |
| **REQ-RW-002:** Horizontal Centering | ✅ | N/A | ⚠️ Manual | `breakindentopt shift:` + virtual padding. Verified via debug output |
| **REQ-RW-003:** Text Wrapping | ❌ | N/A | ⚠️ Manual | NOT WORKING: Window options not being applied. Text extends beyond window without wrapping |
| **REQ-RW-004:** Configuration Interface | ✅ | N/A | ✅ Unit | Config accepted, default 0. Tests in `tests/reader_width_unit_spec.lua` |
| **REQ-RW-005:** Element Coverage | 🟡 | N/A | ⚠️ Manual | 4 of 6 types centered. Gap: Lists/blockquotes lack margin mechanism |
| **REQ-RW-006:** Window Option Restoration | ✅ | N/A | ✅ Integration | Restores wrap/linebreak/breakindent. Test: `tests/reader_width_spec.lua:97` |
| **REQ-RW-007:** Performance Constraint | ✅ | N/A | N/A | O(1) center calculation. No automated perf test needed |
| **REQ-RW-008:** Narrow Window Handling | ✅ | N/A | ✅ Unit | `center_offset()` returns 0 correctly. Test: `tests/reader_width_unit_spec.lua` |
| **REQ-RW-009:** Multiple Windows | ✅ | N/A | ⚠️ Manual | Per-window settings in `ui.lua:108`. Gap: No automated test |
| **REQ-RW-010:** Zero Margins Rendering | ✅ | N/A | ⚠️ Manual | Fixed in `paragraph.lua:27`. Gap: No regression test |

**Progress:** 4.5 of 10 requirements complete

**Note:** While several individual requirements appear technically implemented, the current architecture does not elegantly support all requirements. Significant architectural rework is needed to achieve the complete feature vision.

**Coverage Summary:**
- ✅ Complete: 7 requirements
- ❌ Not Working: 1 requirement (REQ-RW-003: Text wrapping)
- 🟡 Partial: 1 requirement (REQ-RW-005: 4 of 6 element types)
- ⏭️ Planned: 1 requirement (table exception in REQ-RW-005)

**Testing Gaps:**
- No automated tests for centering accuracy (should verify exact offset)
- No tests for REQ-RW-001, REQ-RW-002, REQ-RW-003, REQ-RW-009, REQ-RW-010
- Manual testing procedures exist but not automated

**Implementation Gaps:**
- **Text wrapping not working** (window options not being applied - text extends beyond window)
- Lists not centered (`bullet.lua` lacks `left_margin` config)
- Blockquotes not centered (`quote.lua` lacks margin mechanism)
- Table exception not implemented (should allow tables to exceed width)

## Architectural Concerns

The current implementation approach does not provide an elegant, maintainable solution for all requirements:

1. **Window options not applying correctly** - Despite being configured in `config.lua`, the wrap/linebreak/breakindent options aren't being applied to windows, suggesting a fundamental issue with the rendering lifecycle or condition checking

2. **Inconsistent renderer patterns** - Some renderers support `left_margin` while others only have `left_pad` or no margin mechanism, indicating lack of architectural cohesion

3. **Two-layer complexity** - The combination of `breakindentopt shift:` (global) and per-element virtual text padding (local) creates complexity and potential for misalignment

4. **Render condition coupling** - Window options are tied to render state, meaning features like wrapping disappear in insert mode, which may not be the desired behavior

**Recommendation:** Consider architectural redesign before completing remaining requirements. The current approach may not scale to elegantly support all 10 requirements without significant technical debt.

## Test Execution

**Manual Testing:**
```bash
nvim test_reader_width.md
# Set reader_width = 80 in config
# Verify paragraphs, headings, code blocks centered
# Lists and blockquotes currently flush-left (known gap)
```

**Automated Tests:**
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua', sequential = true }"
# Tests: tests/reader_width_spec.lua, tests/reader_width_unit_spec.lua
```

**Debug Scripts:**
```vim
:luafile debug_reader_width.lua  " Check window options and center_offset
:luafile debug_config.lua         " Verify reader_width config
:luafile debug_render.lua         " Check rendering conditions
```
