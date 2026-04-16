---
name: visual-testing
description: Tiered visual testing model for render-markdown.nvim. Picks the right verification layer (buffer, extmarks, screen grid, terminal, image) for rendering bugs and visual regression tests. Use whenever the user mentions rendering glitches, misrendering, overlays looking wrong, screenshots, visual regression, capturing pane output, verifying how something looks when scrolled, or choosing between screenstring, tmux capture-pane, and image-based approaches — even if the word "testing" isn't used.
---

# Visual testing: the layered model

Terminal plugins render through several independent layers. Each test
tool inspects exactly one of them. Picking the wrong layer wastes time:
extmark assertions pass while the screen is broken; screen captures
differ while the underlying state is fine.

**Prefer lower layers.** Lower layers run in-process, are deterministic,
and describe the bug precisely. Higher layers observe more of the stack
but introduce more variance — timing, terminal behaviour, font
rendering — that you usually don't want in an assertion. Use the lowest
layer that can express the bug.

## The layers

| # | Layer           | What it is                                          | Primary tool                                                  |
|---|-----------------|-----------------------------------------------------|---------------------------------------------------------------|
| 0 | **Buffer**      | Raw file text the plugin reads                      | `nvim_buf_get_lines()`                                        |
| 1 | **Intent**      | Extmarks the plugin places (virt_text, conceal, hl) | `nvim_buf_get_extmarks(..., { details = true })`              |
| 2 | **Screen grid** | What nvim renders after composing marks + scroll    | `vim.fn.screenstring(row, col)` / `screenattr` / `screenchar` |
| 3 | **Terminal**    | TUI output as the terminal interprets it            | `tmux capture-pane -p [-e]`                                   |
| 4 | **Pixels**      | The actual rasterized image                         | VHS, real screenshot                                          |

Higher layers observe everything the lower layers observe *plus* more,
but the bug class they catch is specific. A flake at Layer 3 is not a
Layer 2 problem.

## What each layer catches (and misses)

### Layer 0 — Buffer

- **Catches:** wrong source text, buffer mutation bugs.
- **Misses:** everything rendering-related.
- **Use when:** you suspect the plugin is reading the wrong content.

### Layer 1 — Intent (extmarks)

- **Catches:** wrong mark placed, wrong `virt_text` content, wrong
  position, wrong highlight group, wrong priority.
- **Misses:** rendering-time interactions — overlay clipping under
  horizontal scroll, concealment composition, the visible result when
  overlays don't fully cover buffer text, width mismatches that only
  manifest on screen.
- **Use when:** testing the plugin's decision logic. This is cheap and
  precise.
- **Existing helpers in `tests/util.lua`:** `util.assert_marks()`,
  `util.actual_marks()`, `util.get_overlay_widths()`,
  `util.assert_fullline_widths_strict()`,
  `util.get_overlay_chunks()`, `util.assert_overlay_has_highlight()`.

### Layer 2 — Screen grid

- **Catches:** *what the user actually sees*, in screen coordinates.
  Overlay-not-covering bugs, scroll clipping, concealment visibility,
  text-leaks-through-overlay, display-column width on screen.
- **Misses:** cursor position, terminal-specific escape handling, color
  fidelity across terminals, font rendering.
- **Use when:** the visual output is wrong and you can describe what
  should be there. This is the default layer for rendering bugs.
- **Existing helper in `tests/util.lua`:** `util.actual_screen()`
  (wraps `screenstring`, strips trailing whitespace, stops at `~`).
  `util.assert_screen(expected_lines)` compares against a string array.

### Layer 3 — Terminal

- **Catches:** cursor position, escape-sequence correctness, resize
  behavior, TUI contention with other programs.
- **Misses:** pixel-level rendering, font differences.
- **Use when:** you suspect terminal-specific behavior that Layer 2
  genuinely cannot reproduce — a bug that only manifests under tmux, a
  cursor-positioning issue, or verifying what shows up on copy-paste.
- **Tradeoff:** requires a real PTY, which brings timing. Unlike Layer
  2 there is no synchronous render hook available, so waits are
  inherent to this layer. That is not a smell at Layer 3; it is a
  smell at Layer 2.

### Layer 4 — Pixels

