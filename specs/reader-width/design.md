# Reader Width - Technical Design

## Status: REQ-RW-003 Not Yet Achieved

**CRITICAL:** This document describes two architectural approaches attempted for `reader_width`. **Neither approach fully achieves REQ-RW-003** (text wrapping at reader_width boundary). Both achieve left-side centering and window option management, but neither constrains where text wraps.

**The Fundamental Problem:** Vim's `wrap` option wraps text at the **window width**, not at an arbitrary column width like `reader_width=80`. The current implementations only add left-side padding for centering but have no mechanism to constrain the right edge where wrapping occurs.

**What Works:**
- ✅ Left-side centering (content shifts right via breakindentopt + virtual text)
- ✅ Window options management (wrap, linebreak, breakindent)
- ✅ Element rendering with constrained widths (headings, code blocks)

**What Doesn't Work:**
- ❌ Text wrapping at reader_width boundary (wraps at window edge instead)
- ❌ Right-side constraint mechanism (no way to limit text width to 80 chars in 200-char window)

## Architecture Overview

The `reader_width` feature attempts to constrain markdown content to a maximum column width and center it within the window for improved readability. The implementation uses three coordinated mechanisms:

1. **Window Options** (managed in `state.lua` + `core/ui.lua`) - Controls text wrapping behavior
2. **Centering Mechanism** (via `breakindentopt`) - Shifts all content horizontally
3. **Element Rendering** (via virtual text padding) - Adds additional margins to specific elements

## Architectural Attempts and Failures

Two architectural approaches have been attempted. Both achieve left-side centering but **neither achieves text wrapping at the reader_width boundary** (REQ-RW-003).

### Architecture 1: Render-State-Coupled (Original)

**Approach:**
- Window options (wrap, linebreak, breakindent) dynamically added to `config.win_options` when `reader_width > 0`
- Options captured from global `vim.o.*` at config creation time (in `lib/config.lua:60-77`)
- Options applied/restored based on render state (`rendered` vs `default`) in `core/ui.lua:108-111`
- Coupled to insert/normal mode: options toggled based on whether rendering was active

**Implementation (REMOVED):**
```lua
-- In lib/config.lua:60-77
if config.reader_width and config.reader_width > 0 then
    self.win_options = vim.tbl_deep_extend('force', self.win_options, {
        wrap = { default = vim.o.wrap, rendered = true },
        linebreak = { default = vim.o.linebreak, rendered = true },
        breakindent = { default = vim.o.breakindent, rendered = true },
    })
end
```

**What It Achieved:**
- ✅ Window options applied when rendering enabled
- ✅ Options restored when rendering disabled

**Why It Failed:**
1. **Timing Issue:** Captured global `vim.o.*` defaults at config creation (too early), not actual window-local values when rendering first starts
2. **Mode Coupling:** Options tied to render state, so they toggled off in insert mode (when rendering disabled)
3. **Shared State:** All windows got same captured defaults, ignoring per-window settings
4. **Still No Width Constraint:** Even when wrap was enabled, it wrapped at window edge, not reader_width

**Root Cause of REQ-RW-003 Failure:** Vim's `wrap` option wraps at window width, not at reader_width, regardless of when or how it's set.

### Architecture 2: Render-State-Decoupled (Current)

**Approach:**
- Window options managed independently of render state
- State tracking in `state.lua`: per-buffer `window_options` stores captured global defaults
- New function `M.apply_window_options(buf, config)` in `core/ui.lua` manages lifecycle
- Capture global `vim.o.*` on first render per buffer (better timing)
- Options stay on regardless of insert/normal mode (decoupled from render state)
- `breakindentopt` also decoupled from render state for consistent wrapped line alignment

