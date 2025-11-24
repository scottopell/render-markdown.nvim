# Reader Width - Technical Design

## Architecture Overview

The `reader_width` feature constrains markdown content to a maximum column width and centers it within the window for improved readability. The implementation uses two coordinated mechanisms:

1. **Window Options** (via `win_options` config) - Controls text wrapping behavior
2. **Centering Mechanism** (via `breakindentopt`) - Shifts all content horizontally
3. **Element Rendering** (via virtual text padding) - Adds additional margins to specific elements

## Data Flow

```
User Config (reader_width = 80)
  ↓
Config System (lib/config.lua)
  ├→ Sets win_options (wrap, linebreak, breakindent) if reader_width > 0
  └→ Passes reader_width to rendering context
      ↓
UI Update (core/ui.lua)
  ├→ Applies window options to all windows
  └→ Calculates center_offset = (window_width - reader_width) / 2
      └→ Sets breakindentopt = 'shift:{center_offset}'
          ↓
Renderers (render/markdown/*.lua)
  └→ Add user-configured margins (NOT center_offset)
      └→ Render elements with virtual text padding
```

## Component Interactions

### 1. Configuration (lib/config.lua:60-77)

When `reader_width > 0`, the config system automatically adds window options for text wrapping:

```lua
if config.reader_width and config.reader_width > 0 then
    self.win_options = vim.tbl_deep_extend('force', self.win_options, {
        wrap = { default = vim.o.wrap, rendered = true },
        linebreak = { default = vim.o.linebreak, rendered = true },
        breakindent = { default = vim.o.breakindent, rendered = true },
    })
end
```

**Purpose:** Enable soft word-wrapping so long lines wrap at word boundaries within the constrained width.

### 2. Center Offset Calculation (lib/env.lua:273-284)

```lua
function M.win.center_offset(win, reader_width)
    if reader_width <= 0 then
        return 0
    end
    local infos = vim.fn.getwininfo(win)
    local textoff = #infos == 1 and infos[1].textoff or 0
    local window_width = vim.api.nvim_win_get_width(win) - textoff
    if window_width > reader_width then
        return math.floor((window_width - reader_width) / 2)
    end
    return 0
end
```

**Key behaviors:**
- Returns 0 if `reader_width` disabled (≤ 0)
- Returns 0 if window narrower than `reader_width` (graceful degradation)
- Subtracts `textoff` (sign column, line numbers, etc.) for accurate calculation
- Uses floor() for integer column offset

### 3. Window Option Application (core/ui.lua:112-121)

```lua
-- Add dynamic breakindentopt when reader_width is enabled
if render and self.config.reader_width and self.config.reader_width > 0 then
    local center_offset = env.win.center_offset(win, self.config.reader_width)
    if center_offset > 0 then
        env.win.set(win, 'breakindentopt', 'shift:' .. center_offset)
    end
elseif not render then
    -- Restore default breakindentopt when not rendering
    env.win.set(win, 'breakindentopt', vim.o.breakindentopt)
end
```

**How `breakindentopt shift:` works:**
- Vim's `breakindentopt` with `shift:N` adds N columns of padding to ALL lines
- This includes both real text AND virtual text (extmarks)
- Effect: Everything in the window shifts right by `center_offset` columns
- Wrapped lines maintain the same indentation

**Trade-off:** Why use `breakindentopt` instead of per-element padding?
- ✅ Consistent: ALL content shifts uniformly (text, virtual text, UI elements)
- ✅ Efficient: One window option vs. thousands of extmark calculations
- ✅ Simple: Vim handles wrapped line alignment automatically
- ⚠️ Limitation: Applies to entire window, not per-buffer

### 4. Element Renderers (render/markdown/*.lua)

Each renderer (paragraph, heading, code, dash) adds virtual text padding for:
- **User-configured margins** (`left_margin`, `left_pad`)
- **Element-specific padding** (code block padding, heading decorations)

**Implementation Note:** Renderers add `center_offset + user_margin` to their virtual text padding. The `breakindentopt shift:` setting ALSO affects this virtual text, but this is intentional - `breakindentopt` only shifts wrapped portions of lines, so the virtual text padding provides the initial offset for the first line.

