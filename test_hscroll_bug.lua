-- test_hscroll_bug.lua
-- Direct horizontal scroll bug reproduction test
-- Run: nvim -u test_hscroll_bug.lua demo/wide_table.md

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
vim.opt.number = true

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
})

-- Helper functions
local function get_screen_line(row)
    local line = ""
    for col = 1, vim.o.columns do
        line = line .. vim.fn.screenstring(row, col)
    end
    return line:gsub("%s+$", "")
end

local function find_pipe_positions(line)
    local positions = {}
    local i = 1
    while i <= #line do
        local three = line:sub(i, i + 2)
        if three == "│" or three == "├" or three == "┤" or three == "┬" or three == "┴" or three == "┌" or three == "┐" or three == "└" or three == "┘" or three == "┼" then
            positions[#positions + 1] = i
            i = i + 3
        else
            i = i + 1
        end
    end
    return positions
end

local function capture_table_state()
    vim.cmd("redraw")
    vim.wait(50)

    local leftcol = vim.fn.winsaveview().leftcol
    local results = {
        leftcol = leftcol,
        rows = {},
    }

    -- Capture rows 27-32 (the Mixed Alignment table area on screen)
    for screen_row = 27, 32 do
        local line = get_screen_line(screen_row)
        local pipes = find_pipe_positions(line)
        local first_char = line:find("[^ ]") or 0
        results.rows[screen_row] = {
            content = line,
            first_char = first_char,
            pipes = pipes,
        }
    end

    return results
end

local function check_alignment(results)
    local errors = {}

    -- Compare row 30 (LLLL row) with row 31 (short row)
    local row30 = results.rows[30]
    local row31 = results.rows[31]

    if row30 and row31 then
        -- Check first character alignment
        if row30.first_char ~= row31.first_char then
            errors[#errors + 1] = string.format(
                "Row start misalignment: row30 starts at %d, row31 starts at %d",
                row30.first_char,
                row31.first_char
            )
        end

        -- Check pipe alignment
        local min_pipes = math.min(#row30.pipes, #row31.pipes)
        for i = 1, min_pipes do
            if row30.pipes[i] ~= row31.pipes[i] then
                errors[#errors + 1] = string.format(
                    "Pipe #%d misalignment: row30=%d, row31=%d",
                    i,
                    row30.pipes[i],
                    row31.pipes[i]
                )
            end
        end

        if #row30.pipes ~= #row31.pipes then
            errors[#errors + 1] = string.format(
                "Pipe count mismatch: row30=%d, row31=%d",
                #row30.pipes,
                #row31.pipes
            )
        end
    end

    return errors
end

local function print_state(results, label)
    print(string.format("\n=== %s (leftcol=%d) ===", label, results.leftcol))
    print("Row 30: " .. (results.rows[30] and results.rows[30].content:sub(1, 100) or "N/A"))
    print("Row 31: " .. (results.rows[31] and results.rows[31].content:sub(1, 100) or "N/A"))

    if results.rows[30] and results.rows[31] then
        print(string.format("Pipes row30: %s", table.concat(results.rows[30].pipes, ", ")))
        print(string.format("Pipes row31: %s", table.concat(results.rows[31].pipes, ", ")))
    end
end

-- Keymaps for interactive testing
vim.keymap.set("n", "<leader>t", function()
    print("\n========== ALIGNMENT TEST ==========")
    local results = capture_table_state()
    print_state(results, "Current State")
    local errors = check_alignment(results)
    if #errors > 0 then
        print("\n*** ALIGNMENT ERRORS ***")
        for _, err in ipairs(errors) do
            print("  " .. err)
        end
    else
        print("\nAlignment: OK")
    end
end, { desc = "Test alignment" })

vim.keymap.set("n", "<leader>a", function()
    print("\n========== FULL SCROLL TEST ==========")
    local all_errors = {}

    -- Test at various scroll positions using actual scroll commands
    local test_positions = { 0, 10, 20, 30, 33, 40, 50, 60 }

    for _, target in ipairs(test_positions) do
        -- Reset to start
        vim.cmd("normal! 0")
        vim.fn.winrestview({ leftcol = 0 })
        vim.cmd("redraw")

        -- Scroll to target position using zl commands
        if target > 0 then
            vim.cmd("normal! " .. target .. "zl")
        end
        vim.cmd("redraw")
        vim.wait(100)

        local results = capture_table_state()
        print_state(results, "leftcol=" .. target)

        local errors = check_alignment(results)
        if #errors > 0 then
            all_errors[target] = errors
            print("*** ERRORS at leftcol=" .. target .. " ***")
            for _, err in ipairs(errors) do
                print("  " .. err)
            end
        else
            print("OK")
        end
    end

    print("\n========== SUMMARY ==========")
    if vim.tbl_count(all_errors) > 0 then
        print("FAILED: Alignment errors at scroll positions:")
        for pos, _ in pairs(all_errors) do
            print("  - leftcol=" .. pos)
        end
    else
        print("PASSED: All scroll positions aligned correctly")
    end
end, { desc = "Run full alignment test" })

vim.keymap.set("n", "<leader>l", function()
    print("leftcol = " .. vim.fn.winsaveview().leftcol)
end, { desc = "Show leftcol" })

vim.keymap.set("n", "<leader>r", function()
    for name, _ in pairs(package.loaded) do
        if name:match("^render%-markdown") then
            package.loaded[name] = nil
        end
    end
    require("render-markdown").setup({})
    vim.cmd("e")
    print("render-markdown reloaded")
end, { desc = "Reload render-markdown" })

print("=== Horizontal Scroll Bug Test ===")
print("Open demo/wide_table.md and go to line 31")
print("Keymaps:")
print("  <leader>t - Test alignment at current scroll")
print("  <leader>a - Run full alignment test at multiple scroll positions")
print("  <leader>l - Show current leftcol")
print("  <leader>r - Reload render-markdown")
print("  zl/zh    - Scroll horizontally")
print("")