**Implementation (CURRENT):**
```lua
-- In state.lua:26-34
---@class render.md.WindowOptions
---@field captured boolean
---@field wrap boolean
---@field linebreak boolean
---@field breakindent boolean

---@private
---@type table<integer, render.md.WindowOptions>
M.window_options = {}

-- In core/ui.lua:37-73
function M.apply_window_options(buf, config)
    local reader_width = config.reader_width or 0

    if reader_width > 0 then
        -- Capture global defaults on first enable
        if not state.window_options[buf] then
            state.window_options[buf] = {
                captured = true,
                wrap = vim.o.wrap,
                linebreak = vim.o.linebreak,
                breakindent = vim.o.breakindent,
            }
        end

        -- Apply reader_width window options to all windows
        for _, win in ipairs(env.buf.wins(buf)) do
            env.win.set(win, 'wrap', true)
            env.win.set(win, 'linebreak', true)
            env.win.set(win, 'breakindent', true)
        end
    elseif state.window_options[buf] and state.window_options[buf].captured then
        -- Restore original values when reader_width disabled
        local original = state.window_options[buf]
        for _, win in ipairs(env.buf.wins(buf)) do
            env.win.set(win, 'wrap', original.wrap)
            env.win.set(win, 'linebreak', original.linebreak)
            env.win.set(win, 'breakindent', original.breakindent)
        end
        state.window_options[buf] = nil
    end
end

-- Called in Updater:run() before render decision (core/ui.lua:141)
M.apply_window_options(self.buf, self.config)
```

**What It Achieves:**
- ✅ Better timing: Captures defaults on first render, not at config creation
- ✅ Decoupled from mode: Options stay on in insert mode
- ✅ Better restoration: Restores captured global defaults (as per user preference)
- ✅ Consistent wrapping: `breakindentopt` stays on in insert mode too

**Why It Still Fails REQ-RW-003:**
1. **Fundamental Vim Limitation:** Vim's `wrap` option wraps at window width, NOT at reader_width
2. **No Right-Side Constraint:** Only left-side padding exists (for centering), no mechanism to constrain right edge
3. **Example:** With `reader_width=80` in 200-column window:
   - Left padding: 60 columns (centers the 80-char area)
   - Text wrapping: Occurs at column 200 (window edge)
   - Result: Text spans from column 60 to 200 (140 chars), not 60 to 140 (80 chars)

**Architecture Comparison:**

| Aspect | Architecture 1 (Original) | Architecture 2 (Current) |
|--------|---------------------------|--------------------------|
| Capture timing | ❌ Config creation (too early) | ✅ First render (correct) |
| Insert mode behavior | ❌ Options toggle off | ✅ Options stay on |
| Restoration | ❌ Wrong values (global at wrong time) | ✅ Correct values (captured at first render) |
| Code location | config.lua (wrong place) | state.lua + ui.lua (correct place) |
| **REQ-RW-003** | ❌ **Fails** (wraps at window edge) | ❌ **Still fails** (wraps at window edge) |

**Conclusion:** Architecture 2 is better engineered (correct timing, proper decoupling, cleaner code), but **neither architecture achieves text wrapping at reader_width boundary**. This is a fundamental Vim limitation, not an implementation bug.

## Data Flow (Architecture 2 - Current)

**Note:** This flow achieves left-side centering and window option management, but does NOT achieve width-constrained wrapping (text still wraps at window edge).

```
User Config (reader_width = 80)
  ↓
Config System (lib/config.lua)
  └→ Stores reader_width value
  └→ NOTE: No longer dynamically adds win_options (Architecture 1 removed)
      ↓
UI Update (core/ui.lua:141)
  ├→ Calls M.apply_window_options(buf, config) BEFORE render decision
  │   ├→ If reader_width > 0:
  │   │   ├→ Capture vim.o.* to state.window_options[buf] (first time only)
  │   │   └→ Set wrap=true, linebreak=true, breakindent=true for all windows
  │   └→ If reader_width = 0 and was enabled:
  │       └→ Restore captured defaults, clear state.window_options[buf]
  │
  ├→ Determines if rendering should occur (line 144-147)
  │
  └→ For each window (line 150):
      ├→ Apply non-reader_width window options based on render state (lines 151-157)
      └→ If reader_width > 0 (independent of render state, line 160):
          ├→ Calculate center_offset = (window_width - reader_width) / 2
          └→ Set breakindentopt = 'shift:{center_offset}'
              ↓
Renderers (render/markdown/*.lua)
  └→ Add user-configured margins (NOT center_offset)
      └→ Render elements with virtual text padding

Result: Content centered on left side, but wraps at window edge (not reader_width)
```