- **Catches:** font rendering, Unicode width discrepancies across
  terminals/fonts (emoji, CJK, combining marks as drawn by *this
  font* — independent of `strdisplaywidth`), color fidelity.
- **Misses:** everything internal; requires a human or image diff.
- **Use when:** demonstrating visual work, producing docs/demos,
  checking regressions across terminal emulators. Rarely needed for
  correctness testing.

## Concealment as a separate concern

Concealment is a render-time effect driven by `conceallevel`,
`conceal_lines`, and the plugin's `anti_conceal` config. It fires
between Layer 1 and Layer 2: extmarks request concealment, but what
you see on screen depends on the mode (normal/insert), the cursor
row, and `anti_conceal.enabled`.

Practically:
- A concealment bug that says "the `**` markers are still visible"
  lives at Layer 2. The extmarks are placed; the rendered output is
  wrong.
- A bug that says "concealment is applied in the wrong mode" may
  need to exercise mode transitions, which Layer 2 handles via
  `nvim_cmd` / sending keys before calling `actual_screen()`.
- A bug that says "concealed text appears in copy-paste" is Layer 3
  or 4 — `screenstring` returns the visible grid, which is what got
  copied in the first place.

## Decision flow

```
Bug description mentions...
│
├─ "wrong text is visible" / "something bleeds through" /
│   "overlay doesn't cover" / "concealment not applied"
│       → Layer 2 (screenstring). Default for rendering bugs.
│
├─ "mark is placed wrong" / "highlight group is wrong" /
│   "width computed wrong" / "chunk is missing"
│       → Layer 1 (extmarks). Cheaper and more specific.
│
├─ "cursor ends up in wrong place" / "resize breaks it" /
│   "only happens in tmux" / "copy-paste includes X"
│       → Layer 3 (tmux capture-pane).
│
├─ "emoji renders wrong in terminal X" / "font-specific" /
│   "color looks off"
│       → Layer 4 (VHS / screenshot). Eyeball, not assert.
│
└─ "plugin reads wrong lines"
        → Layer 0 (buffer inspection). Often a symptom of a bug
          elsewhere — don't stop here.
```

## Tool cheatsheet

Every command below is verified against this repo's layout and tool
versions. If you add more, verify them before committing.

### Layer 1 — extmark inspection

From a busted spec (`tests/*_spec.lua`):

```lua
local util = require('tests.util')

util.setup.text({ '| a | b |', '|---|---|', '| 1 | 2 |' })
util.setup.view({ leftcol = 0 })

-- Snapshot assertion — compare against expected MarkInfo array.
util.assert_marks({
    -- ...built via util.marks/util.row helpers
})

-- Inline probing:
local marks = vim.api.nvim_buf_get_extmarks(
    0,
    require('render-markdown.core.ui').ns,
    { 0, 0 },
    { -1, -1 },
    { details = true }
)
```

For scrolled-table overlays specifically, prefer the targeted helpers:

```lua
util.assert_fullline_widths_strict({ 0, 1, 2, 3 })  -- all rows equal width
util.assert_overlay_has_highlight(row, '@markup.strong')  -- chunk exists
```

### Layer 2 — screen grid

```lua
util.setup.text(lines)
util.setup.view({ leftcol = 50 })  -- triggers re-render synchronously

-- Snapshot assertion:
util.assert_screen({
    'first visible line',
    'second visible line',
})

-- Ad hoc probing at a single cell (1-indexed screen coords):
local ch = vim.fn.screenstring(3, 10)

-- Dump the whole screen for eyeballing during development:
print(vim.inspect(util.actual_screen()))
```

`screenstring` returns what is *rendered*, including concealment,
virt_text overlays, and horizontal scroll. Row/col are 1-indexed
**screen** coordinates — after scrolling, buffer col 120 may be at
screen col 10.

**Leftcol clamps to the cursor.** `winrestview({ leftcol = 111 })`
silently resets leftcol to 0 if the cursor is on a line shorter than
111 columns — nvim refuses to scroll the cursor off screen. For
`setup.text` tables this rarely matters because every line is long
enough; for `setup.file` on real documents, pin the cursor to a long
line past your target leftcol:

