---
created: 2026-04-21
priority: p3
status: wont-do
artifact: lua/render-markdown/core/manager.lua
resolved: 2026-05-03
---

## Summary

Tables containing variation-selector-16 emoji (⚠️ = U+26A0+U+FE0F)
render with misaligned trailing content when displayed inside tmux.
Originally framed as "tmux window switch causes misalignment" or
"FocusGained re-render needed"; root cause turned out to be tmux's
wcwidth treating VS-16 promoted emoji as 1 cell instead of 2. Not
something we should work around at the plugin layer.

## Final root cause

tmux's UTF-8 parser uses an internal `utf8_width()` function that
returns the EastAsianWidth-derived width for each codepoint. For
sequences like U+26A0 (base) + U+FE0F (variation selector 16), the
correct Unicode 13+ behavior is for VS-16 to promote the base to
emoji presentation = 2 cells. tmux instead returns the base codepoint's
EAW width (U+26A0 has EAW=Narrow, so 1 cell) and ignores the FE0F.

Reproduction without nvim or render-markdown:

```bash
# Inside tmux:
printf 'row1: ✅ end\nrow2: ⚠️ end\nrow3: ❌ end\n'
# row 2 "end" is 1 cell to the left of rows 1 and 3.

# Outside tmux (raw shell):
printf 'row1: ✅ end\nrow2: ⚠️ end\nrow3: ❌ end\n'
# All three "end" align — iTerm2 alone handles VS-16 correctly.
```

Diagnostics that established this:

- `tmux capture-pane -p` showed the underlying codepoints intact in
  tmux's grid (U+26A0 and U+FE0F both stored). The bytes are right;
  the *width metadata* is wrong.
- Identical printf output rendered correctly in raw zsh and incorrectly
  in tmux, isolating the bug to tmux's parser.
- nvim's initial render *almost* looks correct because nvim positions
  every cell with explicit `\033[row;col H` cursor sequences — the
  per-cell repositioning hides the 1-cell drift. After a tmux pane
  switch, tmux's grid replay batches characters with fewer per-cell
  positionings, and the drift becomes visually obvious.

## Upstream state

- [tmux/tmux#3923](https://github.com/tmux/tmux/issues/3923)
  ("[3.4] Variation selector breaks alignment") — **closed**, partial
  fix. Some VS-16 cases improved but the U+26A0 case still misbehaves.
- [tmux/tmux#4855](https://github.com/tmux/tmux/issues/4855)
  ("Emoji causing alignment width issues in scrollback") — **open**
  as of 2026-05-03, last activity 2026-03-02 awaiting requester logs.
  Same root cause class.

No fix expected in tmux 3.5.x. Would need to land in 3.6+ if/when
upstream lands a proper grapheme-cluster width pass over the parser.

## Why we are not fixing this in the plugin

1. The plugin already lays out tables using `vim.fn.strdisplaywidth`,
   which agrees with iTerm2 (2 cells for VS-16). The misalignment is
   not a layout bug — it is tmux drawing fewer cells than the layout
   reserved for the glyph.
2. The only plugin-side approach that *would* mask the bug
   (FocusGained → save view → cursor-dance through every visible row
   → restore) re-positions the cursor on every focus event. That is
   ugly, flickery, allocates lookups per-row, and would fire on every
   tab/window/pane focus change in a session.
3. The misalignment is at most one cell per VS-16 glyph per row. The
   row remains readable; the table border on the far right column is
   the visible artifact.
4. Other terminal-pipeline mismatches (font fallback, rendering
   priority, ambiguous-width settings) all fall into the same class:
   not the plugin's invariant to uphold.

## Practical guidance for users

- If aligned tables under tmux matter, prefer natively-wide emoji
  (EAW=W in Unicode): 🔴 🟡 🟢 🟧 🔶 ✅ ❌ ☑ ☒ . Avoid VS-16
  promoted emoji: ⚠️ ✍️ ☂️ ☕ ❤️ 〽️ etc.
- Outside tmux (or in tmux on a future fix): the layout is correct.
- The misalignment is independent of horizontal scroll — it would
  happen on a non-scrolled wide table just the same. The hscroll
  framing in the original task title was misleading.

## Status

`wont-do` because the bug is upstream and the only plugin-layer
workaround makes the user experience worse than the bug it addresses.
Tracked here for posterity so the next person who sees ⚠️ misalignment
recognizes it as the tmux wcwidth issue and doesn't redo the
debugging path.