## Component Interactions

### 1. Configuration (lib/config.lua:60-77) - REMOVED IN ARCHITECTURE 2

**Architecture 1 Implementation (REMOVED):**

This code dynamically added window options to `config.win_options` when `reader_width > 0`:

```lua
if config.reader_width and config.reader_width > 0 then
    self.win_options = vim.tbl_deep_extend('force', self.win_options, {
        wrap = { default = vim.o.wrap, rendered = true },
        linebreak = { default = vim.o.linebreak, rendered = true },
        breakindent = { default = vim.o.breakindent, rendered = true },
    })
end
```

**Why This Was Removed:**
1. **Wrong timing:** Captured `vim.o.*` at config creation (too early), not when rendering first starts
2. **Wrong location:** Config is about configuration, not runtime state management
3. **Coupled to render state:** Options applied/restored based on render state, causing insert mode issues

**Architecture 2 Replacement:**

Window options now managed by:
- **State tracking:** `state.lua:26-34` defines `render.md.WindowOptions` structure
- **Lifecycle management:** `core/ui.lua:41-73` implements `M.apply_window_options(buf, config)`
- **Timing:** Captures `vim.o.*` on first render (correct timing)
- **Decoupling:** Independent of render state (stays on in insert mode)

**Current config.lua (lines 60-61):**
```lua
-- Note: wrap, linebreak, breakindent window options for reader_width are now
-- managed by M.apply_window_options in core/ui.lua, independent of render state
```

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

### 3. Window Option Application (core/ui.lua:37-73, 141, 158-168) - ARCHITECTURE 2

**New Function: M.apply_window_options(buf, config)**

Manages wrap, linebreak, breakindent independently of render state:

```lua
function M.apply_window_options(buf, config)
    local reader_width = config.reader_width or 0

    if reader_width > 0 then
        -- Capture global defaults on first enable (REQ-RW-006)
        if not state.window_options[buf] then
            state.window_options[buf] = {
                captured = true,
                wrap = vim.o.wrap,
                linebreak = vim.o.linebreak,
                breakindent = vim.o.breakindent,
            }
        end

        -- Apply reader_width window options to all windows (REQ-RW-003)
        for _, win in ipairs(env.buf.wins(buf)) do
            env.win.set(win, 'wrap', true)
            env.win.set(win, 'linebreak', true)
            env.win.set(win, 'breakindent', true)
        end
    elseif state.window_options[buf] and state.window_options[buf].captured then
        -- Restore original values when reader_width disabled (REQ-RW-006)
        local original = state.window_options[buf]
        for _, win in ipairs(env.buf.wins(buf)) do
            env.win.set(win, 'wrap', original.wrap)
            env.win.set(win, 'linebreak', original.linebreak)
            env.win.set(win, 'breakindent', original.breakindent)
        end

        -- Clear captured state
        state.window_options[buf] = nil
    end
end
```

**Called in Updater:run() (line 141):**
```lua
-- Apply reader_width window options (wrap, linebreak, breakindent) independent of render state
M.apply_window_options(self.buf, self.config)
```

**Key Improvements over Architecture 1:**
- ✅ Decoupled from render state (stays on in insert mode)
- ✅ Better timing (captures on first render, not config creation)
- ✅ Proper state tracking (per-buffer via state.window_options)
- ✅ Correct restoration (captured values, not stale globals)

**breakindentopt Handling (lines 158-168):**

Also decoupled from render state in Architecture 2:

