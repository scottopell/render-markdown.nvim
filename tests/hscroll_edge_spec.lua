---@module 'luassert'

-- Tests generated from specs/horizontal-scroll.allium via the allium
-- propagate workflow. Each `it` cites the invariant or open question it
-- exercises. The goal is to surface edge cases the hand-written tests in
-- tests/hscroll_spec.lua do not cover.

local util = require('tests.util')

---Proptest-style property testing with random integer sampling.
---Local copy of the helper in tests/hscroll_spec.lua so this file can
---evolve independently without refactoring the original.
---@param opts { iterations?: integer, min?: integer, max?: integer, seed?: integer, critical_range?: integer[] }
---@param setup_fn fun()
---@param property_fn fun(value: integer)
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

    local boundaries = { min_val, min_val + 1, min_val + 2, max_val - 1, max_val }
    for _, val in ipairs(boundaries) do
        local ok, err = pcall(property_fn, val)
        if not ok then
            failures[val] = tostring(err)
        end
    end

    for _ = 1, iterations do
        local val = math.random(min_val, max_val)
        if not failures[val] then
            local ok, err = pcall(property_fn, val)
            if not ok then
                failures[val] = tostring(err)
            end
        end
    end

    for _, val in ipairs(critical_range) do
        if val >= min_val and val <= max_val and not failures[val] then
            local ok, err = pcall(property_fn, val)
            if not ok then
                failures[val] = tostring(err)
            end
        end
    end

    if next(failures) then
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

