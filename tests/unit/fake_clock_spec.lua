---@module 'luassert'

local clock = require('render-markdown.lib.clock')
local fake_clock = require('tests.helpers.fake_clock')

describe('fake_clock', function()
    after_each(function()
        clock._reset()
    end)

    describe('timer basics', function()
        it('start/advance fires callback when deadline reached', function()
            local fc = fake_clock.new()
            local fired = 0
            local timer = fc:new_timer()
            timer:start(100, 0, function() fired = fired + 1 end)

            fc:advance(50)
            assert.equals(0, fired, 'not fired before deadline')
            fc:advance(49)
            assert.equals(0, fired, 'still not fired one tick before')
            fc:advance(1)
            assert.equals(1, fired, 'fired exactly at deadline')
        end)

        it('one-shot timer does not fire twice on further advance', function()
            local fc = fake_clock.new()
            local fired = 0
            local timer = fc:new_timer()
            timer:start(10, 0, function() fired = fired + 1 end)
            fc:advance(100)
            assert.equals(1, fired)
            fc:advance(100)
            assert.equals(1, fired)
        end)

        it('stop cancels a pending timer', function()
            local fc = fake_clock.new()
            local fired = 0
            local timer = fc:new_timer()
            timer:start(10, 0, function() fired = fired + 1 end)
            timer:stop()
            fc:advance(100)
            assert.equals(0, fired)
        end)

        it('close marks the timer as closing', function()
            local fc = fake_clock.new()
            local timer = fc:new_timer()
            assert.equals(false, timer:is_closing())
            timer:close()
            assert.equals(true, timer:is_closing())
        end)

        it('rejects repeating timers', function()
            local fc = fake_clock.new()
            local timer = fc:new_timer()
            assert.has_error(function()
                timer:start(10, 10, function() end)
            end)
        end)

        it('rejects start after close', function()
            local fc = fake_clock.new()
            local timer = fc:new_timer()
            timer:close()
            assert.has_error(function()
                timer:start(10, 0, function() end)
            end)
        end)
    end)

    describe('re-scheduling during fire', function()
        it('callback that starts the same timer again defers to next advance', function()
            local fc = fake_clock.new()
            local fires = {}
            local timer = fc:new_timer()
            local function cb()
                fires[#fires + 1] = fc:now()
                -- re-arm for another 100 ms
                timer:start(100, 0, cb)
            end
            timer:start(100, 0, cb)

            fc:advance(100) -- fires once at 100
            assert.same({ 100 }, fires)

            fc:advance(99) -- not yet at the re-scheduled 200
            assert.same({ 100 }, fires)

            fc:advance(1) -- now at 200
            assert.same({ 100, 200 }, fires)
        end)
    end)

    describe('multiple timers', function()
        it('fires each in deadline order across a single advance', function()
            local fc = fake_clock.new()
            local order = {}
            local t1 = fc:new_timer()
            local t2 = fc:new_timer()
            local t3 = fc:new_timer()
            t1:start(30, 0, function() order[#order + 1] = 't1' end)
            t2:start(10, 0, function() order[#order + 1] = 't2' end)
            t3:start(20, 0, function() order[#order + 1] = 't3' end)

            fc:advance(100)
            assert.same({ 't2', 't3', 't1' }, order)
        end)
    end)

    describe('hrtime', function()
        it('returns nanoseconds derived from now_ms', function()
            local fc = fake_clock.new()
            assert.equals(0, fc:hrtime())
            fc:advance(5)
            assert.equals(5 * 1000000, fc:hrtime())
        end)
    end)

    describe('with() lifecycle helper', function()
        it('installs a fake, runs body, restores production clock', function()
            local captured
            fake_clock.with(function(fc)
                captured = fc
                -- clock module should now route through the fake
                local timer = clock.new_timer()
                local fired = false
                timer:start(50, 0, function() fired = true end)
                fc:advance(50)
                assert.equals(true, fired)
            end)
            assert.is_not_nil(captured)

            -- after with() returns, production clock is restored
            local real_timer = clock.new_timer()
            assert.is_function(real_timer.is_closing)
            -- the fake has `.closed` field; a real uv_timer_t does not
            assert.is_nil(real_timer.closed)
            real_timer:close()
        end)

        it('restores production clock even on error in body', function()
            local ok = pcall(function()
                fake_clock.with(function()
                    error('intentional test error')
                end)
            end)
            assert.equals(false, ok)
            -- production clock must be restored despite the error
            assert.is_nil(clock._override)
        end)

        it('propagates body return value', function()
            local result = fake_clock.with(function() return 42 end)
            assert.equals(42, result)
        end)
    end)
end)