```lua
-- Add dynamic breakindentopt when reader_width is enabled (REQ-RW-002, REQ-RW-003)
-- This is independent of render state to keep wrapped lines aligned in insert mode
if self.config.reader_width and self.config.reader_width > 0 then
    local center_offset = env.win.center_offset(win, self.config.reader_width)
    if center_offset > 0 then
        env.win.set(win, 'breakindentopt', 'shift:' .. center_offset)
    end
else
    -- Restore default breakindentopt when reader_width disabled (REQ-RW-006)
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
- ⚠️ Limitation: Only shifts left edge, doesn't constrain right edge (text still wraps at window width)

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
| **List/Bullet** | ❌ Broken | Has `left_pad` but no margin support. **Bug:** Bullets misposition on wrapped items (appear at end, left-aligned) | `bullet.left_pad` | **Bug** in REQ-RW-005 |
| **Blockquote** | ❌ Broken | Overlays markers but no margin. **Bug:** Marker renders on wrong line (after content, not at start) | None | **Bug** in REQ-RW-005 |
| **Table** | ⏭️ Planned | Should NOT be constrained (preserve structure) | N/A | REQ-RW-005 exception |

**Key Findings:**

1. **Working Elements (4/6):** Paragraph, heading, code, and dash renderers all support centering via the `left_margin` configuration option, which allows them to add `center_offset` padding.

2. **Broken: Lists** - The `bullet.lua` renderer has a positioning bug: when list items wrap to multiple lines, the bullet marker appears at the end of the wrapped content and is left-aligned (doesn't respect centering). Additionally, lacks `left_margin` config for proper margin support.

3. **Broken: Blockquotes** - The `quote.lua` renderer has a positioning bug: the blockquote marker (▋) renders on the line after the content instead of at the beginning. Root cause: overlay+concealment pattern conflicts with inline virtual text at column 0. Also lacks margin mechanism.

4. **Paragraph margin=0 Bug (Fixed):** The paragraph renderer was incorrectly skipping rendering when both `left_margin=0` and `indent=0`, even when `reader_width` was enabled. This prevented centering from working. Fixed in `paragraph.lua:27` by checking if `reader_width > 0` before skipping. (REQ-RW-010)

### Marker Positioning Bugs

Both list bullets and blockquote markers have positioning bugs when `reader_width` is enabled:

**List Bullet Bug (`bullet.lua`):**
- When list items wrap to multiple lines, the bullet marker appears at the end of the wrapped content
- Bullet is left-aligned instead of respecting the center offset
- Affects wrapped list items only; single-line list items render correctly

**Blockquote Marker Bug (`quote.lua`):**
- Blockquote marker (▋) renders on the line after the blockquote content instead of at the beginning of the line
- Root cause: Using `virt_text_pos = 'inline'` at column 0 with concealment creates positioning conflicts
- Multiple fix approaches attempted (overlay with padding, inline with concealment, line-by-line processing) all failed
- The overlay+concealment pattern used for markers conflicts with inline virtual text positioning

**Common Issue:**
Both bugs stem from attempting to position markers (which use overlay/replacement patterns) in combination with the centering approach (which uses inline virtual text padding at column 0). Working elements (paragraphs, headings, code, dash) don't have markers to reposition, so they avoid this conflict.

## Width Constraint Implementation

**⚠️ CRITICAL LIMITATION:** Width constraint is **only partially** enforced. Element rendering respects `reader_width`, but **text wrapping does not**.

### What Works: Element Rendering Constraint

Renderers use `env.win.width(win, reader_width)` which returns `min(window_width, reader_width)`:

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

**✅ This works for:**
- Heading backgrounds (constrained to `reader_width`)
- Code block widths (constrained to `reader_width`)
- Horizontal rules (constrained to `reader_width`)

### What Doesn't Work: Text Wrapping Constraint

**❌ Statement (line 362) "Long lines wrap at `reader_width`" is FALSE.**

**Reality:** Long lines wrap at **window width**, not at `reader_width`. This is a fundamental Vim limitation.

**Example with reader_width=80 in 200-column window:**
- ✅ Element rendering: Heading background spans columns 60-140 (80 chars, centered)
- ❌ Text wrapping: Paragraph text spans columns 60-200 (140 chars, wraps at window edge)

**Why This Happens:**
1. Vim's `wrap` option wraps at window boundary, not at arbitrary column
2. `breakindentopt shift:N` only adds left padding, doesn't constrain right edge
3. No mechanism exists to create right-side padding/margin via window options

**What REQ-RW-001 Actually Achieves:**
- ✅ Element rendering constraint (headings, code, rules)
- ❌ Text wrapping constraint (paragraphs, lists)
- **Status:** REQ-RW-001 is **partially implemented**

## Window Option Restoration (REQ-RW-006)

**Architecture 2 Implementation:** Window options are now properly captured and restored.

### wrap, linebreak, breakindent Restoration

**State Tracking (state.lua:26-34):**
```lua
---@class render.md.WindowOptions
---@field captured boolean
---@field wrap boolean
---@field linebreak boolean
---@field breakindent boolean

