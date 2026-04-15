---@module 'luassert'

---A controllable implementation of render.md.Clock for tests. Holds
---a simulated `now_ms` that only advances via `clock:advance(ms)`;
---any timer whose deadline has elapsed fires its callback during
---that advance, in deadline order.
---
---Contract:
---  * `new_timer()` returns an object with the subset of uv_timer_t
---    that decorator.lua uses: start / stop / close / is_closing.
---  * Only one-shot timers are supported (repeat_ms must be 0).
---    Production decorator.lua only uses one-shot timers.
---  * `hrtime()` returns nanoseconds synthesized from `now_ms`.
---  * Timer callbacks may call `vim.schedule` - the fake clock
---    cannot flush those; callers must `vim.wait(0)` after
---    `advance()` to let nvim's own scheduler run them.
---  * A callback that re-schedules its timer (calls start() again)
---    is handled: the new deadline is relative to the current
---    `now_ms`, so it will NOT fire in the same advance() call.
---
---Lifecycle helper:
---  * `M.with(fn)` wraps a test body so the fake is installed via
---    clock._set before the body runs and torn down with
---    clock._reset in an `after`-style guarantee, even on
---    exceptions. Tests that forget after_each cannot leak the fake
---    into sibling tests when they use `with`.

local clock = require('render-markdown.lib.clock')

---@class render.md.test.FakeClock : render.md.Clock
---@field private now_ms integer
---@field private timers table[]
local FakeClock = {}
FakeClock.__index = FakeClock

---@return render.md.test.FakeClock
function FakeClock.new()
    return setmetatable({ now_ms = 0, timers = {} }, FakeClock)
end

---Nanoseconds, matching libuv's hrtime contract.
---@return integer
function FakeClock:hrtime()
    return self.now_ms * 1000000
end

---@return table
function FakeClock:new_timer()
    local fc = self
    local timer = {
        deadline = nil,
        callback = nil,
        active = false,
        closed = false,
    }
    ---@param ms integer
    ---@param repeat_ms integer must be 0
    ---@param cb fun()
    function timer:start(ms, repeat_ms, cb)
        assert(not self.closed, 'fake timer started after close')
        assert(repeat_ms == 0, 'fake clock only supports one-shot timers')
        self.deadline = fc.now_ms + ms
        self.callback = cb
        self.active = true
    end
    function timer:stop()
        self.active = false
    end
    function timer:close()
        self.active = false
        self.closed = true
    end
    function timer:is_closing()
        return self.closed
    end
    fc.timers[#fc.timers + 1] = timer
    return timer
end

---Advance simulated time by `ms`. Any timer whose deadline has
---elapsed fires in deadline order; callbacks that re-schedule their
---own timer do not fire again in the same call (their new deadline
---is after the current `now_ms`).
---@param ms integer
function FakeClock:advance(ms)
    assert(ms >= 0, 'advance must be non-negative')
    self.now_ms = self.now_ms + ms
    while true do
        local next_timer, next_deadline = nil, math.huge
        for _, t in ipairs(self.timers) do
            if
                t.active
                and not t.closed
                and t.deadline
                and t.deadline <= self.now_ms
                and t.deadline < next_deadline
            then
                next_timer = t
                next_deadline = t.deadline
            end
        end
        if not next_timer then
            break
        end
        next_timer.active = false
        local cb = next_timer.callback
        if cb then
            cb()
        end
    end
end

---Read-only access to the list of timers the clock has ever handed
---out. Useful for assertions like "decorator created exactly one
---timer across this test body".
---@return table[]
function FakeClock:timer_list()
    return self.timers
end

---Current simulated time in milliseconds.
---@return integer
function FakeClock:now()
    return self.now_ms
end

---@class render.md.test.fake_clock
local M = {}

M.FakeClock = FakeClock

---@return render.md.test.FakeClock
function M.new()
    return FakeClock.new()
end

---Install a fresh FakeClock, run `body(fc)`, and unconditionally
---restore production wiring afterwards - even on errors. The return
---value of `body` is propagated; any error is re-raised after
---teardown so the test framework still sees it.
---
---FakeClock uses method syntax (`fc:new_timer()`, `fc:advance(ms)`)
---for its public surface, but clock.lua calls `backing().new_timer()`
---with dot syntax. Adapt via a flat closure-bound table so the
---render.md.Clock contract is satisfied without pushing a colon
---call convention into production code.
---@generic T
---@param body fun(fc: render.md.test.FakeClock): T
---@return T
function M.with(body)
    local fc = FakeClock.new()
    clock._set({
        new_timer = function() return fc:new_timer() end,
        hrtime = function() return fc:hrtime() end,
    })
    local ok, result = pcall(body, fc)
    clock._reset()
    if not ok then
        error(result, 0)
    end
    return result
end

return M
