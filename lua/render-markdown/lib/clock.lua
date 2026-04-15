---Time injection seam.
---
---In production, every call through this module forwards to
---`vim.uv` (aka `vim.loop`), so production behaviour is identical to
---calling libuv directly. Tests can substitute a controllable
---implementation via `M._set(impl)` to advance time deterministically
---without sleeping or racing against wall-clock timers.
---
---Only the decorator's debounce window is behaviour-gated on time;
---this module exists to make that single seam testable. Diagnostic
---timing (log.lua's hrtime for runtime measurement) still goes
---through `compat.uv` directly because it has no behavioural effect.
---
---Contract of render.md.Clock:
---  * `new_timer()` returns an object that responds to
---    `start(ms, repeat_ms, cb)`, `stop()`, `close()`, `is_closing()`
---    - the same subset of `uv_timer_t` the decorator uses. The fake
---    implementation in tests/helpers/fake_clock.lua honours this.
---  * `hrtime()` returns a nanosecond integer that increases
---    monotonically within a single clock's lifetime.

---@class render.md.Clock
---@field new_timer fun(): uv.uv_timer_t
---@field hrtime fun(): integer

---@class render.md.lib.clock
local M = {}

---@private
---@type render.md.Clock?
M._override = nil

---@private
---@return render.md.Clock
local function backing()
    if M._override ~= nil then
        return M._override
    end
    local uv = vim.uv or vim.loop
    return {
        new_timer = function()
            return assert(uv.new_timer(), 'uv.new_timer returned nil')
        end,
        hrtime = function()
            return uv.hrtime()
        end,
    }
end

---@return uv.uv_timer_t
function M.new_timer()
    return backing().new_timer()
end

---@return integer
function M.hrtime()
    return backing().hrtime()
end

---Test hook: substitute a controllable clock implementation. The
---implementation must provide every method on render.md.Clock; the
---fake clock in tests/helpers/fake_clock.lua does.
---@param impl render.md.Clock
function M._set(impl)
    assert(type(impl) == 'table', 'clock._set requires a table')
    assert(type(impl.new_timer) == 'function', 'clock._set impl must provide new_timer')
    assert(type(impl.hrtime) == 'function', 'clock._set impl must provide hrtime')
    M._override = impl
end

---Test hook: restore the production clock.
function M._reset()
    M._override = nil
end

return M
