---@module 'luassert'

-- Tests for the debounced render pipeline (Decorator:schedule +
-- leading + trailing edge) using a controllable fake clock. These
-- close three of the four debounce-related open questions from
-- specs/horizontal-scroll.allium. The fourth (anti-conceal refresh
-- on scroll without cursor move) is not actually clock-gated and
-- is better tested as a separate rendering-flow test if the
-- question turns out to matter.
--
-- Test pattern, for each case:
--
--   1. fake_clock.with() installs a fake clock BEFORE any decorator
--      is created. Buffer state reset via state.setup() wipes any
--      previous decorators, and the fresh decorator created on
--      attach receives a fake uv_timer_t.
--   2. Trigger events (scroll, resize, mode change) that would
--      normally cause a render through the debounced pipeline.
--   3. vim.wait(0) flushes nvim's own scheduler after each event
--      - this runs leading-edge callbacks that decorator:schedule
--      dispatches via vim.schedule.
--   4. Assertions on decorator.n observe how many real renders
--      actually fired: leading fires once, intermediate scrolls
--      are coalesced as `pending`, trailing fires exactly once
--      when the fake clock advances past the debounce window.

local util = require('tests.util')
local fake_clock = require('tests.helpers.fake_clock')

describe('debounce', function()
    local table_md = {
        '| English | Col B | Col C |',
        '|---------|-------|-------|',
        '| one     | two   | three |',
        '| four    | five  | six   |',
    }

    ---Common setup: install fake clock, create a rendered markdown
    ---buffer with a non-zero debounce window, and return the
    ---decorator + bufnr. The leading-edge render from the initial
    ---FileType-triggered attach has already run by the time this
    ---returns; `decorator.n == 1` and `decorator.running == true`
    ---(the trailing timer is still armed at fake-time 100).
    ---@param fc render.md.test.FakeClock
    ---@param opts? render.md.UserConfig
    local function prepare(fc, opts)
        opts = vim.tbl_deep_extend('force', { debounce = 100 }, opts or {})
        util.setup.text(table_md, opts)
        vim.wait(0) -- let the leading-edge render callback fire
        local ui = require('render-markdown.core.ui')
        local buf = vim.api.nvim_get_current_buf()
        local decorator = ui.get(buf)
        assert.equals(1, decorator.n, 'leading-edge should have rendered once')
        return decorator, buf
    end

    describe('rapid scroll coalescing', function()
        it('leading fires once, intermediate scrolls are dropped, trailing fires once with the final value', function()
            fake_clock.with(function(fc)
                local decorator, buf = prepare(fc)
                local win = vim.api.nvim_get_current_win()

                -- Ten rapid scrolls within the debounce window.
                -- Each winrestview+api.render call goes through
                -- decorator:schedule. Because `running` is still
                -- true from the initial leading-edge, each of
                -- these stores its callback as `pending` and
                -- resets the trailing timer.
                for i = 1, 10 do
                    vim.fn.winrestview({ leftcol = i })
                    require('render-markdown.api').render({ buf = buf, win = win })
                    vim.wait(0)
                end

                assert.equals(
                    1,
                    decorator.n,
                    'no additional renders should have fired during the debounce window'
                )

                -- Advance past the debounce window. The trailing
                -- timer's callback fires via the fake clock; that
                -- callback calls vim.schedule for the actual work,
                -- which the following vim.wait(0) flushes.
                fc:advance(100)
                vim.wait(0)

                assert.equals(
                    2,
                    decorator.n,
                    'exactly one trailing-edge render should have fired'
                )

                local v = vim.fn.winsaveview()
                assert.equals(
                    10,
                    v.leftcol,
                    'the trailing render should have used the final scroll value'
                )
            end)
        end)

        it('no scroll during the window means no trailing render', function()
            fake_clock.with(function(fc)
                local decorator = prepare(fc)

                -- Nothing happens in the debounce window. The
                -- trailing timer still fires (from the initial
                -- leading edge's scheduling), but with no pending
                -- callback it just clears `running` and returns.
                fc:advance(100)
                vim.wait(0)

                assert.equals(
                    1,
                    decorator.n,
                    'no additional renders should fire when nothing happened'
                )
                assert.equals(
                    false,
                    decorator.running,
                    'decorator should return to idle'
                )
            end)
        end)
    end)

    describe('config state change mid-debounce', function()
        it('trailing render observes config.enabled=false set during the window and clears marks', function()
            -- The original form of this test tried to switch nvim to
            -- insert mode mid-debounce and rely on Updater:run reading
            -- env.mode.get() at trailing time. That does not work in
            -- headless nvim - :startinsert is a no-op because there is
            -- no real input loop, so env.mode.get() keeps reporting
            -- 'n'. This version tests the same property via a
            -- different axis in Updater:run's `render` decision: the
            -- per-buffer config.enabled flag. The trailing closure
            -- holds a reference to the same Config table the test
            -- mutates, so the trailing run evaluates render = false
            -- and takes the clear() branch.
            fake_clock.with(function(fc)
                local decorator, buf = prepare(fc)
                local ui = require('render-markdown.core.ui')
                local state = require('render-markdown.state')

                local before = #vim.api.nvim_buf_get_extmarks(buf, ui.ns, 0, -1, {})
                assert(before > 0, 'initial render should have produced marks')

                -- Queue a pending render during the debounce window.
                vim.fn.winrestview({ leftcol = 3 })
                require('render-markdown.api').render({
                    buf = buf,
                    win = vim.api.nvim_get_current_win(),
                })
                vim.wait(0)
                assert.equals(1, decorator.n)

                -- Mutate the per-buffer config while the trailing
                -- edge is pending. The Updater's self.config points
                -- at this same table.
                state.get(buf).enabled = false

                -- Advance; trailing fires; Updater:run sees
                -- config.enabled == false and calls self:clear().
                fc:advance(100)
                vim.wait(0)

                local after = #vim.api.nvim_buf_get_extmarks(buf, ui.ns, 0, -1, {})
                assert.equals(
                    0,
                    after,
                    'trailing render should have cleared marks because config.enabled flipped to false during the debounce window'
                )
            end)
        end)
    end)

    describe('timer lifetime under buffer deletion mid-debounce', function()
        it('deleting the buffer during the debounce window closes the timer without firing trailing', function()
            fake_clock.with(function(fc)
                local decorator, buf = prepare(fc)
                local timer = decorator.timer
                assert.equals(false, timer:is_closing())

                -- Trigger a pending render
                vim.fn.winrestview({ leftcol = 5 })
                require('render-markdown.api').render({
                    buf = buf,
                    win = vim.api.nvim_get_current_win(),
                })
                vim.wait(0)
                assert.equals(1, decorator.n)

                -- Delete the buffer; buffer_state.on_detach drops
                -- the decorator and closes its fake timer.
                vim.api.nvim_buf_delete(buf, { force = true })
                vim.wait(50, function() return timer:is_closing() end)
                assert.equals(
                    true,
                    timer:is_closing(),
                    'timer should be closed by buffer_state destroy hook'
                )

                -- Advancing past the deadline must NOT invoke the
                -- stale trailing callback - the timer is closed.
                fc:advance(100)
                vim.wait(0)

                assert.equals(
                    1,
                    decorator.n,
                    'closed timer must not fire a trailing-edge render after its buffer dies'
                )
            end)
        end)
    end)
end)
