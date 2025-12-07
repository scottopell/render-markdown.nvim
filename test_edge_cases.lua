-- test_edge_cases.lua
-- Test horizontal scroll fix across various edge cases
-- Run: nvim --headless -u test_edge_cases.lua

local function get_plugin_path(name)
    local data_path = vim.fn.stdpath("data")
    local paths = vim.fs.find(name, { path = data_path })
    if #paths >= 1 then
        return paths[1]
    end
    return nil
end

-- Setup
vim.opt.lines = 40
vim.opt.columns = 120
vim.opt.wrap = false

-- Load plugins
local ts_path = get_plugin_path("nvim-treesitter")
if ts_path then
    vim.opt.rtp:prepend(ts_path)
    vim.cmd.runtime("plugin/nvim-treesitter.lua")
end
local mini_path = get_plugin_path("mini.nvim")
if mini_path then
    vim.opt.rtp:prepend(mini_path)
end

vim.opt.rtp:prepend(".")
vim.cmd.runtime("plugin/render-markdown.lua")

require("mini.icons").setup({})
require("render-markdown").setup({
    anti_conceal = { enabled = false },
    debounce = 0,
})

local function get_overlay_widths(buf, ns, rows)
    local widths = {}
    for _, row in ipairs(rows) do
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
        for _, mark in ipairs(marks) do
            local details = mark[4]
            if details.virt_text_pos == "overlay" and details.virt_text then
                local width = 0
                for _, chunk in ipairs(details.virt_text) do
                    width = width + vim.fn.strdisplaywidth(chunk[1] or "")
                end
                if width > 10 then
                    widths[row] = width
                    break
                end
            end
        end
    end
    return widths
end

local function check_alignment(widths, leftcol)
    local values = {}
    for row, width in pairs(widths) do
        table.insert(values, { row = row, width = width })
    end

    if #values < 2 then
        return true, "Not enough rows to compare"
    end

    local first = values[1].width
    for _, v in ipairs(values) do
        if v.width ~= first then
            return false, string.format("Mismatch: row %d has width %d, expected %d", v.row, v.width, first)
        end
    end

    return true, string.format("All %d rows have width %d", #values, first)
end

vim.schedule(function()
    local ok, err = pcall(function()
        vim.cmd("edit demo/wide_table.md")
        vim.wait(500)

        local buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()
        local ui = require("render-markdown.core.ui")
        local ns = ui.ns

        print("=== EDGE CASE TESTS ===\n")

        -- Mixed Alignment table rows
        local table_rows = { 27, 28, 29, 30 }  -- header, delimiter, LLLL, short

        -- Test various leftcol values
        local test_cases = {
            { leftcol = 0, desc = "No scroll" },
            { leftcol = 1, desc = "Minimal scroll" },
            { leftcol = 10, desc = "Small scroll" },
            { leftcol = 33, desc = "Medium scroll (known issue point)" },
            { leftcol = 50, desc = "Large scroll" },
            { leftcol = 100, desc = "Very large scroll" },
            { leftcol = 120, desc = "Near line end" },
        }

        local results = {}

        for _, tc in ipairs(test_cases) do
            vim.fn.winrestview({ leftcol = tc.leftcol })
            ui.update(buf, win, "Test", true)
            vim.wait(100)

            local widths = get_overlay_widths(buf, ns, table_rows)
            local aligned, msg = check_alignment(widths, tc.leftcol)

            results[tc.leftcol] = { aligned = aligned, msg = msg, widths = widths }

            local status = aligned and "PASS" or "FAIL"
            print(string.format("[%s] leftcol=%3d (%s): %s",
                status, tc.leftcol, tc.desc, msg))

            -- Show individual widths for failures
            if not aligned then
                for row, width in pairs(widths) do
                    print(string.format("      Row %d: width=%d", row, width))
                end
            end
        end

        -- Summary
        print("\n=== SUMMARY ===\n")

        local pass_count = 0
        local fail_count = 0
        for _, result in pairs(results) do
            if result.aligned then
                pass_count = pass_count + 1
            else
                fail_count = fail_count + 1
            end
        end

        print(string.format("Passed: %d / %d", pass_count, #test_cases))

        if fail_count > 0 then
            print("\nFailed test cases:")
            for leftcol, result in pairs(results) do
                if not result.aligned then
                    print(string.format("  leftcol=%d: %s", leftcol, result.msg))
                end
            end
        else
            print("\nAll edge cases passed!")
        end

    end)

    if not ok then
        print("ERROR: " .. tostring(err))
    end

    vim.cmd("cq 0")
end)
