---@module 'luassert'

local util = require('tests.util')

---Proptest-style property testing with random integer sampling.
---Runs a property function across random values plus boundaries.
---On failure, reports the minimal failing value for easier debugging.
---@param opts { iterations?: integer, min?: integer, max?: integer, seed?: integer, critical_range?: integer[] }
---@param setup_fn fun() Function to set up test state (called once)
---@param property_fn fun(value: integer) Property to test at each value
---@return boolean success
---@return string? error_msg
local function proptest_integer(opts, setup_fn, property_fn)
    opts = opts or {}
    local seed = opts.seed or os.time()
    local iterations = opts.iterations or 100
    local min_val = opts.min or 0
    local max_val = opts.max or 200
    local critical_range = opts.critical_range or {}

    math.randomseed(seed)
    setup_fn()

    local failures = {} ---@type table<integer, string>

    -- Test boundary cases first (most likely to find issues)
    local boundaries = { min_val, min_val + 1, min_val + 2, max_val - 1, max_val }
    for _, val in ipairs(boundaries) do
        local ok, err = pcall(property_fn, val)
        if not ok then
            failures[val] = tostring(err)
        end
    end

    -- Random sampling across the range
    for _ = 1, iterations do
        local val = math.random(min_val, max_val)
        if not failures[val] then -- Skip if already tested
            local ok, err = pcall(property_fn, val)
            if not ok then
                failures[val] = tostring(err)
            end
        end
    end

    -- Test critical range (known problem areas)
    for _, val in ipairs(critical_range) do
        if val >= min_val and val <= max_val and not failures[val] then
            local ok, err = pcall(property_fn, val)
            if not ok then
                failures[val] = tostring(err)
            end
        end
    end

    if next(failures) then
        -- Find minimal failing value (shrinking)
        local min_fail = math.huge
        for val in pairs(failures) do
            min_fail = math.min(min_fail, val)
        end
        local fail_count = vim.tbl_count(failures)
        local error_msg = ('Property failed at %d values. Minimal failing: %d (seed=%d)\nError: %s'):format(
            fail_count,
            min_fail,
            seed,
            failures[min_fail]
        )
        return false, error_msg
    end

    return true, nil
end

-- Critical leftcol range where horizontal scroll bugs were found (30-40)
local CRITICAL_LEFTCOL_RANGE = {}
for i = 30, 40 do
    CRITICAL_LEFTCOL_RANGE[#CRITICAL_LEFTCOL_RANGE + 1] = i
end

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

        it('all rows have equal full-line overlay widths when scrolled (proptest)', function()
            -- When leftcol > 0, tables switch to full-line overlay mode
            -- All rows should have the same overlay width for proper alignment
            local success, err = proptest_integer(
                { iterations = 50, min = 1, max = 150, critical_range = CRITICAL_LEFTCOL_RANGE },
                function()
                    util.setup.text(table_md)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)

        -- Wide table with varying content lengths (more likely to expose alignment bugs)
        local wide_table_md = {
            '| Short | Medium Length | This Is A Much Longer Column Header |',
            '|-------|---------------|--------------------------------------|',
            '| a     | hello world   | LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL |',
            '| bb    | hi            | short                                |',
        }

        it('wide table rows aligned when scrolled (proptest)', function()
            -- Wide tables with varying cell content are more likely to expose alignment bugs
            local success, err = proptest_integer(
                { iterations = 50, min = 1, max = 100, critical_range = CRITICAL_LEFTCOL_RANGE },
                function()
                    util.setup.text(wide_table_md)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
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
