-- test_interactive_sim.lua
-- Simulate interactive scrolling with realistic timing
-- Run: nvim --headless -u test_interactive_sim.lua

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

-- Use DEFAULT debounce (not 0) to simulate real usage
require("render-markdown").setup({
    anti_conceal = { enabled = false },
    -- debounce uses default value
})

local function count_overlay_types(buf, ns, row)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
    local full_line = 0
    local individual = 0

    for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.virt_text_pos == "overlay" and details.virt_text then
            local width = 0
            for _, chunk in ipairs(details.virt_text) do
                width = width + vim.fn.strdisplaywidth(chunk[1] or "")
            end
            if width > 10 then
                full_line = full_line + 1
            else
                individual = individual + 1
            end
        end
    end

    return full_line, individual
end

vim.schedule(function()
    local ok, err = pcall(function()
        vim.cmd("edit demo/wide_table.md")
        vim.cmd("normal! 30G")  -- Go to table area
        vim.wait(500)  -- Wait for initial render

        local buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()
        local ui = require("render-markdown.core.ui")
        local ns = ui.ns

        print("=== INTERACTIVE SIMULATION TEST ===\n")
        print("This test simulates interactive scrolling with default debounce.\n")

        local test_row = 30  -- "short" row

        -- Initial state
        print("=== STEP 1: Initial state (leftcol=0) ===")
        local full, indiv = count_overlay_types(buf, ns, test_row)
        print(string.format("Row %d: %d full-line overlays, %d individual overlays", test_row, full, indiv))
        print(string.format("Expected: 0 full-line, multiple individual (using inline padding mode)\n"))

        -- Simulate scroll
        print("=== STEP 2: Scroll to leftcol=33 ===")
        vim.fn.winrestview({ leftcol = 33 })

        -- In interactive mode, WinScrolled would fire here
        -- Simulate it manually since we're in headless
        vim.cmd("doautocmd WinScrolled")

        print("Triggered WinScrolled event")
        print("Waiting for debounce and re-render...")

        -- Wait for debounce (default is usually 100ms or so)
        vim.wait(500)

        -- Check state
        full, indiv = count_overlay_types(buf, ns, test_row)
        print(string.format("\nRow %d: %d full-line overlays, %d individual overlays", test_row, full, indiv))

        if full == 1 and indiv == 0 then
            print("CORRECT: Using full-line overlay mode for horizontal scroll")
        elseif full == 0 and indiv > 0 then
            print("WRONG: Still using individual overlay mode!")
            print("This would cause misalignment when scrolled.")
        else
            print(string.format("UNEXPECTED: %d full-line, %d individual", full, indiv))
        end

        -- Check all table rows for consistency
        print("\n=== STEP 3: Verify all rows are consistent ===")

        local table_rows = { 27, 28, 29, 30 }
        local row_states = {}

        for _, row in ipairs(table_rows) do
            local f, i = count_overlay_types(buf, ns, row)
            local mode = (f == 1 and i == 0) and "FULL-LINE" or
                         (f == 0 and i > 0) and "INDIVIDUAL" or
                         "MIXED"
            row_states[row] = mode
            print(string.format("Row %d: %s", row, mode))
        end

        -- Check consistency
        local all_full_line = true
        for _, state in pairs(row_states) do
            if state ~= "FULL-LINE" then
                all_full_line = false
            end
        end

        print("\n=== FINAL RESULT ===")
        if all_full_line then
            print("SUCCESS: All table rows use full-line overlay mode at leftcol > 0")
            print("This ensures consistent widths and proper alignment.")
        else
            print("FAILURE: Not all rows are using full-line overlay mode")
            print("This can cause visual misalignment when horizontally scrolled.")
        end

        -- Also verify the actual widths
        print("\n=== STEP 4: Verify widths are consistent ===")

        local widths = {}
        for _, row in ipairs(table_rows) do
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

        local width_values = {}
        for row, width in pairs(widths) do
            print(string.format("Row %d: width=%d", row, width))
            width_values[width] = (width_values[width] or 0) + 1
        end

        if vim.tbl_count(width_values) == 1 then
            local w = next(width_values)
            print(string.format("\nAll rows have width %d - ALIGNED!", w))
        else
            print("\nWARNING: Rows have different widths - potential misalignment!")
        end

    end)

    if not ok then
        print("ERROR: " .. tostring(err))
    end

    vim.cmd("cq 0")
end)
