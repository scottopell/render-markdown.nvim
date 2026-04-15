local Context = require('render-markdown.request.context')
local buffer_state = require('render-markdown.lib.buffer_state')
local compat = require('render-markdown.lib.compat')
local env = require('render-markdown.lib.env')
local iter = require('render-markdown.lib.iter')
local log = require('render-markdown.core.log')
local state = require('render-markdown.state')

---@class render.md.Ui
local M = {}

M.ns = vim.api.nvim_create_namespace('render-markdown.nvim')

---@private
---Per-buffer decorator cache. The Decorator owns a uv_timer which
---must be stopped AND closed when the entry is dropped, otherwise
---libuv keeps a reference to it and the callback closure lives on.
---This destructor runs automatically via buffer_state's on_detach
---hook when nvim deletes the buffer.
---@type render.md.buffer_state.Store
M._store = buffer_state.define_cache('decorator', {
    make = function(buf)
        return require('render-markdown.lib.decorator').new(buf)
    end,
    destroy = function(decorator)
        if decorator.timer then
            pcall(decorator.timer.stop, decorator.timer)
            pcall(decorator.timer.close, decorator.timer)
        end
    end,
})

---called from state on setup
function M.setup()
    -- clear marks across every valid buffer so a prior render's
    -- overlays do not leak visually into the new configuration
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
    -- the decorator store itself is wiped centrally by state.setup
    -- via buffer_state._reset_all (see state.lua)
end

---@param buf integer
---@return render.md.Decorator
function M.get(buf)
    return M._store:get(buf)
end

---@param buf integer
---@param win integer
---@param event string
---@param force boolean
function M.update(buf, win, event, force)
    log.buf('info', 'Update', buf, event, ('force %s'):format(force))
    M.updater.new(buf, win, force):start()
end

---@class render.md.ui.Updater
---@field private buf integer
---@field private win integer
---@field private force boolean
---@field private decorator render.md.Decorator
---@field private config render.md.buf.Config
---@field private mode string
local Updater = {}
Updater.__index = Updater

---@param buf integer
---@param win integer
---@param force boolean
---@return render.md.ui.Updater
function Updater.new(buf, win, force)
    local self = setmetatable({}, Updater)
    self.buf = buf
    self.win = win
    self.force = force
    self.decorator = M.get(buf)
    self.config = state.get(buf)
    return self
end

function Updater:start()
    if not env.valid(self.buf, self.win) then
        return
    end
    if env.buf.empty(self.buf) then
        return
    end
    self.decorator:schedule(
        self:changed(),
        self.config.debounce,
        log.runtime('update', function()
            self:run()
        end)
    )
end

---@private
---@return boolean
function Updater:changed()
    -- force or buffer has changed or we have not handled the visible range yet
    return self.force
        or self.decorator:changed()
        or not Context.contains(self.buf, self.win)
end

---@private
function Updater:run()
    if not env.valid(self.buf, self.win) then
        return
    end
    self.mode = env.mode.get() -- mode is only available after this point
    local in_diff = env.win.get(self.win, 'diff')
    local render = self.config.enabled
        and self.config.resolved:render(self.mode)
        and (state.render_in_diff or not in_diff)
    log.buf('info', 'Render', self.buf, render)
    local next_state = render and 'rendered' or 'default'
    for _, win in ipairs(env.buf.wins(self.buf)) do
        for name, value in pairs(self.config.win_options) do
            env.win.set(win, name, value[next_state])
        end
    end
    if not render then
        self:clear()
    else
        self:render()
    end
end

---@private
function Updater:clear()
    local extmarks = self.decorator:get()
    for _, extmark in ipairs(extmarks) do
        extmark:hide(M.ns, self.buf)
    end
    vim.api.nvim_buf_clear_namespace(self.buf, M.ns, 0, -1)
    state.on.clear({ buf = self.buf, win = self.win })
end

---@private
function Updater:render()
    if self:changed() then
        self:parse(function(extmarks)
            if not extmarks then
                return
            end
            local initial = self.decorator:initial()
            self:clear()
            self.decorator:set(extmarks)
            if initial then
                compat.fix_lsp_window(self.buf, self.win, extmarks)
                state.on.initial({ buf = self.buf, win = self.win })
            end
            self:display()
        end)
    else
        self:display()
    end
end

---@private
---@param callback fun(extmarks: render.md.Extmark[]|nil)
function Updater:parse(callback)
    local ok, parser = pcall(vim.treesitter.get_parser, self.buf)
    if ok and parser then
        -- reset buffer context
        local context = Context.new(self.buf, self.win, self.config)
        if context then
            -- make sure injections are processed
            context.view:parse(parser, function()
                local Extmark = require('render-markdown.lib.extmark')
                local handlers = require('render-markdown.core.handlers')
                local marks = handlers.run(context, parser)
                callback(iter.list.map(marks, Extmark.new))
            end)
        else
            log.buf('debug', 'Skip', self.buf, 'in progress')
            callback(nil)
        end
    else
        log.buf('error', 'Fail', self.buf, 'no treesitter parser found')
        callback(nil)
    end
end

---@private
function Updater:display()
    local range = self:hidden()
    local extmarks = self.decorator:get()
    for _, extmark in ipairs(extmarks) do
        if self:hide(extmark, range) then
            extmark:hide(M.ns, self.buf)
        else
            extmark:show(M.ns, self.buf)
        end
    end
    state.on.render({ buf = self.buf, win = self.win })
end

---@private
---@return render.md.Range?
function Updater:hidden()
    -- anti-conceal is not enabled -> hide nothing
    -- in disabled mode -> hide nothing
    local config = self.config.anti_conceal
    if not config.enabled or env.mode.is(self.mode, config.disabled_modes) then
        return nil
    end
    -- row is not known -> buffer is not active -> hide nothing
    local row = env.row.get(self.buf, self.win)
    if not row then
        return nil
    end
    if env.mode.is(self.mode, { 'v', 'V', '\22' }) then
        local start = vim.fn.getpos('v')[2] - 1
        ---@type render.md.Range
        return { math.min(row, start), math.max(row, start) }
    else
        ---@type render.md.Range
        return { row - config.above, row + config.below }
    end
end

---@private
---@param extmark render.md.Extmark
---@param range? render.md.Range
---@return boolean
function Updater:hide(extmark, range)
    local mark = extmark:get()

    -- not in top level or mark level modes -> hide
    local show = env.mode.join(self.config.render_modes, mark.modes)
    if not env.mode.is(self.mode, show) then
        return true
    end

    -- does not overlap with hidden range -> show
    if not extmark:overlaps(range) then
        return false
    end

    local conceal = mark.conceal
    if type(conceal) == 'boolean' then
        -- mark has conceal value -> respect
        return conceal
    else
        -- mark has conceal element -> show if anti-conceal is ignored
        local ignore = self.config.anti_conceal.ignore[conceal]
        return not (ignore and env.mode.is(self.mode, ignore))
    end
end

---@private
M.updater = Updater

return M
