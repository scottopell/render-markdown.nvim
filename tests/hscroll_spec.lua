---@module 'luassert'

local util = require('tests.util')

describe('horizontal scroll', function()
    describe('tables', function()
        local table_md = {
            '| Col1 | Column Two | Col3 |',
            '|------|------------|------|',
            '| a    | data here  | x    |',
            '| bb   | more data  | yy   |',
        }

        it('renders overlays at leftcol 0', function()
            util.setup.text(table_md)
            util.setup.view({ leftcol = 0 })
            -- Verify table overlay marks exist
            local widths = util.get_overlay_widths({ 0, 1, 2, 3 })
            assert(#widths > 0, 'Table should have overlay marks at leftcol 0')
        end)

        it('delimiter row consistent across scroll positions', function()
            util.setup.text(table_md)
            -- Check delimiter row (row 1) overlay width at different positions
            local widths_at_0 = nil
            for _, lc in ipairs({ 0, 5, 10, 15, 20 }) do
                util.setup.view({ leftcol = lc })
                local widths = util.get_overlay_widths({ 1 }) -- delimiter row only
                if lc == 0 then
                    widths_at_0 = widths[1] and widths[1].width
                elseif widths_at_0 and widths[1] then
                    assert.equals(
                        widths_at_0,
                        widths[1].width,
                        ('Delimiter width at leftcol %d differs from leftcol 0'):format(lc)
                    )
                end
            end
        end)
    end)

    describe('code blocks', function()
        local code_md = {
            '```lua',
            'local x = 1',
            'local longer_line = "some text here"',
            '```',
        }

        it('renders at leftcol 0', function()
            util.setup.text(code_md)
            util.setup.view({ leftcol = 0 })
            -- Verify code block marks exist
            local marks = util.actual_marks()
            assert(#marks > 0, 'Code block should have extmarks at leftcol 0')
        end)

        it('renders at leftcol 10', function()
            util.setup.text(code_md)
            util.setup.view({ leftcol = 10 })
            local marks = util.actual_marks()
            assert(#marks > 0, 'Code block should have extmarks when scrolled')
        end)
    end)

    describe('headings', function()
        local heading_md = {
            '# Heading One',
            '',
            '## Heading Two',
        }

        it('renders at leftcol 0', function()
            util.setup.text(heading_md)
            util.setup.view({ leftcol = 0 })
            local marks = util.actual_marks()
            assert(#marks > 0, 'Headings should have extmarks at leftcol 0')
        end)

        it('renders at leftcol 5', function()
            util.setup.text(heading_md)
            util.setup.view({ leftcol = 5 })
            local marks = util.actual_marks()
            assert(#marks > 0, 'Headings should have extmarks when scrolled')
        end)
    end)

    describe('dashes', function()
        local dash_md = {
            'Above the line',
            '---',
            'Below the line',
        }

        it('renders at leftcol 0', function()
            util.setup.text(dash_md)
            util.setup.view({ leftcol = 0 })
            local marks = util.actual_marks()
            -- Filter for marks on line 1 (the dash line, 0-indexed)
            local dash_marks = vim.tbl_filter(function(m)
                return m.row[1] == 1
            end, marks)
            assert(#dash_marks > 0, 'Dash should have extmarks at leftcol 0')
        end)

        it('renders at leftcol 10', function()
            util.setup.text(dash_md)
            util.setup.view({ leftcol = 10 })
            local marks = util.actual_marks()
            local dash_marks = vim.tbl_filter(function(m)
                return m.row[1] == 1
            end, marks)
            assert(#dash_marks > 0, 'Dash should have extmarks when scrolled')
        end)
    end)
end)
