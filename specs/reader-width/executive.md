# Reader Width Feature - Executive Summary

## ⚠️ PROJECT DISCONTINUED - 2025-11-24

**This feature has been superseded by [no-neck-pain.nvim](https://github.com/shortcuts/no-neck-pain.nvim).**

After implementing 3000+ lines of rendering-level changes to achieve centered, width-constrained markdown content, we discovered that no-neck-pain.nvim solves the same problem more elegantly at the vim window level. Key advantages of the window-based approach:

1. **Simpler Architecture**: Creates side-buffer padding instead of modifying rendering pipeline
2. **Native Text Wrapping**: Uses vim's built-in `wrap` without fighting window width boundaries (our REQ-RW-003 failure)
3. **Works Everywhere**: Applies to all filetypes and modes, not just rendered markdown
4. **Better Separation of Concerns**: render-markdown.nvim should focus on rendering markdown beautifully, not window layout

**Recommendation**: Users wanting centered reading should use no-neck-pain.nvim. This branch demonstrates that rendering-level centering, while technically possible, introduces unnecessary complexity when window management is the more appropriate solution level.

See "Salvageable Ideas for Future Work" section below for techniques that may still be valuable.

---

# Reader Width Feature - Historical Summary

## Requirements Summary

The reader_width feature provides a book-like reading experience for markdown files by constraining content to a comfortable column width (e.g., 80 characters) and centering it within wide editor windows. This solves the readability problem where markdown content stretches across the full width of modern widescreen displays, making lines too long to read comfortably.

Users can set `reader_width = 80` in their config to transform their markdown editing experience. Instead of reading 200+ character lines that require excessive eye movement, content is constrained to a readable width and centered on screen. Long lines automatically wrap at word boundaries, preserving readability without horizontal scrolling.

The feature is non-intrusive with a default of 0 (disabled), ensuring existing users see no behavior change until they opt in. Window options (wrap, linebreak, breakindent) are automatically configured when enabled and restored when disabled or in insert mode, respecting user preferences.

All prose and code elements (paragraphs, headings, code blocks) should be consistently centered for a unified reading experience. Tables are intentionally exempted to preserve their columnar structure, as wrapping table cells would destroy readability.

Current implementation successfully centers all 6 element types (paragraphs, headings, code blocks, horizontal rules, lists, blockquotes). Marker positioning issues for lists and blockquotes have been resolved through integrated rendering in paragraph wrapping.

## Technical Summary

The reader_width feature uses a two-layer centering approach: window-level configuration via vim's `breakindentopt` and element-level virtual text padding.

**Architecture:** When reader_width is enabled, `config.lua` automatically adds window options (wrap, linebreak, breakindent) for comfortable text wrapping. The UI updater (`core/ui.lua`) calculates `center_offset = floor((window_width - reader_width) / 2)` and sets `breakindentopt = "shift:{center_offset}"`, which shifts all text including virtual text by the center offset.

**Element Rendering:** Individual renderers (paragraph, heading, code, dash) add virtual text padding of `center_offset + user_margin` at the start of each line. This provides the initial left offset for non-wrapped lines, while `breakindentopt shift:` ensures wrapped portions align correctly.

**Key Technical Decision:** Using `breakindentopt` for global centering rather than per-element padding provides consistency and efficiency. All content shifts uniformly, and vim handles wrapped line alignment automatically.

**Marker Integration:** Lists and blockquotes are now fully supported through an integrated rendering approach. When reader_width centering is active, paragraph wrapping includes markers (bullets and blockquote icons) directly in the first virtual line, ensuring proper positioning and alignment. This eliminates the need for separate `left_margin` configuration in `bullet.lua` and `quote.lua`.

**Width Constraint:** The `env.win.width()` helper returns `min(window_width, reader_width)` to constrain element rendering, though vim's text wrapping still occurs at window width, not reader_width.

## Status Summary

| Requirement | Backend | Frontend | Testing | Verification & Gaps |
|-------------|---------|----------|---------|---------------------|
| **REQ-RW-001:** Content Width Constraint | ✅ | N/A | ⚠️ Manual | `env.win.width()` constrains elements. Gap: No automated test |
| **REQ-RW-002:** Horizontal Centering | ✅ | N/A | ⚠️ Manual | `breakindentopt shift:` + virtual padding. Verified via debug output |
| **REQ-RW-003:** Text Wrapping | ❌ | N/A | ⚠️ Manual | NOT WORKING: Window options not being applied. Text extends beyond window without wrapping |
| **REQ-RW-004:** Configuration Interface | ✅ | N/A | ✅ Unit | Config accepted, default 0. Tests in `tests/reader_width_unit_spec.lua` |
| **REQ-RW-005:** Element Coverage | ✅ | N/A | ⚠️ Manual | All 6 types work. Markers integrated into paragraph wrapping. Gap: No automated test |
| **REQ-RW-006:** Window Option Restoration | ✅ | N/A | ✅ Integration | Restores wrap/linebreak/breakindent. Test: `tests/reader_width_spec.lua:97` |
| **REQ-RW-007:** Performance Constraint | ✅ | N/A | N/A | O(1) center calculation. No automated perf test needed |
| **REQ-RW-008:** Narrow Window Handling | ✅ | N/A | ✅ Unit | `center_offset()` returns 0 correctly. Test: `tests/reader_width_unit_spec.lua` |
| **REQ-RW-009:** Multiple Windows | ✅ | N/A | ⚠️ Manual | Per-window settings in `ui.lua:108`. Gap: No automated test |
| **REQ-RW-010:** Zero Margins Rendering | ✅ | N/A | ⚠️ Manual | Fixed in `paragraph.lua:27`. Gap: No regression test |

**Progress:** 8 of 10 requirements complete

**Coverage Summary:**
- ✅ Complete: 8 requirements
- ❌ Not Working: 1 requirement (REQ-RW-003: Text wrapping at reader_width boundary)
- ⏭️ Planned: 1 requirement (table exception in REQ-RW-005)

**Testing Gaps:**
- No automated tests for centering accuracy (should verify exact offset)
- No tests for REQ-RW-001, REQ-RW-002, REQ-RW-003, REQ-RW-009, REQ-RW-010
- Manual testing procedures exist but not automated

**Implementation Gaps:**
- **Text wrapping at reader_width boundary** (REQ-RW-003): Text wraps at window edge, not at reader_width boundary. This is a vim limitation - the `wrap` option wraps at window width, not arbitrary column widths
- Table exception not implemented (should allow tables to exceed width)

## Architectural Concerns

The current implementation approach does not provide an elegant, maintainable solution for all requirements:

1. **Text wrapping boundary** - Vim's native `wrap` option wraps at window width, not at arbitrary column widths like reader_width. The current implementation uses virtual lines with manual text wrapping to achieve REQ-RW-003, but this is complex and only applies to wrapped paragraphs.

2. **Two-layer complexity** - The combination of `breakindentopt shift:` (global) and per-element virtual text padding (local) creates some complexity, but has proven maintainable and effective.

3. **Render condition coupling** - Window options are tied to render state, meaning features like wrapping disappear in insert mode, which may not be the desired behavior.

**Recent Improvements:** The marker positioning issues for lists and blockquotes have been resolved through an integrated rendering approach where paragraph wrapping includes markers directly in virtual lines. This eliminates architectural inconsistencies and provides proper alignment for all element types.

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

---

## Salvageable Ideas for Future Work

While the overall feature is superseded, several implementation techniques developed here may be valuable for other rendering enhancements:

### 1. Two-Layer Centering Pattern (`breakindentopt` + Virtual Text)

**Location**: `lua/render-markdown/core/ui.lua:108-120`

The combination of:
- Global shift via `vim.wo[win].breakindentopt = "shift:" .. offset`
- Per-element virtual text padding

This pattern successfully achieved uniform centering across all element types. While not needed for window-width centering, this technique could be useful for:
- Indenting specific markdown sections (e.g., nested block quotes beyond standard indentation)
- Creating "margin notes" or sidebar annotations at specific column offsets
- Implementing hanging indents for definition lists or footnotes

**Key Insight**: `breakindentopt shift:` affects ALL text in the window, including virtual text, making it powerful for uniform transformations.

### 2. Integrated Marker Rendering in Paragraph Wrapping

**Location**: `lua/render-markdown/render/markdown/paragraph.lua:25-78`

When wrapping paragraphs into multiple virtual lines, markers (bullets, blockquote icons) were integrated directly into the first virtual line rather than rendered separately. This solved alignment issues where markers would be mispositioned.

**Technique**:
```lua
-- Build first line with marker included
local first_line = marker_text .. wrapped_lines[1]
-- Subsequent lines just get padding
for i = 2, #wrapped_lines do
  table.insert(virt_lines, { { padding .. wrapped_lines[i] } })
end
```

**Potential Applications**:
- Custom rendering for definition lists (`<dt>`/`<dd>` tags) where the term needs special positioning
- Enhanced checklist items with custom icons that need to stay aligned with wrapped text
- Multi-line callout boxes where the icon/emoji appears only on the first line

### 3. Window Option State Management

**Location**: `lua/render-markdown/state.lua:65-80` and `lua/render-markdown/core/ui.lua:90-100`

Implemented pattern for:
- Saving original window option values before modification
- Restoring them when feature is disabled or buffer unloaded
- Per-window state tracking to handle split windows correctly

**Code Pattern**:
```lua
-- Save original values
local saved_wrap = vim.wo[win].wrap
-- Apply temporary values
vim.wo[win].wrap = true
-- Restore on disable/unload
vim.wo[win].wrap = saved_wrap
```

**Potential Applications**:
- Any feature that temporarily modifies window options (conceallevel, foldmethod, etc.)
- Mode-dependent rendering that changes window behavior in insert vs normal mode
- Buffer-specific vim option overrides that need clean restoration

### 4. Width-Constrained Rendering Helper

**Location**: `lua/render-markdown/lib/env.lua:108-115`

The `env.win.width()` helper was modified to return `min(actual_width, reader_width)`, constraining all element rendering calculations.

**Technique**: Centralized width calculation that all renderers call instead of directly accessing window width.

**Potential Applications**:
- Responsive rendering that adapts to window size (e.g., simplifying UI in narrow windows)
- Maximum width constraints for specific element types (e.g., limiting code blocks to 120 chars)
- Breakpoint-based rendering (different styles for narrow/medium/wide windows)

### 5. Virtual Line Text Wrapping Algorithm

**Location**: `lua/render-markdown/render/markdown/paragraph.lua:180-245`

Implemented a custom text wrapping algorithm that:
- Wraps at word boundaries (respecting `linebreak` semantics)
- Handles indentation on wrapped lines
- Integrates with markdown-specific considerations (inline code spans, links)

While vim's native wrapping is usually sufficient, this shows how to implement custom wrapping logic when needed.

**Potential Applications**:
- Justified text rendering (distributing spaces for flush right margin)
- Smart wrapping that avoids breaking within inline code or link text
- Custom wrapping for non-standard element types (e.g., keeping key-value pairs together in YAML frontmatter)

### 6. Per-Window Rendering State

**Location**: `lua/render-markdown/core/ui.lua:108`

Pattern for tracking rendering state per-window (not per-buffer) to handle split window scenarios where the same buffer appears in multiple windows of different sizes.

**Key Pattern**: Using `vim.wo[win]` for window-local state rather than buffer-local state.

**Potential Applications**:
- Any feature that needs to render differently based on window dimensions
- Adaptive detail levels (more detail in larger windows, simplified in smaller windows)
- Window-specific UI preferences (one window in "focus mode", another in "full detail mode")

---

## Lessons Learned

1. **Choose the Right Abstraction Level**: Window management problems are better solved at the window level (like no-neck-pain.nvim) than the rendering level. render-markdown.nvim should focus on *what* to render, not *where* in the window.

2. **Fight Vim's Defaults Sparingly**: The REQ-RW-003 failure (text wrapping at reader_width boundary) stemmed from fighting vim's fundamental assumption that wrapping happens at window width. Working with vim's primitives (like no-neck-pain does) is more maintainable.

3. **Complexity Budget**: 3000+ lines of changes for a feature that can be achieved with ~500 lines of window management code suggests the wrong approach. Always evaluate if there's a simpler solution at a different level of abstraction.

4. **Separation of Concerns**: Mixing window layout concerns (centering, width constraint) with content rendering (markdown styling) created tight coupling and made the codebase harder to reason about.

5. **Integration Testing is Critical**: The text wrapping issue (REQ-RW-003) would have been caught earlier with better automated integration tests that verify actual window behavior, not just internal state.
