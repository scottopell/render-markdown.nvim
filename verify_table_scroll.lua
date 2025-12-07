-- verify_table_scroll.lua
-- Table Scroll Verification Script for render-markdown.nvim
--
-- Usage: nvim --headless -u verify_table_scroll.lua
--
-- Environment variables:
--   OUTPUT_DIR     - Output directory (default: test_output)
--   TEST_FILE      - Markdown file to test (default: demo/wide_table.md)
--   LEFTCOL_VALUES - Comma-separated scroll positions (default: 0,10,20,30,31,32,33,34,40,50)
--   TARGET_LINE    - Buffer line to check alignment (default: 31, 0-indexed)
--
-- REQ-TSV-001 through REQ-TSV-008 implementation

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

---@class Config
---@field lines integer
---@field columns integer
---@field output_dir string
---@field test_file string
---@field leftcol_values integer[]
---@field target_line integer
local CONFIG = {
    lines = 40,
    columns = 80,
    output_dir = os.getenv("OUTPUT_DIR") or "test_output",
    test_file = os.getenv("TEST_FILE") or "demo/wide_table.md",
    leftcol_values = nil, -- Parsed below
    target_line = tonumber(os.getenv("TARGET_LINE")) or 30, -- "short" row in Mixed Alignment table
}

--- Parse comma-separated integer list from environment variable
---@param var_name string
---@return integer[]|nil
local function parse_env_list(var_name)
    local value = os.getenv(var_name)
    if not value then
        return nil
    end
    local result = {}
    for num in value:gmatch("[^,]+") do
        local n = tonumber(num)
        if n then
            result[#result + 1] = n
        end
    end
    return #result > 0 and result or nil
end

CONFIG.leftcol_values = parse_env_list("LEFTCOL_VALUES") or { 0, 10, 20, 30, 31, 32, 33, 34, 40, 50 }

--------------------------------------------------------------------------------
-- Environment Setup
-- REQ-TSV-008: Run without user interaction
--------------------------------------------------------------------------------

---@param name string
---@return string
local function get_plugin_path(name)
    local data_path = vim.fn.stdpath("data")
    local paths = vim.fs.find(name, { path = data_path })
    if #paths ~= 1 then
        error(string.format("Expected 1 path for %s, found %d in %s", name, #paths, data_path))
    end
    return paths[1]
end

-- Window settings
vim.opt.lines = CONFIG.lines
vim.opt.columns = CONFIG.columns
vim.opt.wrap = false
vim.opt.tabstop = 4

-- Load dependencies (pattern from render-markdown.nvim/tests/minimal_init.lua)
vim.opt.rtp:prepend(get_plugin_path("nvim-treesitter"))
vim.cmd.runtime("plugin/nvim-treesitter.lua")
vim.opt.rtp:prepend(get_plugin_path("mini.nvim"))

-- Load render-markdown from current directory
vim.opt.rtp:prepend(".")
vim.cmd.runtime("plugin/render-markdown.lua")

-- Install treesitter parsers (may already be installed)
local ts_ok, nvim_ts = pcall(require, "nvim-treesitter")
if ts_ok and nvim_ts.install then
    pcall(function()
        nvim_ts.install({ "markdown", "markdown_inline" }):wait()
    end)
end

-- Setup mini.icons
require("mini.icons").setup({})

-- Setup render-markdown with test config
require("render-markdown").setup({
    anti_conceal = { enabled = false },
    win_options = { concealcursor = { rendered = "nvic" } },
})

--------------------------------------------------------------------------------
-- Capture Functions
-- REQ-TSV-003: Capture visual state
-- REQ-TSV-004: Capture extmark state
--------------------------------------------------------------------------------

--- Capture screen output using vim.fn.screenstring()
--- Pattern from render-markdown.nvim/tests/util.lua:actual_screen()
---@return string[]
local function capture_screen()
    vim.cmd("redraw")

    local lines = {}
    for row = 1, vim.o.lines do
        local line = ""
        for col = 1, vim.o.columns do
            line = line .. vim.fn.screenstring(row, col)
        end
        -- Remove trailing whitespace for cleaner output
        line = line:gsub("%s+$", "")
        -- Stop at empty lines (~ indicates end of buffer)
        if line == "~" then
            break
        end
        lines[#lines + 1] = line
    end
    return lines
end

--- Classify extmark type from details
---@param details table
---@return string
local function classify_extmark(details)
    local virt_text_pos = details.virt_text_pos
    if virt_text_pos == "inline" then
        return "inline"
    elseif virt_text_pos == "overlay" then
        return "overlay"
    elseif details.virt_lines then
        return "virtual_lines"
    else
        return "other"
    end
end

--- Calculate display width of virtual text
---@param virt_text table|nil
---@return integer
local function calculate_virt_text_width(virt_text)
    if not virt_text then
        return 0
    end
    local width = 0
    for _, chunk in ipairs(virt_text) do
        if type(chunk[1]) == "string" then
            width = width + vim.fn.strdisplaywidth(chunk[1])
        end
    end
    return width
end

--- Capture all extmarks with detailed information
--- Pattern from render-markdown.nvim/tests/util.lua:actual_marks()
---@param buf integer
---@param ns integer
---@param leftcol integer
---@return table
local function capture_extmarks(buf, ns, leftcol)
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    local result = {
        total = #marks,
        by_type = { inline = 0, overlay = 0, virtual_lines = 0, other = 0 },
        marks = {},
    }

    for _, mark in ipairs(marks) do
        local id, row, col, details = mark[1], mark[2], mark[3], mark[4]

        -- Compute visual position accounting for leftcol
        local visual_col = col - leftcol
        local visible = visual_col >= 0 and visual_col < vim.o.columns

        -- Determine type
        local mark_type = classify_extmark(details)
        result.by_type[mark_type] = (result.by_type[mark_type] or 0) + 1

        -- Calculate display width
        local width = calculate_virt_text_width(details.virt_text)

        result.marks[#result.marks + 1] = {
            id = id,
            row = row,
            col = col,
            end_row = details.end_row,
            end_col = details.end_col,
            type = mark_type,
            details = details,
            computed = {
                visual_col = visual_col,
                visible = visible,
                width = width,
                before_leftcol = col < leftcol,
            },
        }
    end

    return result
end

--- Capture environment metadata
---@return table
local function capture_metadata()
    local version_output = vim.fn.execute("version")
    local nvim_version = version_output:match("NVIM v[%d%.]+[^%s]*") or "unknown"

    -- Get git commit for plugin version
    local git_cmd = "git -C . rev-parse --short HEAD 2>/dev/null"
    local git_version = vim.fn.system(git_cmd):gsub("%s+", "")
    if vim.v.shell_error ~= 0 then
        git_version = "unknown"
    end

    return {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        nvim_version = nvim_version,
        plugin_version = "git:" .. git_version,
        test_file = CONFIG.test_file,
        window = {
            lines = vim.o.lines,
            columns = vim.o.columns,
        },
        config = CONFIG,
    }
end

--------------------------------------------------------------------------------
-- Analysis Functions
-- REQ-TSV-001: Verify row alignment
--------------------------------------------------------------------------------

--- Find first non-whitespace position in line
---@param line string
---@return integer
local function first_nonspace(line)
    local pos = line:find("[^ ]")
    return pos or 0
end

--- Find positions of pipe/border characters in line
---@param line string
---@return integer[]
local function find_pipes(line)
    local positions = {}
    local i = 1
    while i <= #line do
        local char = line:sub(i, i)
        -- Check for single-byte pipe
        if char == "|" then
            positions[#positions + 1] = i
            i = i + 1
        else
            -- Check for multi-byte box drawing characters
            -- UTF-8: │ (0xE2 0x94 0x82), ├ (0xE2 0x94 0x9C), ┤ (0xE2 0x94 0xA4)
            local three = line:sub(i, i + 2)
            if three == "│" or three == "├" or three == "┤" or three == "┬" or three == "┴" then
                positions[#positions + 1] = i
                i = i + 3
            else
                i = i + 1
            end
        end
    end
    return positions
end

--- Check if a line is a table data row (contains │ pipes)
---@param line string
---@return boolean
local function is_data_row(line)
    -- Data rows contain │ (box drawing vertical) as separators
    return line:find("│") ~= nil
end

--- Check if a line is a table border row (contains ├ ┼ ┤ or ┌ ┬ ┐ or └ ┴ ┘)
---@param line string
---@return boolean
local function is_border_row(line)
    return line:find("[├┼┤┌┬┐└┴┘━─]") ~= nil and not is_data_row(line)
end

--- Detect row misalignment by comparing visual column positions
--- Only compares rows of the same type (data rows with data rows)
---@param visual_lines string[]
---@param target_row integer 1-based screen row number
---@return table|nil Error details if misalignment detected
local function detect_row_misalignment(visual_lines, target_row)
    if target_row < 2 or target_row > #visual_lines then
        return nil
    end

    local prev_line = visual_lines[target_row - 1]
    local curr_line = visual_lines[target_row]

    if not prev_line or not curr_line then
        return nil
    end

    -- Only compare data rows with data rows
    local prev_is_data = is_data_row(prev_line)
    local curr_is_data = is_data_row(curr_line)

    if not prev_is_data or not curr_is_data then
        -- Different row types - not a misalignment we care about
        return nil
    end

    -- Check first non-space alignment for data rows
    local prev_col = first_nonspace(prev_line)
    local curr_col = first_nonspace(curr_line)

    if prev_col ~= curr_col and prev_col > 0 and curr_col > 0 then
        return {
            type = "row_shift",
            prev_line_num = target_row - 1,
            curr_line_num = target_row,
            prev_col = prev_col,
            curr_col = curr_col,
            shift_amount = curr_col - prev_col,
        }
    end

    -- Additional check: verify pipe character alignment for data rows
    local prev_pipes = find_pipes(prev_line)
    local curr_pipes = find_pipes(curr_line)

    if #prev_pipes > 0 and #curr_pipes > 0 and #prev_pipes == #curr_pipes then
        for i = 1, #prev_pipes do
            if prev_pipes[i] ~= curr_pipes[i] then
                return {
                    type = "pipe_misalignment",
                    prev_line_num = target_row - 1,
                    curr_line_num = target_row,
                    prev_pipes = prev_pipes,
                    curr_pipes = curr_pipes,
                }
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Baseline Comparison
-- REQ-TSV-006: Show changes between scroll positions
--------------------------------------------------------------------------------

---@param baseline table
---@param current table
---@return table
local function compare_to_baseline(baseline, current)
    local diff = {
        visual_changes = {},
        extmark_changes = {
            added = {},
            removed = {},
            moved = {},
        },
    }

    -- Visual comparison
    for i = 1, math.max(#baseline.visual, #current.visual) do
        local baseline_line = baseline.visual[i] or ""
        local current_line = current.visual[i] or ""
        if baseline_line ~= current_line then
            diff.visual_changes[i] = {
                baseline = baseline_line,
                current = current_line,
            }
        end
    end

    -- Extmark comparison (by row and col)
    local baseline_map = {}
    for _, mark in ipairs(baseline.extmarks.marks) do
        local key = string.format("%d:%d:%s", mark.row, mark.col, mark.type)
        baseline_map[key] = mark
    end

    for _, mark in ipairs(current.extmarks.marks) do
        local key = string.format("%d:%d:%s", mark.row, mark.col, mark.type)
        local baseline_mark = baseline_map[key]

        if not baseline_mark then
            diff.extmark_changes.added[#diff.extmark_changes.added + 1] = mark
        elseif baseline_mark.computed.visual_col ~= mark.computed.visual_col then
            diff.extmark_changes.moved[#diff.extmark_changes.moved + 1] = {
                baseline = baseline_mark,
                current = mark,
                delta = mark.computed.visual_col - baseline_mark.computed.visual_col,
            }
        end

        baseline_map[key] = nil -- Mark as seen
    end

    -- Remaining in baseline_map are removed extmarks
    for _, mark in pairs(baseline_map) do
        diff.extmark_changes.removed[#diff.extmark_changes.removed + 1] = mark
    end

    return diff
end

--------------------------------------------------------------------------------
-- Output Generation
-- REQ-TSV-003, REQ-TSV-004, REQ-TSV-005, REQ-TSV-006
--------------------------------------------------------------------------------

--- Create output directory structure
local function setup_output_dirs()
    local dirs = {
        CONFIG.output_dir,
        CONFIG.output_dir .. "/visual",
        CONFIG.output_dir .. "/extmarks",
        CONFIG.output_dir .. "/diffs",
    }

    for _, dir in ipairs(dirs) do
        vim.fn.mkdir(dir, "p")
    end
end

--- Write visual capture to text file
---@param leftcol integer
---@param visual string[]
---@param analysis table
local function write_visual_output(leftcol, visual, analysis)
    local filename = string.format("%s/visual/leftcol_%03d.txt", CONFIG.output_dir, leftcol)
    local lines = {
        string.format("=== LEFTCOL: %d ===", leftcol),
        string.format("Window: %d lines x %d columns", vim.o.lines, vim.o.columns),
        string.format("Target: Line %d (buffer line, 0-indexed)", CONFIG.target_line),
        "",
        "Screen Output (vim.fn.screenstring):",
        string.rep("─", 80),
    }

    -- Add screen lines with line numbers
    for i, line in ipairs(visual) do
        lines[#lines + 1] = string.format("%2d: %s", i, line)
    end

    lines[#lines + 1] = string.rep("─", 80)
    lines[#lines + 1] = ""

    -- Add analysis
    if analysis.alignment_error then
        lines[#lines + 1] = "ALIGNMENT ERROR DETECTED:"
        lines[#lines + 1] = vim.inspect(analysis.alignment_error)
    else
        lines[#lines + 1] = "Alignment: OK"
    end

    local file = io.open(filename, "w")
    if file then
        file:write(table.concat(lines, "\n"))
        file:close()
    else
        error("Failed to write: " .. filename)
    end
end

--- Write extmark data to JSON file
---@param leftcol integer
---@param extmarks table
local function write_extmarks_output(leftcol, extmarks)
    local filename = string.format("%s/extmarks/leftcol_%03d.json", CONFIG.output_dir, leftcol)

    -- Filter to just target line for detailed view
    local target_line_marks = {}
    for _, mark in ipairs(extmarks.marks) do
        if mark.row == CONFIG.target_line then
            target_line_marks[#target_line_marks + 1] = mark
        end
    end

    local output = {
        leftcol = leftcol,
        total_extmarks = extmarks.total,
        by_type = extmarks.by_type,
        target_line = CONFIG.target_line,
        target_line_extmarks = target_line_marks,
        all_extmarks = extmarks.marks,
    }

    local file = io.open(filename, "w")
    if file then
        file:write(vim.json.encode(output))
        file:close()
    else
        error("Failed to write: " .. filename)
    end
end

--- Write diff to text file
---@param leftcol integer
---@param diff table
local function write_diff_output(leftcol, diff)
    local filename = string.format("%s/diffs/leftcol_%03d_vs_baseline.diff", CONFIG.output_dir, leftcol)

    local lines = {
        string.format("=== Diff: leftcol %d vs baseline (leftcol 0) ===", leftcol),
        "",
        "VISUAL DIFFERENCES:",
    }

    local sorted_changes = {}
    for line_num, _ in pairs(diff.visual_changes) do
        sorted_changes[#sorted_changes + 1] = line_num
    end
    table.sort(sorted_changes)

    for _, line_num in ipairs(sorted_changes) do
        local change = diff.visual_changes[line_num]
        lines[#lines + 1] = string.format("  Line %d:", line_num)
        lines[#lines + 1] = string.format('    Baseline:  "%s"', change.baseline)
        lines[#lines + 1] = string.format('    Current:   "%s"', change.current)
        lines[#lines + 1] = ""
    end

    lines[#lines + 1] = "EXTMARK DIFFERENCES:"
    lines[#lines + 1] = string.format("  Added: %d", #diff.extmark_changes.added)
    lines[#lines + 1] = string.format("  Removed: %d", #diff.extmark_changes.removed)
    lines[#lines + 1] = string.format("  Moved: %d", #diff.extmark_changes.moved)
    lines[#lines + 1] = ""

    if #diff.extmark_changes.moved > 0 then
        lines[#lines + 1] = "  Position Changes:"
        for i, change in ipairs(diff.extmark_changes.moved) do
            lines[#lines + 1] = string.format(
                "    [%d] Row %d, Col %d: %s",
                i,
                change.current.row,
                change.current.col,
                change.current.type
            )
            lines[#lines + 1] = string.format("         Baseline visual_col: %d", change.baseline.computed.visual_col)
            lines[#lines + 1] =
                string.format("         Current visual_col: %d (%+d)", change.current.computed.visual_col, change.delta)
            lines[#lines + 1] = ""
        end
    end

    local file = io.open(filename, "w")
    if file then
        file:write(table.concat(lines, "\n"))
        file:close()
    else
        error("Failed to write: " .. filename)
    end
end

--- Write complete report.json
---@param results table
local function write_report(results)
    local filename = CONFIG.output_dir .. "/report.json"

    -- Simplify captures for JSON (remove full extmark/visual data, keep references)
    local simplified_captures = {}
    for _, capture in ipairs(results.captures) do
        local simplified = {
            leftcol = capture.leftcol,
            is_baseline = capture.is_baseline,
            visual = {
                path = string.format("visual/leftcol_%03d.txt", capture.leftcol),
                line_count = #capture.visual,
            },
            extmarks = {
                path = string.format("extmarks/leftcol_%03d.json", capture.leftcol),
                total = capture.extmarks.total,
                by_type = capture.extmarks.by_type,
            },
            analysis = capture.analysis,
        }

        if capture.diff_from_baseline then
            simplified.diff_from_baseline = {
                path = string.format("diffs/leftcol_%03d_vs_baseline.diff", capture.leftcol),
                visual_changes_count = vim.tbl_count(capture.diff_from_baseline.visual_changes),
                extmark_changes = {
                    added = #capture.diff_from_baseline.extmark_changes.added,
                    removed = #capture.diff_from_baseline.extmark_changes.removed,
                    moved = #capture.diff_from_baseline.extmark_changes.moved,
                },
            }
        end

        simplified_captures[#simplified_captures + 1] = simplified
    end

    local report = {
        metadata = results.metadata,
        test_config = results.test_config,
        captures = simplified_captures,
        summary = results.summary,
    }

    local file = io.open(filename, "w")
    if file then
        file:write(vim.json.encode(report))
        file:close()
    else
        error("Failed to write: " .. filename)
    end

    -- REQ-TSV-002: Provide clear pass/fail summary
    print(string.format("Report written to: %s", filename))
    print(string.format("Tests: %d total, %d passed, %d failed", results.summary.total, results.summary.passed, results.summary.failed))
    if results.summary.critical_leftcol then
        print(string.format("FAIL: Critical failure at leftcol: %d", results.summary.critical_leftcol))
    else
        print("PASS: All scroll positions rendered correctly")
    end
end

--------------------------------------------------------------------------------
-- Test Orchestration
-- REQ-TSV-001, REQ-TSV-007
--------------------------------------------------------------------------------

--- Execute test suite across all leftcol values
---@return table
local function run_tests()
    -- Open test file
    vim.cmd("edit " .. CONFIG.test_file)
    local buf = vim.api.nvim_get_current_buf()

    -- Wait for initial render
    vim.wait(200)

    -- Get render-markdown namespace
    local ui = require("render-markdown.core.ui")
    local ns = ui.ns

    local metadata = capture_metadata()
    local results = {
        metadata = metadata,
        test_config = {
            leftcol_values = CONFIG.leftcol_values,
            target_line = CONFIG.target_line,
        },
        captures = {},
        summary = {
            total = #CONFIG.leftcol_values,
            passed = 0,
            failed = 0,
            failure_points = {},
        },
    }

    local baseline = nil

    -- Test each leftcol value
    for _, leftcol_value in ipairs(CONFIG.leftcol_values) do
        -- Set scroll position
        local view = vim.fn.winsaveview()
        view.leftcol = leftcol_value
        vim.fn.winrestview(view)

        -- Wait for render to settle
        vim.wait(100)
        vim.cmd("redraw")

        -- Capture data
        local visual = capture_screen()
        local extmarks = capture_extmarks(buf, ns, leftcol_value)

        -- Convert target_line (0-indexed buffer) to screen row
        -- This is approximate; assumes target line is visible
        local screen_row = CONFIG.target_line + 1 -- Simple conversion, may need adjustment

        -- Analyze
        local alignment_error = detect_row_misalignment(visual, screen_row)

        local capture = {
            leftcol = leftcol_value,
            is_baseline = (leftcol_value == 0),
            visual = visual,
            extmarks = extmarks,
            analysis = {
                alignment_valid = (alignment_error == nil),
                alignment_error = alignment_error,
            },
        }

        -- Store baseline
        if leftcol_value == 0 then
            baseline = capture
        end

        -- Compare to baseline if not baseline
        if baseline and leftcol_value ~= 0 then
            capture.diff_from_baseline = compare_to_baseline(baseline, capture)
        end

        -- Update summary
        if alignment_error then
            results.summary.failed = results.summary.failed + 1
            results.summary.failure_points[#results.summary.failure_points + 1] = leftcol_value
        else
            results.summary.passed = results.summary.passed + 1
        end

        results.captures[#results.captures + 1] = capture
    end

    -- Identify critical leftcol (first failure)
    if #results.summary.failure_points > 0 then
        results.summary.critical_leftcol = results.summary.failure_points[1]
    end

    return results
end

--------------------------------------------------------------------------------
-- Main Entry Point
-- REQ-TSV-008: Run without user interaction
--------------------------------------------------------------------------------

local function main()
    print("Starting table scroll verification...")
    print(string.format("Output directory: %s", CONFIG.output_dir))
    print(string.format("Test file: %s", CONFIG.test_file))
    print(string.format("Leftcol values: %s", table.concat(CONFIG.leftcol_values, ", ")))

    -- Setup
    setup_output_dirs()

    -- Run tests
    local results = run_tests()

    -- Write outputs
    for _, capture in ipairs(results.captures) do
        write_visual_output(capture.leftcol, capture.visual, capture.analysis)
        write_extmarks_output(capture.leftcol, capture.extmarks)
        if capture.diff_from_baseline then
            write_diff_output(capture.leftcol, capture.diff_from_baseline)
        end
    end

    -- Write master report
    write_report(results)

    print("Verification complete!")

    -- Exit with appropriate code
    local exit_code = results.summary.failed > 0 and 1 or 0
    vim.cmd("cq " .. exit_code)
end

-- Execute after Neovim initialization
vim.schedule(function()
    local ok, err = pcall(main)
    if not ok then
        io.stderr:write("ERROR: " .. tostring(err) .. "\n")
        vim.cmd("cq 1")
    end
end)
