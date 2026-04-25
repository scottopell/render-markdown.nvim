local Node = require('render-markdown.lib.node')
local env = require('render-markdown.lib.env')
local interval = require('render-markdown.lib.interval')
local log = require('render-markdown.core.log')

---@class render.md.request.View
---@field private buf integer
---@field private ranges render.md.Range[]
---@field private leftcol integer
---@field private text_width integer
local View = {}
View.__index = View

---@param buf integer
---@return render.md.request.View
function View.new(buf)
    local self = setmetatable({}, View)
    self.buf = buf
    local ranges = {} ---@type render.md.Range[]
    local max_leftcol = 0
    -- Use the minimum text_width across windows so the wrap path
    -- produces output that fits all of them. Initialise to math.huge
    -- and fall back to 0 only if no windows are showing the buffer.
    local min_text_width = math.huge
    for _, win in ipairs(env.buf.wins(buf)) do
        ranges[#ranges + 1] = env.range(buf, win, 10)
        local view = env.win.view(win)
        max_leftcol = math.max(max_leftcol, view.leftcol)
        min_text_width = math.min(min_text_width, env.win.width(win))
    end
    self.ranges = interval.coalesce(ranges)
    self.leftcol = max_leftcol
    self.text_width = min_text_width == math.huge and 0 or min_text_width
    return self
end

---@return string
function View:__tostring()
    local ranges = {} ---@type string[]
    for _, range in ipairs(self.ranges) do
        ranges[#ranges + 1] = ('%d->%d'):format(range[1], range[2])
    end
    return ('[%s]'):format(table.concat(ranges, ','))
end

---@param win integer
---@return boolean
function View:contains(win)
    -- Check if leftcol changed (horizontal scroll)
    local view = env.win.view(win)
    if view.leftcol ~= self.leftcol then
        return false
    end
    -- Check if window text_width changed (resize) - the wrap path
    -- depends on this, so a resize must force a re-render.
    if env.win.width(win) ~= self.text_width then
        return false
    end
    -- Check if visible rows are contained
    local rows = env.range(self.buf, win, 0)
    for _, range in ipairs(self.ranges) do
        if interval.contains(range, rows) then
            return true
        end
    end
    return false
end

---@return integer
function View:get_leftcol()
    return self.leftcol
end

---@return integer
function View:get_text_width()
    return self.text_width
end

---@param node TSNode
---@return boolean
function View:overlaps(node)
    local start_row, _, end_row = node:range()
    for _, range in ipairs(self.ranges) do
        if interval.overlap(range, { start_row, end_row }) then
            return true
        end
    end
    return false
end

---@param parser vim.treesitter.LanguageTree
---@param callback fun()
function View:parse(parser, callback)
    for _, range in ipairs(self.ranges) do
        parser:parse(range)
    end
    callback()
end

---@param root TSNode
---@param query vim.treesitter.Query
---@param callback fun(capture: string, node: render.md.Node)
function View:nodes(root, query, callback)
    self:query(root, query, function(id, ts_node)
        if not ts_node:has_error() then
            local capture = query.captures[id]
            local node = Node.new(self.buf, ts_node)
            log.node(capture, node)
            callback(capture, node)
        end
    end)
end

---@param root TSNode
---@param query vim.treesitter.Query
---@param callback fun(id: integer, node: TSNode, data: vim.treesitter.query.TSMetadata)
function View:query(root, query, callback)
    for _, range in ipairs(self.ranges) do
        local start, stop = range[1], range[2]
        for id, node, data in query:iter_captures(root, self.buf, start, stop) do
            callback(id, node, data)
        end
    end
end

return View