```lua
util.setup.view({
    topline = 106,   -- first visible buffer row
    lnum    = 110,   -- cursor on a row long enough to not clamp
    col     = 130,   -- cursor past target leftcol
    leftcol = 111,
})
-- Sanity check the setup, not the plugin:
assert.equals(111, vim.fn.winsaveview().leftcol)
```

### Test fixture prerequisites

The busted harness launches with `tests/minimal_init.lua`, which
prepends three plugins to `rtp` by looking them up in nvim's
`stdpath('data')`:

- `nvim-treesitter`
- `mini.nvim`
- `plenary.nvim`

Each must exist under `~/.local/share/nvim/lazy/<plugin>` (or
whichever plugin manager's path your environment uses) before any
busted spec runs. If they are missing, `minimal_init.lua` fails at
the `assert(#plugin_path == 1, 'plugin must have one path')` line
and every test errors out with the same message. Clone missing
plugins into the lazy path — no install step is needed beyond
making them findable on disk.

### Layer 3 — tmux

Full verified flow for an interactive visual check using your normal
nvim config (the test suite's `minimal_init.lua` cannot be launched
outside the plenary harness — it looks up plugins in Neovim's
data_path):

```bash
SESSION=vt_$$

tmux new-session -d -s "$SESSION" -x 120 -y 30
tmux send-keys -t "$SESSION" "nvim demo/newspaper-table.md" Enter
sleep 3                                   # plugin init + treesitter parse

tmux send-keys -t "$SESSION" ":set nowrap" Enter
sleep 0.3
tmux send-keys -t "$SESSION" "110G150|"   # row 110, col 150 → leftcol > 0
sleep 0.3

tmux capture-pane -p -t "$SESSION" > /tmp/capture.txt

tmux send-keys -t "$SESSION" ":qa!" Enter
sleep 0.3
tmux kill-session -t "$SESSION"
```

Useful flags:
- `-p` prints to stdout
- `-e` includes ANSI escape sequences (colors and styles)
- `-S -` captures scrollback history as well as the visible pane
- `-x` / `-y` on `new-session` set pane dimensions; otherwise the
  current window size is used and captures vary across machines.

### Layer 4 — VHS / screenshot

VHS (Charm — https://github.com/charmbracelet/vhs) records terminal
sessions as GIFs or PNGs, driven by a `.tape` file. It is not
installed in this repo's dev environment; install with
`brew install vhs` before using.

Treat Layer 4 output as an artifact for humans — attach to a PR or
an issue for visual review. Do not assert on it.

For one-off captures without VHS, use the terminal's built-in
screenshot (`Cmd+Shift+4` on macOS into iTerm/Kitty/etc) or
`scrot`/`grim` on Linux. Attach the image, describe what is wrong,
move on.

## Worked examples

### Example 1 — `demo/newspaper-table.md` horizontal-scroll glitch

**Symptom:** scrolled to col 111, data-row overlays don't fully cover
buffer text. Stray letters visible on screen where the cell content
should be hidden or overlaid.

**Layer:** 2. The overlays probably exist (Layer 1 test would pass);
the bug is what's *visible* after composition.

**Diagnostic workflow:**

```lua
-- 1. Capture the broken output. Pin the cursor past the target
-- leftcol so nvim does not clamp the scroll (see "Leftcol clamps to
-- the cursor" above). Row 110 in this file is a long data row.
util.setup.file('demo/newspaper-table.md')
util.setup.view({
    topline = 106,
    lnum    = 110,
    col     = 130,
    leftcol = 111,
})
assert.equals(111, vim.fn.winsaveview().leftcol, 'scroll was clamped')
local screen = util.actual_screen()
for i, line in ipairs(screen) do
    print(i, line)
end
-- Eyeball: identify which rows have stray text.

-- 2. If the bug is a specific string leaking through the overlay,
-- write a targeted substring assertion. This produces a failure
-- message that names the exact leaking row rather than dumping the
-- entire screen diff:
local leak = 'No UI indicators for "new content available"'
for i, line in ipairs(screen) do
    assert.is_nil(line:find(leak, 1, true), ('row %d leaked: %s'):format(i, line))
end

-- 3. Once the rendering is stable and correct, a whole-screen
-- snapshot assertion replaces the substring check. Regenerate by
-- printing actual_screen() and pasting the output:
util.assert_screen({
    -- exact expected lines here
})
```

Snapshot assertions are the right answer for stable rendering; the
substring form is the right answer while you are actively chasing a
bug, because the failure message tells you where the leak is. Do
not try to write a regex that matches "bad" vs "good" screens —
rendered output is not a regular language.

### Example 2 — "bold highlight missing from scrolled overlay"

**Layer:** 1. The claim is about a mark's content, not its visual
effect.

```lua
util.setup.text(bold_table_md)
util.setup.view({ leftcol = 5 })
util.assert_overlay_has_highlight(2, '@markup.strong')
```

### Example 3 — "emoji renders wrong width on iTerm but not Alacritty"

**Layer:** 4 only. `strdisplaywidth()` is deterministic across
terminals, so Layers 0-3 all agree. The mismatch is the terminal's
font + Unicode width implementation. Capture images from both
terminals, attach to the issue, eyeball.

## Anti-patterns

- **Asserting extmarks when the bug is on screen.** Common when the bug
  is overlay clipping under horizontal scroll. Marks look fine; screen
  is wrong. Go to Layer 2.
- **Asserting screen content when the bug is the plugin's decision
  logic.** E.g., "bold should produce a `@markup.strong` chunk" — the
  decision happens at Layer 1; screen introspection via
  `screenattr` is brittle across `:hi` configurations.
- **Writing regex to detect "wrong" rendered output.** Rendered screen
  content is not regular. Use snapshot equality; regenerate the
  snapshot when the render legitimately changes.
- **Reaching for tmux by default.** Layer 3 is for bugs that genuinely
  require a PTY. Most "I want to see what it looks like" questions are
  Layer 2.
- **`sleep` in Layer 2 tests.** `util.setup.view()` renders
  synchronously via the test harness's `debounce = 0` config. If you
  think you need sleep, something is wrong with setup. Sleep at
  Layer 3 is different — see that section.
- **Encoding your assumption about a bug as a test.** A test that says
  "if the string X appears on screen, it's a bug" only works if you
  have an independent definition of why X appearing is wrong. Rendered
  output you haven't seen unscrolled before is not a reliable reference
  for what "correct" looks like scrolled.

## Establish the reference before writing the assertion

Before writing a Layer 2 (or any) assertion, you must have a reliable
description of what correct output looks like. Otherwise the test
encodes your guess, not the plugin's contract. Two paths to a
reference:

1. **Capture at the other end of the scroll.** Render the same buffer
   unscrolled, observe what's at display col N, and assert that
   rendered scrolled output at screen col 1 (with any gutter
   accounted for) contains the same characters.

2. **Cross-check against a lower layer.** If your Layer 2 assertion
   boils down to "the plugin's intent for this row was X", assert on
   the intent (Layer 1 — extmarks) directly. Layer 2 bugs that look
   identical to correct output on the grid — e.g., an overlay shifted
   N cols left whose leading N cols fall offscreen and get clipped —
   can only be caught by inspecting byte-level placement. The visible
   grid lies when the rendering pipeline has compensating clips.

If you cannot establish a reference, your bug report is a hypothesis,
not an observation. Investigate at lower layers first.

### Watch for hidden terminal/window gutters

Before reading screen cells at column 1 and assuming you're looking at
the first text column, verify that no gutter (signcolumn, number,
foldcolumn) is occupying the leftmost cells. `signcolumn = 'auto'`
will display for the whole window the moment any sign is placed
anywhere in the buffer, shifting the entire text area right by two
columns. A false "overlay doesn't cover" diagnosis is easy to reach if
you mistake the signcolumn background for an uncovered buffer region.
`vim.o.signcolumn`, `vim.fn.wincol()`, and `vim.fn.screenattr()` let
you distinguish gutter cells from text cells.

## Adding new tests

1. Describe the bug in one sentence.
2. Identify the layer from the decision flow.
3. Write the assertion at that layer using the existing helpers in
   `tests/util.lua`.
4. If no helper exists, add one to `tests/util.lua` first. Do not
   inline extmark or screen probing in specs — the helpers document
   the contract.
5. Verify every command you add to this skill against this repo's
   layout before committing. Outdated or aspirational commands are
   worse than none — they mislead and cost debugging time.
