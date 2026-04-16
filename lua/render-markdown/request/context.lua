local buffer_state = require('render-markdown.lib.buffer_state')
local str = require('render-markdown.lib.str')

---@class render.md.request.Context
---@field buf integer
---@field win integer
---@field config render.md.buf.Config
---@field view render.md.request.View
---@field conceal render.md.request.Conceal
---@field callout render.md.request.Callout
---@field checkbox render.md.request.Checkbox
---@field latex render.md.request.Latex
---@field offset render.md.request.Offset
---@field used render.md.request.Used
local Context = {}
Context.__index = Context

---@param buf integer
---@param win integer
---@param config render.md.buf.Config
---@param view render.md.request.View
---@return render.md.request.Context
function Context.new(buf, win, config, view)
    local self = setmetatable({}, Context)
    self.buf = buf
    self.win = win
    self.config = config
    self.view = view
    self.conceal =
        require('render-markdown.request.conceal').new(buf, win, view)
    self.callout = require('render-markdown.request.callout').new()
    self.checkbox = require('render-markdown.request.checkbox').new()
    self.latex = require('render-markdown.request.latex').new()
    self.offset = require('render-markdown.request.offset').new()
    self.used = require('render-markdown.request.used').new()
    return self
end

---@param body? render.md.node.Body
---@return integer
function Context:width(body)
    if not body then
        return 0
    end
    return str.width(body.text) + self.offset:get(body) - self.conceal:get(body)
end

---@class render.md.request.context.Manager
local M = {}

---@private
---Per-buffer request-context cache. Previously this table was never
---cleared - not even on setup - and leaked every Context for every
---buffer ever opened. Now it is lifetime-bound to the buffer via
---buffer_state's on_detach hook.
---@type render.md.buffer_state.Store
M._store = buffer_state.define_cache('context', {
    make = function(buf, win, config)
        local view = require('render-markdown.request.view').new(buf)
        return Context.new(buf, win, config, view)
    end,
    destroy = function(_) end, -- plain object graph, no external resources
})

---@param buf integer
---@param win integer
---@return boolean
function M.contains(buf, win)
    local context = M._store:peek(buf)
    return context and context.view:contains(win) or false
end

---@param buf integer
---@param win integer
---@param config render.md.buf.Config
---@return render.md.request.Context?
function M.new(buf, win, config)
    -- Always create a fresh Context on this entry point - the caller
    -- (Updater:parse) calls M.new precisely when it has determined
    -- the existing cached context is stale (scroll/range change or
    -- buffer edit). Drop any prior entry first so buffer_state's
    -- destroy hook fires, then install the new one.
    M._store:drop(buf)
    return M._store:get(buf, win, config)
end

---@param buf integer
---@return render.md.request.Context
function M.get(buf)
    return assert(M._store:peek(buf), 'missing request context')
end

return M