## Renderer Support Matrix

Different markdown element renderers have varying levels of support for `reader_width` centering:

| Renderer | Centering Support | Implementation | Config Option | Status |
|----------|-------------------|----------------|---------------|--------|
| **Paragraph** | ✅ Yes | `center_offset + user_margin` virtual text padding | `paragraph.left_margin` | REQ-RW-005, REQ-RW-010 |
| **Heading** | ✅ Yes | `center_offset + user_margin` in box calculation | `heading.left_margin` | REQ-RW-005 |
| **Code** | ✅ Yes | `center_offset + user_margin` in data setup | `code.left_margin` | REQ-RW-005 |
| **Dash** | ✅ Yes | `center_offset + user_margin` in setup | `dash.left_margin` | REQ-RW-005 |
| **List/Bullet** | ❌ No | Only has `left_pad` (inline padding), no margin support | `bullet.left_pad` | **Gap** in REQ-RW-005 |
| **Blockquote** | ❌ No | Only overlays `>` markers, no margin mechanism | None | **Gap** in REQ-RW-005 |
| **Table** | ⏭️ Planned | Should NOT be constrained (preserve structure) | N/A | REQ-RW-005 exception |

**Key Findings:**

1. **Working Elements (4/6):** Paragraph, heading, code, and dash renderers all support centering via the `left_margin` configuration option, which allows them to add `center_offset` padding.

2. **Missing: Lists** - The `bullet.lua` renderer only has `left_pad` which adds inline padding around the bullet icon, not margin padding at the start of the line. To support centering, lists would need a `left_margin` config option and modification to add virtual text padding at column 0.

3. **Missing: Blockquotes** - The `quote.lua` renderer only overlays the `>` marker with an icon. It has no margin mechanism at all. Supporting centering would require adding virtual text padding similar to paragraphs.

4. **Paragraph margin=0 Bug (Fixed):** The paragraph renderer was incorrectly skipping rendering when both `left_margin=0` and `indent=0`, even when `reader_width` was enabled. This prevented centering from working. Fixed in `paragraph.lua:27` by checking if `reader_width > 0` before skipping. (REQ-RW-010)

## Width Constraint Implementation

Width constraint (REQ-RW-001) is enforced via:

1. **Text wrapping** (`wrap`, `linebreak`) - Long lines wrap at `reader_width`
2. **Element rendering** - Renderers use `env.win.width(win, reader_width)` which returns `min(window_width, reader_width)`

Example from `env.lua:260-268`:
```lua
function M.win.width(win, reader_width)
    local infos = vim.fn.getwininfo(win)
    local textoff = #infos == 1 and infos[1].textoff or 0
    local window_width = vim.api.nvim_win_get_width(win) - textoff
    if reader_width and reader_width > 0 then
        return math.min(window_width, reader_width)
    end
    return window_width
end
```

This ensures heading backgrounds, code block widths, and horizontal rules don't exceed `reader_width`.

## Window Option Restoration (REQ-RW-006)

**Issue:** How to restore user's original `breakindentopt` when disabling rendering?

**Current approach:**
```lua
elseif not render then
    env.win.set(win, 'breakindentopt', vim.o.breakindentopt)
end
```

**Problem:** `vim.o.breakindentopt` is the GLOBAL default, not the user's buffer-local setting.

**Potential Fix:** Store original value per-buffer:
```lua
-- When first enabling
if not self.original_breakindentopt then
    self.original_breakindentopt = env.win.get(win, 'breakindentopt')
end

-- When disabling
env.win.set(win, 'breakindentopt', self.original_breakindentopt or '')
```

## Performance Considerations (REQ-RW-007)

**Current performance:**
- `center_offset` calculation: O(1) - simple arithmetic
- `breakindentopt` setting: O(1) - single window option
- Element rendering: O(n) where n = visible elements (already exists)

**Impact:** Minimal - reader_width adds negligible overhead beyond existing rendering.

## Edge Cases

