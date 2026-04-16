---@class render.md.Str
local M = {}

---@param s string
---@param sep string
---@param trimempty boolean
---@return string[]
function M.split(s, sep, trimempty)
    return vim.split(s, sep, { plain = true, trimempty = trimempty })
end

---Display-column substring. Returns the portion of `s` covering display
---columns [i, j] inclusive. Width-preserving: when a multi-column glyph
---straddles the start or end of the range, the visible portion of that
---glyph is substituted with spaces so the returned string's display
---width always equals `max(0, j - i + 1)` (assuming the source covers
---the range). This matters for callers like Line:sub which rely on
---slice-width equaling requested-width for horizontal-scroll clipping.
---@param s string
---@param i integer 1-based inclusive
---@param j integer 1-based inclusive
---@return string
function M.sub(s, i, j)
    if i > j then
        return ''
    end
    local bytes = vim.str_utf_pos(s)
    local col = 1
    local result = ''
    for k, start_byte in ipairs(bytes) do
        local end_byte = k < #bytes and bytes[k + 1] - 1 or #s
        local char = s:sub(start_byte, end_byte)
        local width = M.width(char)
        if width > 0 then
            local c_start, c_end = col, col + width - 1
            if c_start >= i and c_end <= j then
                -- fully within the requested range
                result = result .. char
            elseif c_end >= i and c_start <= j then
                -- partially overlapping: substitute the visible portion
                -- of this glyph with spaces to keep the column count
                local visible_start = math.max(c_start, i)
                local visible_end = math.min(c_end, j)
                result = result .. (' '):rep(visible_end - visible_start + 1)
            end
        end
        col = col + width
    end
    return result
end

---number of hashtags at the start of the string
---@param s string
---@return integer
function M.level(s)
    local match = s:match('^%s*(#+)')
    return match and #match or 0
end

---@param s? string
---@return integer
function M.width(s)
    return s and vim.fn.strdisplaywidth(s) or 0
end

---@param line? render.md.mark.Line
---@return integer
function M.line_width(line)
    local result = 0
    for _, text in ipairs(line or {}) do
        result = result + M.width(text[1])
    end
    return result
end

---@param pos 'start'|'end'
---@param s string
---@return integer
function M.spaces(pos, s)
    local pattern = pos == 'start' and '^%s*' or '%s*$'
    local from, to = s:find(pattern)
    return (from and to) and to - from + 1 or 0
end

---@param n integer
---@return string
function M.pad(n)
    return n > 0 and (' '):rep(n) or ''
end

---Convert a byte offset within a string to a display column (1-indexed)
---Byte offset is 0-indexed (like treesitter columns relative to line start)
---Result is 1-indexed display column suitable for str.sub()
---@param s string The string to analyze
---@param byte_offset integer The byte offset within the string (0-indexed)
---@return integer display_col The 1-indexed display column
function M.byte_to_col(s, byte_offset)
    local bytes = vim.str_utf_pos(s)
    local col = 1
    for k, start_byte in ipairs(bytes) do
        if start_byte > byte_offset + 1 then
            break
        end
        if start_byte <= byte_offset then
            local end_byte = k < #bytes and bytes[k + 1] - 1 or #s
            local char = s:sub(start_byte, end_byte)
            col = col + M.width(char)
        end
    end
    return col
end

---Convert a 0-indexed display column to a 0-indexed byte offset within
---a string. The inverse of byte_to_col. If the target display column is
---past the string's display width, returns the string's byte length.
---Useful for mapping window leftcol (a display column) to the byte
---position required by extmark APIs.
---@param s string
---@param display_col integer 0-indexed display column
---@return integer byte_offset 0-indexed byte offset
function M.col_to_byte(s, display_col)
    if display_col <= 0 then
        return 0
    end
    local bytes = vim.str_utf_pos(s)
    local col = 0
    for k, start_byte in ipairs(bytes) do
        local end_byte = k < #bytes and bytes[k + 1] - 1 or #s
        local char = s:sub(start_byte, end_byte)
        local w = M.width(char)
        -- char occupies display cols [col, col + w - 1]. Return the
        -- first byte of whichever char contains or follows display_col.
        if col + w > display_col then
            return start_byte - 1
        end
        col = col + w
    end
    return #s
end

return M
