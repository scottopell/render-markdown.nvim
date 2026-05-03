---
created: 2026-05-03
priority: p3
status: done
artifact: documentation in specs/horizontal-scroll.allium
---

## Summary

When scrolled horizontally, scattered table rows can show a leading `<`
character with the rest of the row visually shifted by one cell. This is
neovim's standard `precedes` indicator firing because `leftcol` lands
inside a multi-cell glyph on those specific rows. Not a bug in
render-markdown, tmux, or iTerm2.

## Symptom

In `demo/wide_table.md`'s CJK section at leftcol=49 (also reproduces at
leftcol=14 on other tables in the same file):

- Row 37: renders cleanly
- Row 38: leading `<` followed by row content shifted right one cell
- Row 39: renders cleanly

The affected rows are not predictable from "contains emoji" alone — they
are exactly the rows whose content places a wide glyph across the leftcol
display-column boundary.

## Root cause

When `wrap=off` and `leftcol` falls strictly inside the display range of
a multi-cell glyph (i.e., the glyph's left edge is at a column < leftcol
and its right edge is at a column ≥ leftcol), neovim renders `<` in the
leftmost visible cell to indicate the partial glyph and resumes rendering
from the next character. This is documented behavior of `:set list` /
`listchars precedes:<` and the equivalent default for non-list lines.

Per-character display layout of the relevant rows at leftcol=49:

| Row | Glyph at boundary | Spans display cols | Result |
|---|---|---|---|
| 37 | `リ` | 49-50 | left edge at leftcol → clean |
| 38 | `れ` | 48-49 | right edge at leftcol → `<` |
| 39 | `未` | 49-50 | left edge at leftcol → clean |

Each row has different content before col 49, so the same leftcol value
intersects each row's glyph layout differently. The asymmetry between
rows is just content variation, not a rendering inconsistency.

## How to verify on any file

```sh
nvim --headless -u NONE -c 'edit demo/wide_table.md' -c 'lua
local function chars_at(line_nr)
  local s = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
  local bytes = vim.str_utf_pos(s)
  local col = 0
  for k, sb in ipairs(bytes) do
    local eb = k < #bytes and bytes[k+1]-1 or #s
    local ch = s:sub(sb, eb)
    local w = vim.fn.strdisplaywidth(ch)
    print(string.format("col=[%d..%d] %q", col, col+w-1, ch))
    col = col + w
  end
end
chars_at(38)
' -c qa! 2>&1
```

Find the glyph whose `col=[L..R]` range straddles your leftcol value
strictly (L < leftcol < R+1). That glyph is the one triggering `<`.

## Done

No code change. This task exists so the next person who sees `<` on a
scrolled table row recognizes it as `precedes` and doesn't burn time
investigating the rendering pipeline.

## Not in scope

The original "table looks misaligned after switching tmux windows and
coming back" report is a separate issue and remains open. That bug is
*not* explained by this finding, since `<` would be visible from initial
render — and the original report describes correct rendering before the
switch and broken rendering only after. Tracked elsewhere.