### Narrow Windows (REQ-RW-008)
`center_offset()` returns 0 when `window_width <= reader_width`, preventing horizontal scroll.

### Multiple Windows (REQ-RW-009)
`ui.lua:108` loops through `env.buf.wins(self.buf)` and applies settings independently:
```lua
for _, win in ipairs(env.buf.wins(self.buf)) do
    local center_offset = env.win.center_offset(win, self.config.reader_width)
    -- Each window gets its own center_offset based on its width
end
```

## Testing Strategy

**Unit tests** (`tests/reader_width_unit_spec.lua`):
- Test `center_offset()` calculation with various window/reader widths
- Test window option application

**Integration tests** (`tests/reader_width_spec.lua`):
- Verify window options (wrap, linebreak, breakindent) are set when reader_width > 0
- Verify `breakindentopt` contains `shift:` with correct offset
- Verify window option restoration when rendering disabled

**Manual testing:**
- Open markdown file with `reader_width = 80` in wide window (140+ columns)
- Verify content is centered
- Verify long lines wrap at word boundaries
- Resize window and verify re-centering
- Disable rendering (insert mode) and verify restoration

## Requirements Traceability

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| **REQ-RW-001:** Content Width Constraint | ✅ Complete | `env.win.width()` returns `min(window_width, reader_width)` |
| **REQ-RW-002:** Horizontal Centering | ✅ Complete | `breakindentopt shift:N` + `center_offset` virtual text padding |
| **REQ-RW-003:** Text Wrapping | ❌ Not Working | Window options not being applied - text extends beyond window |
| **REQ-RW-004:** Configuration | ✅ Complete | `reader_width` config accepted, default 0 |
| **REQ-RW-005:** Element Coverage | 🟡 Partial | ✅ Paragraph/heading/code/dash centered<br>❌ Lists/blockquotes not centered (no left_margin mechanism)<br>⏭️ Tables exception not implemented |
| **REQ-RW-006:** Window Option Restoration | ✅ Complete | `ui.lua:118-121` restores window options |
| **REQ-RW-007:** Performance | ✅ Complete | O(1) overhead for centering calculation |
| **REQ-RW-008:** Narrow Windows | ✅ Complete | `center_offset()` returns 0 when `window_width <= reader_width` |
| **REQ-RW-009:** Multiple Windows | ✅ Complete | `ui.lua:108` applies settings per-window independently |
| **REQ-RW-010:** Zero Margins | ✅ Complete | `paragraph.lua:27` checks reader_width before skipping |

**Progress:** 4.5 of 10 requirements complete (REQ-RW-003 not working, REQ-RW-005 partial: 4 of 6 element types)

**Architectural Concern:** The current architecture does not elegantly support all requirements. While some requirements appear technically implemented, significant architectural rework is needed to achieve a cohesive, maintainable solution.

## Known Limitations

1. **Text wrapping not working:** Window options (wrap, linebreak, breakindent) are not being applied. Text extends beyond the window without wrapping, even in normal mode. This is a critical bug that prevents comfortable reading.

2. **Lists not centered:** The `bullet.lua` renderer only has `left_pad` (inline padding), not `left_margin` (line-start padding). Supporting centering requires adding `left_margin` config and virtual text padding at column 0.

3. **Blockquotes not centered:** The `quote.lua` renderer only overlays `>` markers. Supporting centering requires adding a margin mechanism similar to paragraphs.

4. **Table exception not implemented:** Tables currently use default rendering. REQ-RW-005 specifies tables should be allowed to exceed `reader_width`, but this isn't explicitly implemented yet.

## Next Steps

1. **FIX CRITICAL BUG:** Debug and fix text wrapping not working (REQ-RW-003)
   - Investigate why window options aren't being applied
   - Verify render conditions are being met in normal mode
   - Test with debug scripts to identify root cause
2. Add `left_margin` support to `bullet.lua` for list centering (REQ-RW-005)
3. Add margin mechanism to `quote.lua` for blockquote centering (REQ-RW-005)
4. Implement table width exception (REQ-RW-005)
5. Add integration tests for element centering verification
