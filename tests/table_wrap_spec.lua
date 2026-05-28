---@module 'luassert'

local util = require('tests.util')

---Force a render. setup.text relies on the FileType autocmd to attach
---and render the buffer; under PlenaryBustedFile the autocmd doesn't
---always fire reliably when vim.o.columns has just been changed, so
---tests that depend on a narrow viewport invoke this helper to ensure
---marks are emitted before assertions run.
local function force_render()
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    require('render-markdown.api').render({ buf = buf, win = win })
    vim.wait(0)
end

---Read all extmarks for the buffer and return them as a flat list.
---@return table[]
local function get_marks()
    local ui = require('render-markdown.core.ui')
    return vim.api.nvim_buf_get_extmarks(0, ui.ns, 0, -1, { details = true })
end

---Count extmarks that emit virt_lines (the wrap continuation lines
---and table borders both use this; tests filter further if needed).
---@return integer
local function count_virt_line_marks()
    local n = 0
    for _, mark in ipairs(get_marks()) do
        if mark[4] and mark[4].virt_lines then
            n = n + 1
        end
    end
    return n
end

---Get the overlay extmark text for a given buffer row, joined into a
---single string. Returns nil if the row has no overlay.
---@param row integer
---@return string?
local function overlay_text(row)
    local ui = require('render-markdown.core.ui')
    local marks = vim.api.nvim_buf_get_extmarks(
        0,
        ui.ns,
        { row, 0 },
        { row, -1 },
        { details = true }
    )
    for _, mark in ipairs(marks) do
        local d = mark[4]
        if d and d.virt_text_pos == 'overlay' and d.virt_text then
            local total_w = 0
            local s = ''
            for _, chunk in ipairs(d.virt_text) do
                s = s .. (chunk[1] or '')
                total_w = total_w + vim.fn.strdisplaywidth(chunk[1] or '')
            end
            -- Filter out single-pipe overlays; we want the row overlay.
            if total_w > 5 then
                return s
            end
        end
    end
    return nil
end

---Get the per-virt-line strings for the wrap continuation marks on a
---given row, in the order they appear.
---@param row integer
---@return string[]
local function virt_line_texts(row)
    local ui = require('render-markdown.core.ui')
    local marks = vim.api.nvim_buf_get_extmarks(
        0,
        ui.ns,
        { row, 0 },
        { row, -1 },
        { details = true }
    )
    local result = {} ---@type string[]
    for _, mark in ipairs(marks) do
        local d = mark[4]
        if d and d.virt_lines then
            for _, line in ipairs(d.virt_lines) do
                local s = ''
                for _, chunk in ipairs(line) do
                    s = s .. (chunk[1] or '')
                end
                result[#result + 1] = s
            end
        end
    end
    return result
end

describe('table cell wrap', function()
    it('does not activate when the table fits the window', function()
        -- 80-column window from minimal_init; this short table is well
        -- under that, so wrap should be a no-op.
        util.setup.text({
            '',
            '| A | B |',
            '| - | - |',
            '| 1 | 2 |',
        }, { pipe_table = { cell = 'wrap' } })
        force_render()

        -- The data row has no wrap continuation lines (wrap is a no-op
        -- when the table fits). Borders use virt_lines too, so we
        -- filter to lines that contain a vertical pipe.
        local virt = virt_line_texts(3)
        for _, line in ipairs(virt) do
            assert.is_nil(
                line:find('│', 1, true),
                ('unexpected wrap continuation line: %s'):format(line)
            )
        end
    end)

    it('wraps a long cell into multiple display lines when narrow', function()
        -- Force a narrow viewport so the natural table overflows.
        local saved_columns = vim.o.columns
        vim.o.columns = 30
        local ok, err = pcall(function()
            util.setup.text({
                '',
                '| Name  | Description                                  |',
                '| ----- | -------------------------------------------- |',
                '| alpha | the quick brown fox jumps over the lazy dog  |',
                '| beta  | short                                        |',
            }, { pipe_table = { cell = 'wrap' } })
            force_render()

            -- The data row "alpha" sits on buffer row 3. Expect at
            -- least one wrap continuation line for that row (the long
            -- description doesn't fit in a narrow column budget).
            -- Filter to lines that contain the column-divider pipe;
            -- borders also use virt_lines but contain ─/┌/└ instead.
            local virt = virt_line_texts(3)
            local continuation = {} ---@type string[]
            for _, line in ipairs(virt) do
                if line:find('│', 1, true) then
                    continuation[#continuation + 1] = line
                end
            end
            assert.is_true(
                #continuation >= 1,
                ('expected >= 1 wrap continuation line, got %d'):format(
                    #continuation
                )
            )
        end)
        vim.o.columns = saved_columns
        if not ok then
            error(err)
        end
    end)

    it('preserves pipe alignment across wrap continuation lines', function()
        local saved_columns = vim.o.columns
        vim.o.columns = 30
        local ok, err = pcall(function()
            util.setup.text({
                '',
                '| Name  | Description                                  |',
                '| ----- | -------------------------------------------- |',
                '| alpha | the quick brown fox jumps over the lazy dog  |',
            }, { pipe_table = { cell = 'wrap' } })
            force_render()

            local first = overlay_text(3)
            local virt = virt_line_texts(3)
            -- Display widths of every wrapped line for this row should
            -- be equal, otherwise pipes don't line up vertically.
            local function w(s)
                return vim.fn.strdisplaywidth(s or '')
            end
            local first_w = w(first)
            for i, line in ipairs(virt) do
                local lw = w(line)
                assert.equals(
                    first_w,
                    lw,
                    ('virt line %d width %d != first %d'):format(i, lw, first_w)
                )
            end
        end)
        vim.o.columns = saved_columns
        if not ok then
            error(err)
        end
    end)

    it('falls back to padded behaviour when window is too narrow', function()
        -- 4 cols * MIN_COLUMN_BUDGET (5) + 5 pipes = 25; with columns=20
        -- there is not enough room to satisfy the floor and wrap
        -- declines to activate.
        local saved_columns = vim.o.columns
        vim.o.columns = 20
        local ok, err = pcall(function()
            util.setup.text({
                '',
                '| a | b | c | d |',
                '| - | - | - | - |',
                '| 1 | 2 | 3 | 4 |',
            }, { pipe_table = { cell = 'wrap' } })
            force_render()
            -- Should not crash; should produce some marks (padded
            -- behaviour) and no wrap continuation virt_lines (lines
            -- containing the column-divider pipe) for the data row.
            -- Borders may still appear as virt_lines and are fine.
            for _, line in ipairs(virt_line_texts(3)) do
                assert.is_nil(
                    line:find('│', 1, true),
                    ('unexpected wrap continuation: %s'):format(line)
                )
            end
        end)
        vim.o.columns = saved_columns
        if not ok then
            error(err)
        end
    end)
end)
