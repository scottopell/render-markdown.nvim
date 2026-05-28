local str = require('render-markdown.lib.str')

---@class render.md.table.wrap.Segment
---@field text string
---@field highlight render.md.mark.Hl

---@class render.md.table.wrap.Token
---@field kind 'word'|'space'
---@field segments render.md.table.wrap.Segment[]
---@field width integer

---Module that converts a chunk list (output of process_cell_content) into a
---list of wrapped display lines, preserving inline highlights across wrap
---points. Used by the table 'wrap' cell mode to fit cell contents into a
---per-column budget.
local M = {}

---@param ch string
---@return boolean
local function is_space(ch)
    -- Only ASCII space and tab are treated as wrap-eligible whitespace.
    -- Newlines inside a cell are not expected for pipe-table syntax.
    return ch == ' ' or ch == '\t'
end

---Tokenise a chunk list into alternating word / whitespace tokens. A word
---may span multiple chunks when adjacent non-whitespace characters carry
---different highlights (e.g. inline emphasis), in which case the word's
---segments preserve the chunk-level highlights.
---@param chunks render.md.mark.Text[]
---@return render.md.table.wrap.Token[]
function M.tokenise(chunks)
    local tokens = {} ---@type render.md.table.wrap.Token[]
    local cur ---@type render.md.table.wrap.Token?

    ---Flush the in-progress token, if any.
    local function flush()
        if cur and #cur.segments > 0 then
            tokens[#tokens + 1] = cur
        end
        cur = nil
    end

    ---Append a single character (already tagged with its highlight) to the
    ---in-progress token, starting a new token whenever the kind changes.
    ---@param ch string
    ---@param kind 'word'|'space'
    ---@param hl render.md.mark.Hl
    local function push_char(ch, kind, hl)
        if cur and cur.kind ~= kind then
            flush()
        end
        if not cur then
            cur = { kind = kind, segments = {}, width = 0 }
        end
        local last = cur.segments[#cur.segments]
        if last and last.highlight == hl then
            last.text = last.text .. ch
        else
            cur.segments[#cur.segments + 1] = { text = ch, highlight = hl }
        end
        cur.width = cur.width + str.width(ch)
    end

    for _, chunk in ipairs(chunks) do
        local text, hl = chunk[1], chunk[2]
        if text and #text > 0 then
            local bytes = vim.str_utf_pos(text)
            for k, start_byte in ipairs(bytes) do
                local end_byte = k < #bytes and bytes[k + 1] - 1 or #text
                local ch = text:sub(start_byte, end_byte)
                local kind = is_space(ch) and 'space' or 'word'
                push_char(ch, kind, hl)
            end
        end
    end

    flush()
    return tokens
end

---Greedy line packer: consumes tokens left-to-right and emits display
---lines whose total width does not exceed the budget, except when a
---single word is wider than the budget (in which case it is placed on
---its own line and allowed to overflow). Leading whitespace on a new
---line is dropped, and a trailing space is dropped when wrapping
---occurs at the boundary it sits on (so wrapped lines never end with
---a stray space). The `pending` slot defers adding inter-word spaces
---until we know whether the next word will fit on the same line.
---@param tokens render.md.table.wrap.Token[]
---@param budget integer
---@return render.md.table.wrap.Segment[][]
function M.pack(tokens, budget)
    local lines = {} ---@type render.md.table.wrap.Segment[][]
    local cur_line = {} ---@type render.md.table.wrap.Segment[]
    local cur_width = 0
    local pending ---@type render.md.table.wrap.Token?

    local function flush()
        lines[#lines + 1] = cur_line
        cur_line = {}
        cur_width = 0
        pending = nil
    end

    local function append_word(token)
        if cur_width == 0 then
            -- Word goes on a fresh line. Always place it, even if it
            -- overflows the budget (single oversize tokens are not
            -- split mid-character).
            for _, seg in ipairs(token.segments) do
                cur_line[#cur_line + 1] = seg
            end
            cur_width = token.width
            return
        end

        local with_pending = cur_width + (pending and pending.width or 0)
        if with_pending + token.width <= budget then
            if pending then
                for _, seg in ipairs(pending.segments) do
                    cur_line[#cur_line + 1] = seg
                end
                cur_width = cur_width + pending.width
                pending = nil
            end
            for _, seg in ipairs(token.segments) do
                cur_line[#cur_line + 1] = seg
            end
            cur_width = cur_width + token.width
        else
            -- Wrap before this word. The pending space is consumed as
            -- the break and dropped, so the previous line does not
            -- end with a trailing space.
            flush()
            for _, seg in ipairs(token.segments) do
                cur_line[#cur_line + 1] = seg
            end
            cur_width = token.width
        end
    end

    for _, token in ipairs(tokens) do
        if token.kind == 'space' then
            if cur_width > 0 then
                pending = token
            end
            -- Else: drop leading whitespace.
        else
            append_word(token)
        end
    end

    -- Drop a trailing pending space; never emit it.
    pending = nil
    flush()
    return lines
end

---Wrap a chunk list to a budget. Returns a list of lines, each a list
---of segments. Empty content yields a single empty line.
---@param chunks render.md.mark.Text[]
---@param budget integer
---@return render.md.table.wrap.Segment[][]
function M.wrap(chunks, budget)
    if budget <= 0 then
        budget = 1
    end
    local tokens = M.tokenise(chunks)
    if #tokens == 0 then
        return { {} }
    end
    return M.pack(tokens, budget)
end

---Compute per-column budgets given the natural delim widths and the
---available text width. Returns a list of integer budgets that sum to
---`text_width - (n + 1)`. Returns nil when the available width is
---smaller than the minimum required to place every column at its
---floor; the caller should fall back to non-wrap rendering.
---
---`min_budget` may be either a single integer (used for all columns)
---or a list of per-column floors. The per-column form is needed so
---callers can raise a column's floor to its longest unsplittable word
---width (W1: oversize tokens render intact; W3: total still fits).
---@param natural_widths integer[]
---@param text_width integer
---@param min_budget integer|integer[]
---@return integer[]?
function M.allocate_budgets(natural_widths, text_width, min_budget)
    local n = #natural_widths
    if n == 0 then
        return nil
    end
    -- Account for the n+1 vertical pipes separating / bounding columns.
    local available = text_width - (n + 1)

    ---@param i integer
    ---@return integer
    local function floor_for(i)
        if type(min_budget) == 'table' then
            return min_budget[i]
        else
            return min_budget
        end
    end

    local total_floor = 0
    for i = 1, n do
        total_floor = total_floor + floor_for(i)
    end
    if available < total_floor then
        return nil
    end

    local total_natural = 0
    for _, w in ipairs(natural_widths) do
        total_natural = total_natural + math.max(w, 1)
    end

    local budgets = {} ---@type integer[]
    local floor_overflow = 0
    local flexible = {} ---@type integer[]
    for i, w in ipairs(natural_widths) do
        local share = math.floor(available * math.max(w, 1) / total_natural)
        local col_floor = floor_for(i)
        if share < col_floor then
            budgets[i] = col_floor
            floor_overflow = floor_overflow + (col_floor - share)
        else
            budgets[i] = share
            flexible[#flexible + 1] = i
        end
    end

    -- Reclaim the shortfall taken by min-floor columns from flexible
    -- columns proportional to their current share.
    if floor_overflow > 0 then
        if #flexible == 0 then
            -- No flexible columns to reclaim from; fall back.
            return nil
        end
        local flex_total = 0
        for _, i in ipairs(flexible) do
            flex_total = flex_total + budgets[i]
        end
        local remaining = floor_overflow
        for idx, i in ipairs(flexible) do
            local take
            if idx == #flexible then
                take = remaining
            else
                take = math.floor(floor_overflow * budgets[i] / flex_total)
            end
            local new_budget = budgets[i] - take
            if new_budget < floor_for(i) then
                -- Reclaim would push this column below its floor; bail.
                return nil
            end
            budgets[i] = new_budget
            remaining = remaining - take
        end
    end

    -- Distribute any rounding leftover. Prefer flexible (non-clamped)
    -- columns so floored columns stay at the floor; if there are none,
    -- spread evenly across all columns starting from the first.
    local total = 0
    for _, b in ipairs(budgets) do
        total = total + b
    end
    local leftover = available - total
    local recipients = #flexible > 0 and flexible or nil
    local idx = 1
    while leftover > 0 do
        if recipients then
            local target = recipients[((idx - 1) % #recipients) + 1]
            budgets[target] = budgets[target] + 1
        else
            budgets[((idx - 1) % n) + 1] = budgets[((idx - 1) % n) + 1] + 1
        end
        leftover = leftover - 1
        idx = idx + 1
    end

    return budgets
end

return M