local CRITICAL_LEFTCOL_RANGE = {}
for i = 30, 40 do
    CRITICAL_LEFTCOL_RANGE[#CRITICAL_LEFTCOL_RANGE + 1] = i
end

describe('horizontal scroll edge cases', function()
    -- =====================================================================
    -- Invariant I1: AllRowsMatchDelimiterWidth (non-ASCII content)
    -- =====================================================================
    describe('I1 - AllRowsMatchDelimiterWidth with non-ASCII', function()
        -- I1 states every row's rendered width equals the delimiter's
        -- rendered width when scrolled. The existing hscroll_spec.lua
        -- covers ASCII tables; these extend the check to double-width
        -- glyphs which depend on display-width measurement (I5).

        local cjk_table = {
            '| English | CJK    | Mixed |',
            '|---------|--------|-------|',
            '| hello   | 日本語 | a日b  |',
            '| world   | 語句   | p語q  |',
        }

        it('holds across leftcol 1..80 with CJK cells (proptest)', function()
            local success, err = proptest_integer(
                { iterations = 50, min = 1, max = 80, critical_range = CRITICAL_LEFTCOL_RANGE },
                function()
                    util.setup.text(cjk_table)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)

        local emoji_table = {
            '| Type   | Icon | Note  |',
            '|--------|------|-------|',
            '| rocket | 🚀   | fast  |',
            '| party  | 🎉   | yay   |',
        }

        it('holds across leftcol 1..60 with emoji cells (proptest)', function()
            local success, err = proptest_integer(
                { iterations = 50, min = 1, max = 60, critical_range = CRITICAL_LEFTCOL_RANGE },
                function()
                    util.setup.text(emoji_table)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)

        local mixed_table = {
            '| ASCII longer    | DW |',
            '|-----------------|----|',
            '| plain text here | 日 |',
            '| another row     | 語 |',
        }

        it('holds with mixed ASCII + double-width in same table (proptest)', function()
            local success, err = proptest_integer(
                { iterations = 50, min = 1, max = 60, critical_range = CRITICAL_LEFTCOL_RANGE },
                function()
                    util.setup.text(mixed_table)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)
    end)

    -- =====================================================================
    -- Invariant I2: DelimColWidthIsMaxCellWidth
    -- =====================================================================
    describe('I2 - DelimColWidthIsMaxCellWidth', function()
        -- I2 states each delim column's width is at least the max cell
        -- display width across all rows. This is verified transitively by
        -- the alignment check (I1): if the delim column were narrower than
        -- a cell, the cell would overflow and I1 would fail. The test
        -- below crafts a table where the dashes are much shorter than the
        -- widest cell to put maximum pressure on the max-width pass.

        local narrow_delim_wide_cells = {
            '| A |',
            '|---|',
            '| this cell is much wider than the delimiter dashes |',
            '| short                                             |',
        }

        it('narrow delimiter with wide cells still aligns when scrolled', function()
            local success, err = proptest_integer(
                { iterations = 50, min = 1, max = 60 },
                function()
                    util.setup.text(narrow_delim_wide_cells)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)
    end)

    -- =====================================================================
    -- Invariant I5: DoubleWidthAware
    -- =====================================================================
    describe('I5 - DoubleWidthAware', function()
        -- I5 says width measurements are display columns not byte length.
        -- Directly exercised by rendering a table whose cells are all
        -- double-width glyphs and checking that overlays exist (would be
        -- dropped or clipped wrong if byte length were used).

        local all_cjk = {
            '| 一 | 二 |',
            '|----|----|',
            '| 三 | 四 |',
            '| 五 | 六 |',
        }

        it('pure CJK table renders overlays at leftcol 0', function()
            util.setup.text(all_cjk)
            util.setup.view({ leftcol = 0 })
            local marks = util.actual_marks()
            assert(#marks > 0, 'pure CJK table should produce marks at leftcol 0')
        end)

        it('pure CJK table aligns when scrolled', function()
            local success, err = proptest_integer(
                { iterations = 30, min = 1, max = 30 },
                function()
                    util.setup.text(all_cjk)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)
    end)

    -- =====================================================================
    -- Open question: header-only table
    -- =====================================================================
    describe('header-only table (open question)', function()
        -- The distill spec flags: table setup may fail when indexing the
        -- last row if there are no data rows. Test that the renderer at
        -- least does not crash on this input.

        local header_only = {
            '| A | B |',
            '|---|---|',
        }

        it('does not crash when rendered unscrolled', function()
            local ok, err = pcall(function()
                util.setup.text(header_only)
                util.setup.view({ leftcol = 0 })
            end)
            assert(ok, ('header-only leftcol=0 crashed: %s'):format(err or ''))
        end)

        it('does not crash when rendered scrolled', function()
            local ok, err = pcall(function()
                util.setup.text(header_only)
                util.setup.view({ leftcol = 5 })
            end)
            assert(ok, ('header-only leftcol=5 crashed: %s'):format(err or ''))
        end)
    end)

    -- =====================================================================
    -- Open question: combining characters
    -- =====================================================================
    describe('combining characters (open question)', function()
        -- e + U+0301 combining acute accent = visually "é". LuaJIT does
        -- not support \u{} escapes, so bytes are written explicitly. The
        -- two trailing bytes \xcc\x81 encode U+0301 in UTF-8.

        local e_acute = 'cafe\xcc\x81'
        local plain = 'naive'
        local combining_table = {
            '| Word  | N |',
            '|-------|---|',
            '| ' .. e_acute .. ' | 1 |',
            '| ' .. plain .. ' | 2 |',
        }

        it('does not crash with combining marks', function()
            local ok, err = pcall(function()
                util.setup.text(combining_table)
                util.setup.view({ leftcol = 0 })
                util.setup.view({ leftcol = 6 })
            end)
            assert(ok, ('combining char crashed: %s'):format(err or ''))
        end)

        it('alignment holds across leftcol 1..40 (proptest)', function()
            local success, err = proptest_integer(
                { iterations = 30, min = 1, max = 40 },
                function()
                    util.setup.text(combining_table)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    util.assert_fullline_widths_equal({ 0, 1, 2, 3 })
                end
            )
            assert(success, err)
        end)
    end)

    -- =====================================================================
    -- Open question: zero-width joiner in cells
    -- =====================================================================
    describe('zero-width joiner (open question)', function()
        -- ZWJ sequences build a single grapheme from multiple emoji. The
        -- family emoji is U+1F468 U+200D U+1F469 U+200D U+1F467 U+200D
        -- U+1F466. Byte sequences are written directly for LuaJIT.
        local zwj = '\xe2\x80\x8d'
        local man = '\xf0\x9f\x91\xa8'
        local woman = '\xf0\x9f\x91\xa9'
        local girl = '\xf0\x9f\x91\xa7'
        local boy = '\xf0\x9f\x91\xa6'
        local family = man .. zwj .. woman .. zwj .. girl .. zwj .. boy

        local zwj_table = {
            '| Label  | Icon |',
            '|--------|------|',
            '| family | ' .. family .. ' |',
            '| plain  | x    |',
        }

        it('does not crash with ZWJ sequence in cell', function()
            local ok, err = pcall(function()
                util.setup.text(zwj_table)
                util.setup.view({ leftcol = 0 })
                util.setup.view({ leftcol = 5 })
            end)
            assert(ok, ('ZWJ sequence crashed: %s'):format(err or ''))
        end)
    end)

    -- =====================================================================
    -- Open question: tabs inside cells
    -- =====================================================================
    describe('tab inside cell (open question)', function()
        -- Display width of a tab depends on the effective tabstop, which
        -- is a vim-level setting not exposed to the spec. The open
        -- question asks whether the renderer handles this gracefully.

        local tab_table = {
            '| A        | B |',
            '|----------|---|',
            '| x\ty     | 1 |',
            '| plain    | 2 |',
        }

        it('does not crash with tab character in cell', function()
            local ok, err = pcall(function()
                util.setup.text(tab_table)
                util.setup.view({ leftcol = 0 })
                util.setup.view({ leftcol = 5 })
            end)
            assert(ok, ('tab in cell crashed: %s'):format(err or ''))
        end)
    end)

    -- =====================================================================
    -- Open question: scroll at pipe boundary
    -- =====================================================================
    describe('scroll offset at pipe boundary (open question)', function()
        -- Ask: is alignment preserved when leftcol lands exactly on a
        -- pipe column? Pipes in the delimiter row below sit at columns
        -- 0, 7, 14, 21.

        local t = {
            '| Col1 | Col2 | Col3 |',
            '|------|------|------|',
            '| a    | b    | c    |',
        }

        it('alignment holds at each pipe column', function()
            util.setup.text(t)
            for _, leftcol in ipairs({ 0, 7, 14, 21 }) do
                util.setup.view({ leftcol = leftcol })
                local ok, err = pcall(util.assert_fullline_widths_equal, { 0, 1, 2 })
                assert(ok, ('leftcol=%d: %s'):format(leftcol, err or ''))
            end
        end)
    end)

    -- =====================================================================
    -- Open question: scroll offset far beyond row width
    -- =====================================================================
    describe('scroll offset beyond row width (open question)', function()
        -- Code guards with `trim_amount < width` but this test verifies
        -- the guard holds at arbitrary extreme offsets up to 2000.

        local t = {
            '| Col1 | Col2 | Col3 |',
            '|------|------|------|',
            '| a    | b    | c    |',
            '| dd   | ee   | ff   |',
        }

        it('does not crash at leftcol 50..2000 (proptest)', function()
            local success, err = proptest_integer(
                { iterations = 50, min = 50, max = 2000 },
                function()
                    util.setup.text(t)
                end,
                function(leftcol)
                    util.setup.view({ leftcol = leftcol })
                    -- Alignment is not asserted here: when the entire
                    -- table is clipped, no overlays are emitted.
                end
            )
            assert(success, err)
        end)

        it('leftcol equal to row width does not crash', function()
            local ok, err = pcall(function()
                util.setup.text(t)
                -- The row '| Col1 | Col2 | Col3 |' is 22 bytes wide.
                util.setup.view({ leftcol = 22 })
            end)
            assert(ok, ('leftcol=width crashed: %s'):format(err or ''))
        end)
    end)

    -- =====================================================================
    -- Open question: table inside list indentation
    -- =====================================================================
    describe('indented table inside list (open question)', function()
        -- Tree-sitter may or may not parse an indented table as a table
        -- node. Either way the renderer should not error.

        local t = {
            '- list item',
            '',
            '  | Col1 | Col2 |',
            '  |------|------|',
            '  | a    | b    |',
        }

        it('does not crash at leftcol 0 or 10', function()
            local ok, err = pcall(function()
                util.setup.text(t)
                util.setup.view({ leftcol = 0 })
                util.setup.view({ leftcol = 10 })
            end)
            assert(ok, ('indented table crashed: %s'):format(err or ''))
        end)
    end)

    -- NOTE: Rules VII-X of the spec (debounce leading+trailing edge state
    -- machine) are intentionally not propagated into tests here. Exercising
    -- them reliably requires a controllable clock / async harness that the
    -- existing plenary+busted setup does not expose. Cases that would go
    -- here if such a harness existed:
    --   - rapid scroll during debounce window (trailing-edge coalescing)
    --   - window resize during debounce window (stale width)
    --   - insert mode entered mid-debounce (render_modes mismatch)
end)