M.window_options = {} -- table<integer, render.md.WindowOptions>
```

**Lifecycle:**

1. **On First Enable (reader_width changes from 0 to > 0):**
   ```lua
   if not state.window_options[buf] then
       state.window_options[buf] = {
           captured = true,
           wrap = vim.o.wrap,          -- Capture global default
           linebreak = vim.o.linebreak,
           breakindent = vim.o.breakindent,
       }
   end
   ```

2. **While Enabled:**
   - Options set to `true` for all windows showing buffer
   - Values remain in `state.window_options[buf]`

3. **On Disable (reader_width changes to 0):**
   ```lua
   local original = state.window_options[buf]
   for _, win in ipairs(env.buf.wins(buf)) do
       env.win.set(win, 'wrap', original.wrap)
       env.win.set(win, 'linebreak', original.linebreak)
       env.win.set(win, 'breakindent', original.breakindent)
   end
   state.window_options[buf] = nil  -- Clear state
   ```

**Design Decision:** Restores **global defaults** (vim.o.*), not window-local values. This was chosen as simpler and acceptable per user requirements.

### breakindentopt Restoration

**Current approach (core/ui.lua:166):**
```lua
else
    -- Restore default breakindentopt when reader_width disabled (REQ-RW-006)
    env.win.set(win, 'breakindentopt', vim.o.breakindentopt)
