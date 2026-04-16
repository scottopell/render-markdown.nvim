---@module 'luassert'

-- Invariant I7 (specs/horizontal-scroll.allium):
-- A scrolled overlay extmark is anchored at the BYTE offset whose
-- display-column position equals leftcol, not at the byte value of
-- leftcol itself. For ASCII-only rows the two coincide. For rows
-- containing multi-byte glyphs (emoji, CJK) before leftcol they
-- diverge, and passing leftcol directly to nvim_buf_set_extmark
-- anchors the overlay to a buffer byte whose display position is
-- strictly less than leftcol -- neovim then clips the overlay's
-- leading display columns offscreen, producing a visible overlay
-- shifted right by the clipped amount.
--
-- This is a Layer 1 (extmark) test specifically because the bug is
-- invisible at Layer 2: a shifted-and-clipped overlay looks
-- identical on the rendered grid to a correctly-placed overlay.
-- The mark's byte col is the authoritative signal.

local str = require('render-markdown.lib.str')
local util = require('tests.util')

---Locate the full-row overlay mark on a given buffer row. Returns the
---mark's byte col (0-indexed) or nil if no full-row overlay exists
---(e.g., at leftcol=0 or for rows that rendered as a sequence of
---pipe-level overlays instead).
---@param row integer 0-indexed buffer row
---@return integer? byte_col
---@return integer? width
local function full_row_overlay(row)
    local ui = require('render-markdown.core.ui')
    local marks = vim.api.nvim_buf_get_extmarks(
        0,
        ui.ns,
        { row, 0 },
        { row, -1 },
        { details = true }
    )
    for _, m in ipairs(marks) do
        local d = m[4]
        if d.virt_text_pos == 'overlay' and d.virt_text then
            local w = 0
            for _, chunk in ipairs(d.virt_text) do
                w = w + str.width(chunk[1])
            end
            if w > 5 then -- filter single-pipe overlays
                return m[3], w
            end
        end
    end
    return nil, nil
end

describe('horizontal scroll: overlay mark placement (I7)', function()
    -- A table whose data-row cells contain emojis before the scroll
    -- target. ✅ is 3 bytes / 2 display cols (+1 byte of drift each);
    -- ⚠️ is 6 bytes / 2 display cols (+4 bytes of drift each).
    local lines = {
        '| Status | Notes                                         |',
        '|--------|-----------------------------------------------|',
        '| ✅     | plain ascii content filling the rest of column |',
        '| ⚠️     | second row, variation selector adds 4 byte drift|',
        '| ✅ ⚠️  | both present, compounding to 5 bytes of drift  |',
    }

    it('ascii-only row: mark byte col equals leftcol', function()
        util.setup.text(lines)
        util.setup.view({ leftcol = 20, lnum = 1, col = 30 })
        -- Row 0 (header) has no multi-byte content before col 20.
        local mark_col = full_row_overlay(0)
        assert(mark_col, 'expected a full-row overlay on the header')
        assert.equals(20, mark_col, 'ASCII row: byte col should equal leftcol')
    end)

    it('single-emoji row: mark byte col is leftcol + emoji byte drift', function()
        util.setup.text(lines)
        util.setup.view({ leftcol = 20, lnum = 3, col = 30 })
        -- Row 2 source: "| ✅     | plain ascii content..."
        -- ✅ adds 1 byte of drift (3 bytes / 2 display).
        -- Display col 20 lands inside the Notes cell's ASCII content,
        -- so the byte col we want is leftcol + 1.
        local mark_col = full_row_overlay(2)
        assert(mark_col, 'expected a full-row overlay on row 2')
        assert.equals(
            21,
            mark_col,
            ('single-emoji row: expected leftcol+1 byte offset, got %d'):format(mark_col)
        )
    end)

    it('variation-selector emoji row: drift is 4 bytes', function()
        util.setup.text(lines)
        util.setup.view({ leftcol = 20, lnum = 4, col = 30 })
        -- Row 3 source: "| ⚠️     | ..."
        -- ⚠️ adds 4 bytes of drift (6 bytes / 2 display).
        local mark_col = full_row_overlay(3)
        assert(mark_col, 'expected a full-row overlay on row 3')
        assert.equals(
            24,
            mark_col,
            ('⚠️ row: expected leftcol+4 byte offset, got %d'):format(mark_col)
        )
    end)

    it('compound-emoji row: drifts compound', function()
        util.setup.text(lines)
        util.setup.view({ leftcol = 20, lnum = 5, col = 30 })
        -- Row 4 source: "| ✅ ⚠️  | ..."
        -- ✅ = +1 byte, ⚠️ = +4 bytes, total +5.
        local mark_col = full_row_overlay(4)
        assert(mark_col, 'expected a full-row overlay on row 4')
        assert.equals(
            25,
            mark_col,
            ('compound row: expected leftcol+5 byte offset, got %d'):format(mark_col)
        )
    end)

    it('delimiter row: mark byte col equals leftcol (ASCII-only)', function()
        util.setup.text(lines)
        util.setup.view({ leftcol = 20, lnum = 3, col = 30 })
        -- Delim row is all ASCII so byte == display.
        local mark_col = full_row_overlay(1)
        assert(mark_col, 'expected a full-row overlay on the delimiter')
        assert.equals(20, mark_col)
    end)
end)
