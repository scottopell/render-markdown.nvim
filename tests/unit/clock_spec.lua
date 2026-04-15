---@module 'luassert'

local clock = require('render-markdown.lib.clock')

describe('clock', function()
    after_each(function()
        clock._reset()
    end)

    describe('production wiring', function()
        it('new_timer returns a real uv_timer_t', function()
            local timer = clock.new_timer()
            assert.is_not_nil(timer)
            -- real uv_timer_t responds to these methods
            assert.is_function(timer.start)
            assert.is_function(timer.stop)
            assert.is_function(timer.close)
            assert.is_function(timer.is_closing)
            assert.equals(false, timer:is_closing())
            timer:close()
            assert.equals(true, timer:is_closing())
        end)

        it('hrtime returns a monotonically increasing integer', function()
            local t0 = clock.hrtime()
            assert.is_number(t0)
            -- hrtime granularity is ns; any pair of calls should differ
            -- by at least a few ns. Busy-loop a tiny amount to guarantee it.
            local n = 0
            for i = 1, 1000 do n = n + i end
            local t1 = clock.hrtime()
            assert(t1 > t0, ('hrtime should advance: %d -> %d'):format(t0, t1))
        end)
    end)

    describe('override / reset', function()
        it('_set installs a fake; subsequent calls dispatch to it', function()
            local calls = { new_timer = 0, hrtime = 0 }
            clock._set({
                new_timer = function()
                    calls.new_timer = calls.new_timer + 1
                    return { marker = 'fake' }
                end,
                hrtime = function()
                    calls.hrtime = calls.hrtime + 1
                    return 42
                end,
            })
            local t = clock.new_timer()
            assert.equals('fake', t.marker)
            assert.equals(42, clock.hrtime())
            assert.equals(1, calls.new_timer)
            assert.equals(1, calls.hrtime)
        end)

        it('_reset restores production wiring', function()
            clock._set({
                new_timer = function() return { marker = 'fake' } end,
                hrtime = function() return 42 end,
            })
            clock._reset()
            local t = clock.new_timer()
            -- production uv_timer_t is a userdata / table with real methods,
            -- not the fake marker
            assert.is_not_equal('fake', t.marker)
            assert.is_function(t.start)
            t:close()
        end)

        it('_set rejects non-table impl', function()
            assert.has_error(function() clock._set(nil) end)
            assert.has_error(function() clock._set('not a table') end)
        end)

        it('_set rejects impl missing new_timer', function()
            assert.has_error(function()
                clock._set({ hrtime = function() return 0 end })
            end)
        end)

        it('_set rejects impl missing hrtime', function()
            assert.has_error(function()
                clock._set({ new_timer = function() return {} end })
            end)
        end)
    end)
end)
