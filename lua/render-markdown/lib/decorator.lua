local compat = require('render-markdown.lib.compat')

---@class render.md.Decorator
---@field private buf integer
---@field private timer uv.uv_timer_t
---@field private running boolean
---@field private pending fun()?
---@field private marks render.md.Extmark[]
---@field private tick integer?
---@field n integer
local Decorator = {}
Decorator.__index = Decorator

---@param buf integer
---@return render.md.Decorator
function Decorator.new(buf)
    local self = setmetatable({}, Decorator)
    self.buf = buf
    self.timer = assert(compat.uv.new_timer())
    self.running = false
    self.pending = nil
    self.marks = {}
    self.tick = nil
    self.n = 0
    return self
end

---@return boolean
function Decorator:initial()
    return self.tick == nil
end

---@return boolean
function Decorator:changed()
    return self.tick ~= self:get_tick()
end

---@return render.md.Extmark[]
function Decorator:get()
    return self.marks
end

---@param marks render.md.Extmark[]
function Decorator:set(marks)
    self.marks = marks
    self.tick = self:get_tick()
    self.n = self.n + 1
end

---@param debounce boolean
---@param ms integer
---@param callback fun()
function Decorator:schedule(debounce, ms, callback)
    if debounce and ms > 0 then
        if self.running then
            -- Store latest callback to execute after debounce (trailing edge)
            self.pending = callback
        else
            -- Execute immediately (leading edge)
            self.running = true
            self.pending = nil
            vim.schedule(callback)
        end
        -- Always reset timer to debounce from latest event
        self.timer:start(ms, 0, function()
            vim.schedule(function()
                self.running = false
                -- Execute pending callback if state changed during debounce
                if self.pending then
                    local pending = self.pending
                    self.pending = nil
                    pending()
                end
            end)
        end)
    else
        vim.schedule(callback)
    end
end

---@private
---@return integer
function Decorator:get_tick()
    return vim.api.nvim_buf_get_changedtick(self.buf)
end

return Decorator
