-- test_rapid_scroll.lua
-- Test that rapid scrolling eventually renders correctly (trailing-edge debounce)
-- Run: nvim --headless -u test_rapid_scroll.lua

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
vim.opt.columns = 100
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

-- Use default debounce (100ms) to test real behavior
require("render-markdown").setup({
    anti_conceal = { enabled = false },
})

local function get_overlay_info(buf, ns, row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
    local full_line_width = nil
    local individual_count = 0

    for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_text_pos == "overlay" and details.virt_text then
            local width = 0
            for _, chunk in ipairs(details.virt_text) do
                width = width + vim.fn.strdisplaywidth(chunk[1] or "")
            end
            if width > 10 then
                full_line_width = width
            else
                individual_count = individual_count + 1
            end
        end
    end

    return full_line_width, individual_count
end

vim.schedule(function()
    local ok, err = pcall(function()
        vim.cmd("edit demo/wide_table.md")
        vim.cmd("normal! 30G")
        vim.wait(500)

        local buf = vim.api.nvim_get_current_buf()
        local ui = require("render-markdown.core.ui")
        local ns = ui.ns

        print("=== RAPID SCROLL TEST (Trailing-Edge Debounce) ===\n")

        local test_row = 30  -- "short" row

        -- Initial state
        print("=== STEP 1: Initial state (leftcol=0) ===")
        local width, count = get_overlay_info(buf, ns, test_row)
        print(string.format("Row %d: full_line_width=%s, individual_count=%d",
            test_row, tostring(width), count))

        -- Simulate rapid scrolling - fire multiple WinScrolled events quickly
        print("\n=== STEP 2: Rapid scrolling simulation ===")
        print("Firing 10 scroll events in quick succession...")

        local scroll_positions = { 5, 10, 15, 20, 25, 30, 35, 40, 45, 50 }

        for i, pos in ipairs(scroll_positions) do
            vim.fn.winrestview({ leftcol = pos })
            vim.cmd("doautocmd WinScrolled")
            -- Small delay to simulate rapid but not instant scrolling
            vim.wait(10)
            print(string.format("  [%d] Set leftcol=%d, triggered WinScrolled", i, pos))
        end

        -- Check state immediately after rapid scroll (should be inconsistent)
        print("\n=== STEP 3: State immediately after rapid scroll ===")
        local current_leftcol = vim.fn.winsaveview().leftcol
        width, count = get_overlay_info(buf, ns, test_row)
        print(string.format("leftcol=%d, Row %d: full_line_width=%s, individual_count=%d",
            current_leftcol, test_row, tostring(width), count))

        -- Wait for debounce to complete (default is 100ms, wait 200ms to be safe)
        print("\n=== STEP 4: Waiting for debounce (200ms) ===")
        vim.wait(200)

        -- Check final state - should now be correct
        print("\n=== STEP 5: Final state after debounce ===")
        current_leftcol = vim.fn.winsaveview().leftcol
        width, count = get_overlay_info(buf, ns, test_row)
        print(string.format("leftcol=%d, Row %d: full_line_width=%s, individual_count=%d",
            current_leftcol, test_row, tostring(width), count))

        -- Verify all table rows are consistent
        print("\n=== STEP 6: Verify all rows consistent ===")
        local table_rows = { 27, 28, 29, 30 }
        local widths = {}
        local all_full_line = true

        for _, row in ipairs(table_rows) do
            local w, c = get_overlay_info(buf, ns, row)
            widths[row] = w
            if not w or c > 0 then
                all_full_line = false
            end
            print(string.format("Row %d: full_line_width=%s, individual_count=%d",
                row, tostring(w), c))
        end

        -- Check width consistency
        print("\n=== FINAL RESULT ===")

        if not all_full_line then
            print("FAILURE: Not all rows using full-line overlay mode!")
            print("The trailing-edge debounce may not be working correctly.")
        else
            local first_width = widths[table_rows[1]]
            local all_same = true
            for _, w in pairs(widths) do
                if w ~= first_width then
                    all_same = false
                    break
                end
            end

            if all_same then
                print(string.format("SUCCESS: All rows have matching width (%d) after debounce!", first_width))
                print("Trailing-edge debounce is working correctly.")

                -- Verify the width matches expected for leftcol=50
                local expected_width = 124 - 50  -- 74
                if first_width == expected_width then
                    print(string.format("Width %d matches expected (124 - 50 = 74)", first_width))
                else
                    print(string.format("WARNING: Width %d differs from expected %d", first_width, expected_width))
                end
            else
                print("FAILURE: Rows have inconsistent widths!")
                for row, w in pairs(widths) do
                    print(string.format("  Row %d: width=%s", row, tostring(w)))
                end
            end
        end

    end)

    if not ok then
        print("ERROR: " .. tostring(err))
    end

    vim.cmd("cq 0")
end)
