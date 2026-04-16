---@module 'luassert'

-- Regression: at leftcol=111 on demo/newspaper-table.md, data-row
-- overlays should fully cover buffer text so nothing bleeds through on
-- screen. The header row, delimiter, and bottom border were already
-- covered correctly; the bug is that data rows had their overlay
-- clipped too short, exposing fragments from long "Notes" cells (e.g.
-- `No UI indicators for "new content available"` from the REQ-NP-003
-- row).
--
-- Layer 2 per visual-testing/SKILL.md: the bug is what is visible after
-- composition. Layer 1 extmark widths can look plausible while the
-- screen still leaks buffer text through, so we assert against
-- screenstring output via util.actual_screen().

local util = require('tests.util')

describe('horizontal scroll: newspaper-table regression', function()
    it('data rows do not bleed buffer text through overlay at leftcol=111', function()
        util.setup.file('demo/newspaper-table.md')

        -- Pin cursor to a column past leftcol so winrestview does not
        -- clamp leftcol back to keep the cursor visible. Row 110 is
        -- REQ-NP-003 whose "Notes" cell extends well past col 130.
        util.setup.view({
            topline = 106,
            lnum = 110,
            col = 130,
            leftcol = 111,
        })
        assert.equals(
            111,
            vim.fn.winsaveview().leftcol,
            'leftcol was clamped; test setup is not reproducing the scroll'
        )

        local screen = util.actual_screen()

        -- The buffer lines that the overlay is supposed to cover all
        -- contain long "Notes" cell text well past col 111. When the
        -- overlay clips short, fragments like these are visible.
        --
        -- We check for a distinctive substring known to leak from the
        -- REQ-NP-003 row at this scroll position. Using a substring
        -- makes the failure message describe the actual leak rather
        -- than a whole-screen diff.
        local leak = 'No UI indicators for "new content available"'
        local leaking_rows = {} ---@type string[]
        for i, line in ipairs(screen) do
            if line:find(leak, 1, true) then
                leaking_rows[#leaking_rows + 1] = ('row %d: %s'):format(i, line)
            end
        end

        assert.equals(
            0,
            #leaking_rows,
            ('buffer text leaked through data-row overlay (%d row(s)):\n  %s'):format(
                #leaking_rows,
                table.concat(leaking_rows, '\n  ')
            )
        )
    end)
end)