end
```

**Status:** Restores global default directly (no state tracking needed since restored on every update when reader_width=0).

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

**Status Tracking:** See `@specs/reader-width/executive.md` for requirements traceability, progress tracking, and status summary. This design document focuses on technical implementation details.

## Known Limitations

### 1. **Text Wrapping at Window Edge, Not reader_width (REQ-RW-003 Not Achieved)**

**Status:** Window options ARE being applied correctly, but the fundamental limitation is Vim's wrap behavior.

**The Problem:**
- Vim's `wrap` option wraps text at the **window width**, not at an arbitrary column width
- No window option or extmark mechanism can constrain text wrapping to a specific column
- Current implementation only adds left-side padding (centering), no right-side constraint

**Example:** With `reader_width=80` in 200-column window:
- Content centered: Columns 60-140
- Text wraps at: Column 200 (window edge)
- Result: Text spans 140 characters, not 80

**This is a Fundamental Vim Limitation**, not an implementation bug. Architecture 2 improved window option handling, but neither architecture solves this core issue.

### 2. **Lists Not Centered (REQ-RW-005 Gap)**

The `bullet.lua` renderer only has `left_pad` (inline padding around bullet icon), not `left_margin` (line-start padding).

**To Fix:** Add `left_margin` config option and virtual text padding at column 0, similar to paragraphs.

### 3. **Blockquotes Not Centered (REQ-RW-005 Gap)**

The `quote.lua` renderer only overlays `>` marker with icon. No margin mechanism exists.

**To Fix:** Add virtual text padding mechanism similar to paragraphs.

### 4. **Table Exception Not Implemented (REQ-RW-005 Gap)**

Tables currently use default rendering. REQ-RW-005 specifies tables should be allowed to exceed `reader_width`, but this isn't explicitly handled.

**To Fix:** Add logic to skip width constraint for table renderers.

### 5. **REQ-RW-001 Only Partially Achieved**

Content width constraint works for element rendering (headings, code blocks, rules) but NOT for text wrapping (paragraphs, lists). See "Width Constraint Implementation" section for details.

## Next Steps

### Blocking Issue: REQ-RW-003 Text Wrapping

**Status:** Window options are working correctly (Architecture 2). The issue is a **fundamental Vim limitation**: `wrap` wraps at window width, not reader_width.

**Action Required:** Determine path forward:
1. Is it acceptable to compromise REQ-RW-003? (Allow wrapping at window edge)
2. Should we pursue right-side padding solution? (See "Potential Solutions" section)
3. Should we explore alternative architectures?

**Do not proceed** with remaining gaps until REQ-RW-003 path is determined.

### Lower Priority Gaps (Pending REQ-RW-003 Resolution)

2. **Fix list bullet positioning bug (REQ-RW-005)**
   - Currently: Bullets misposition on wrapped list items (appear at end, left-aligned)
   - Need to resolve marker positioning conflict with inline virtual text
   - Add `left_margin` config support
   - Ensure bullets align with centered content on wrapped lines

3. **Fix blockquote marker positioning bug (REQ-RW-005)**
   - Currently: Marker renders on wrong line (after content instead of at start)
   - Root cause: overlay+concealment conflicts with inline positioning at column 0
   - Need to redesign marker rendering approach for compatibility with centering
   - Add proper margin mechanism

4. **Implement table width exception (REQ-RW-005)**
   - Add logic to skip width constraint for table renderers
   - Preserve table structure when reader_width enabled

5. **Add integration tests**
   - Test list centering
   - Test blockquote centering
   - Test table width exception
   - Test that text wrapping behavior is as-designed (window-edge wrapping with left centering)

## Potential Solutions for REQ-RW-003

This section explores possible approaches to achieve text wrapping at reader_width boundary. **All are experimental** and require research/prototyping.

### Option A: Right-Side Virtual Text Padding

**Concept:** Add invisible virtual text on the right side of lines to create a visual "margin" that prevents text from extending beyond reader_width.

**Approach:**
1. Calculate `right_margin = window_width - reader_width - center_offset`
2. For each line in wrapped content, append virtual text (spaces/invisible chars) on the right
3. This creates a visual barrier, though text can still technically wrap beyond it

**Pros:**
- Doesn't require Vim core changes
- Works with existing wrap mechanism
- Could be applied per-element (paragraphs, lists)

**Cons:**
- Virtual text right-side behavior unpredictable
- May interfere with visual selection, copying
- Difficult to get exact positioning across all content types
- Performance: O(lines) calculation for every render

**Status:** Untested, uncertain feasibility

### Option B: Accept Window-Edge Wrapping as Design

**Concept:** Document that reader_width provides left-side centering and element width constraint, but text wraps at window edge. This is the "reading column" concept: centered narrower column for visual focus, but content may span wider.

**Approach:**
1. Update REQ-RW-003 specification to clarify wrapping happens at window edge
2. Document that users should resize window to match reader_width if they want precise wrapping
3. Focus on other requirements (element centering, REQ-RW-005 gaps)

**Pros:**
- No architectural changes needed
- Architecture 2 is complete for this approach
- Works with Vim's native wrap behavior
- Simpler user mental model

**Cons:**
- Doesn't achieve original vision of width-constrained content
- "Comfortable reading" requires either manual window sizing or accepting wide text

**Status:** Viable, but compromises user requirements

### Option C: Alternative Text Rendering Approach

**Concept:** Instead of relying on Vim's wrap, use a different mechanism:
- Soft-wrap at reader_width using virtual text with newlines?
- Pre-format lines on render to break at reader_width?
- Use concealing to hide text beyond reader_width boundary?

**Approach:** (Requires research)
1. Investigate if virtual text can contain newlines for soft-wrapping
2. Research if content can be pre-formatted during parsing
3. Explore concealing as boundary mechanism

**Pros:**
- Could theoretically achieve precise width constraint
- Doesn't rely on Vim wrap limitations

**Cons:**
- Likely requires significant architectural rework
- Unknown feasibility (virtual text limitations, performance)
- May break selection, copying, editing features
- Complex interaction with actual text content

**Status:** Highly experimental, uncertain feasibility

### Recommended Path Forward

**Option A (Right-Side Padding)** requires prototyping to determine feasibility. If successful, it provides the best user experience without compromising requirements.

If Option A proves infeasible, **Option B (Accept Window-Edge Wrapping)** with updated documentation is the pragmatic choice. Architecture 2 provides a solid foundation for this approach.

**Option C (Alternative Rendering)** should be last resort due to complexity and uncertainty.
