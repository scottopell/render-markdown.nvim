local Base = require('render-markdown.render.base')
local iter = require('render-markdown.lib.iter')
local log = require('render-markdown.core.log')
local str = require('render-markdown.lib.str')
local table_wrap = require('render-markdown.render.markdown.table_wrap')
local ts = require('render-markdown.core.ts')

-- Lower bound on a column's wrap budget (in display columns, including
-- per-cell padding). Below this even a 1-character cell would render as
-- pure padding, so wrap falls back to the non-wrap path instead.
local MIN_COLUMN_BUDGET = 5

---@class render.md.table.Data
---@field delim render.md.table.DelimRow
---@field rows render.md.table.Row[]
---@field wrap? render.md.table.WrapData

---@class render.md.table.WrapData
---@field budgets integer[]
---@field rows render.md.table.WrapRow[]
---@field indent integer

---@class render.md.table.WrapRow
---@field height integer
---@field cells render.md.mark.Line[][]

---@class render.md.table.DelimRow
---@field node render.md.Node
---@field cols render.md.table.DelimCol[]

---@class render.md.table.DelimCol
---@field width integer
---@field alignment render.md.table.Alignment

---@enum render.md.table.Alignment
local Alignment = {
    left = 'left',
    right = 'right',
    center = 'center',
    default = 'default',
}

---@class render.md.table.Row
---@field node render.md.Node
---@field pipes render.md.Node[]
---@field cols render.md.table.Col[]

---@class render.md.table.Col
---@field row integer
---@field start_col integer
---@field end_col integer
---@field width integer
---@field space render.md.table.Space

---@class render.md.table.Space
---@field left integer
---@field right integer

---@class render.md.render.Table: render.md.Render
---@field private config render.md.table.Config
---@field private data render.md.table.Data
local Render = setmetatable({}, Base)
Render.__index = Render

---@protected
---@return boolean
function Render:setup()
    self.config = self.context.config.pipe_table
    if not self.config.enabled then
        return false
    end

    -- ensure delimiter and rows exist
    local delim_node = nil ---@type render.md.Node?
    local row_nodes = {} ---@type render.md.Node[]
    local types = {
        delim = 'pipe_table_delimiter_row',
        row = { 'pipe_table_header', 'pipe_table_row' },
        skip = { 'block_continuation' },
    }
    self.node:for_each_child(function(node)
        if node.type == types.delim then
            delim_node = node
        elseif self.context.view:overlaps(node:get()) then
            if vim.tbl_contains(types.row, node.type) then
                row_nodes[#row_nodes + 1] = node
            elseif not vim.tbl_contains(types.skip, node.type) then
                log.unhandled(self.context.buf, 'markdown', 'row', node.type)
            end
        end
    end)
    if not delim_node or #row_nodes == 0 then
        return false
    end

    -- double check delimiter exists after parsing
    local delim = self:parse_delim(delim_node)
    if not delim then
        return false
    end

    -- double check rows exist after parsing
    local rows = {} ---@type render.md.table.Row[]
    table.sort(row_nodes)
    for _, row_node in ipairs(row_nodes) do
        local row = self:parse_row(row_node, #delim.cols)
        if row then
            rows[#rows + 1] = row
        end
    end
    if #rows == 0 then
        return false
    end

    -- store the max width in the delimiter
    for _, row in ipairs(rows) do
        for i, col in ipairs(row.cols) do
            local space = col.space.left + col.space.right
            local available = space - (2 * self.config.padding)
            -- if we don't have enough space for padding add it to the width
            local width = col.width
            if available < 0 then
                width = width - available
            end
            if self.config.cell == 'trimmed' then
                width = width - math.max(available, 0)
            end
            local delim_col = delim.cols[i]
            delim_col.width = math.max(delim_col.width, width)
        end
    end

    self.data = { delim = delim, rows = rows }

    -- Auto-activate wrap mode when (a) the user opted in via cell='wrap'
    -- and (b) the natural table width does not fit the window. Wrap
    -- replaces delim.cols[i].width with the per-column budget, so the
    -- subsequent delimiter / border logic produces the same widths the
    -- wrapped row content was sized to.
    if self.config.cell == 'wrap' then
        self:try_activate_wrap()
    end

    return true
end

---Attempt to activate wrap mode. On success, populates self.data.wrap
---and rewrites delim.cols[i].width to the per-column budget so that the
---existing delimiter / border rendering paths produce widths that match
---the wrapped row content. On failure (table fits, window too narrow,
---etc.) leaves self.data unchanged so rendering falls through to the
---padded path.
---@private
function Render:try_activate_wrap()
    local delim = self.data.delim
    local n = #delim.cols
    if n == 0 then
        return
    end

    -- Total natural width of the table including pipes.
    local natural_total = n + 1
    for _, col in ipairs(delim.cols) do
        natural_total = natural_total + col.width
    end

    local indent = str.spaces('start', delim.node.text)
    local text_width = self.context.view:get_text_width()
    local available = text_width - indent
    if available <= 0 then
        return
    end

    -- Auto-trigger: only wrap when the table actually doesn't fit. For
    -- tables that already fit we want the padded path's exact output
    -- (W6 in cell-wrapping.allium).
    if natural_total <= available then
        return
    end

    local natural_widths = iter.list.map(delim.cols, function(col)
        return col.width
    end)

    local padding = self.config.padding
    local row_highlight = self.config.row
    local head_highlight = self.config.head

    -- First pass: pre-tokenise each cell so we can (a) measure the
    -- longest unsplittable word per column to set a per-column floor
    -- (a column must be wide enough to hold its widest word, otherwise
    -- the cell would overflow its budget and break row alignment) and
    -- (b) avoid re-tokenising when packing into lines below.
    local row_tokens = {} ---@type render.md.table.wrap.Token[][][]
    local longest_word = {} ---@type integer[]
    for i = 1, n do
        longest_word[i] = 0
    end
    for r, row in ipairs(self.data.rows) do
        local header = row.node.type == 'pipe_table_header'
        local cell_hl = header and head_highlight or row_highlight
        local row_start = row.node.start_col
        local cells_tokens = {} ---@type render.md.table.wrap.Token[][]
        for i = 1, n do
            local content_start_byte = row.pipes[i].end_col - row_start
            local content_end_byte = row.pipes[i + 1].start_col - row_start
            local chunks = self:process_cell_content(
                row.node,
                content_start_byte,
                content_end_byte,
                cell_hl
            )
            chunks = self:trim_chunks(chunks)
            local tokens = table_wrap.tokenise(chunks)
            cells_tokens[i] = tokens
            for _, tok in ipairs(tokens) do
                if tok.kind == 'word' and tok.width > longest_word[i] then
                    longest_word[i] = tok.width
                end
            end
        end
        row_tokens[r] = cells_tokens
    end

    -- Per-column floor: enough to hold the widest word plus padding.
    -- Falls back to the global MIN_COLUMN_BUDGET when content is empty.
    local floors = {} ---@type integer[]
    for i = 1, n do
        floors[i] = math.max(MIN_COLUMN_BUDGET, longest_word[i] + 2 * padding)
    end

    local budgets = table_wrap.allocate_budgets(natural_widths, available, floors)
    if not budgets then
        return
    end

    -- Second pass: pack the pre-tokenised cells into wrapped lines
    -- using the resolved budgets.
    local wrap_rows = {} ---@type render.md.table.WrapRow[]
    for r in ipairs(self.data.rows) do
        local cells = {} ---@type render.md.mark.Line[][]
        local height = 1
        for i = 1, n do
            local content_budget = math.max(1, budgets[i] - 2 * padding)
            local lines = table_wrap.pack(row_tokens[r][i], content_budget)
            local cell_lines = {} ---@type render.md.mark.Line[]
            for _, segs in ipairs(lines) do
                local line = {} ---@type render.md.mark.Line
                for _, seg in ipairs(segs) do
                    line[#line + 1] = { seg.text, seg.highlight }
                end
                cell_lines[#cell_lines + 1] = line
            end
            cells[i] = cell_lines
            if #cell_lines > height then
                height = #cell_lines
            end
        end
        wrap_rows[#wrap_rows + 1] = { height = height, cells = cells }
    end

    -- Rewrite delimiter widths to the budgets so delimiter() and
    -- border() naturally produce the wrapped widths.
    for i = 1, n do
        delim.cols[i].width = budgets[i]
    end

    self.data.wrap = { budgets = budgets, rows = wrap_rows, indent = indent }
end

---Drop a leading and trailing whitespace-only run from a chunk list.
---Used so wrapped cells don't carry the source's per-cell padding into
---the wrap budget; padding is added back when composing display lines.
---@private
---@param chunks render.md.mark.Text[]
---@return render.md.mark.Text[]
function Render:trim_chunks(chunks)
    local result = {} ---@type render.md.mark.Text[]
    for _, c in ipairs(chunks) do
        result[#result + 1] = { c[1], c[2] }
    end
    if #result > 0 then
        local first = result[1]
        first[1] = first[1]:gsub('^[ \t]+', '')
        if first[1] == '' then
            table.remove(result, 1)
        end
    end
    if #result > 0 then
        local last = result[#result]
        last[1] = last[1]:gsub('[ \t]+$', '')
        if last[1] == '' then
            result[#result] = nil
        end
    end
    return result
end

---@private
---@param node render.md.Node
---@return render.md.table.DelimRow?
function Render:parse_delim(node)
    local pipes, cells = self:parse_cells(node, 'pipe_table_delimiter_cell')
    if not pipes or not cells then
        return nil
    end
    local cols = {} ---@type render.md.table.DelimCol[]
    for i, cell in ipairs(cells) do
        local start_col, end_col = pipes[i].end_col, pipes[i + 1].start_col
        local width = end_col - start_col
        assert(width >= 0, 'invalid table layout')
        if self.config.cell == 'padded' or self.config.cell == 'wrap' then
            -- 'wrap' uses the same initial natural width as 'padded';
            -- if wrap activates, delim widths are overwritten with
            -- budgets after setup() finishes width computation.
            width = math.max(width, self.config.min_width)
        elseif self.config.cell == 'trimmed' then
            width = self.config.min_width
        end
        cols[#cols + 1] = {
            width = width,
            alignment = Render.alignment(cell),
        }
    end
    ---@type render.md.table.DelimRow
    return { node = node, cols = cols }
end

---@private
---@param node render.md.Node
---@return render.md.table.Alignment
function Render.alignment(node)
    local left = node:child('pipe_table_align_left')
    local right = node:child('pipe_table_align_right')
    if left and right then
        return Alignment.center
    elseif left then
        return Alignment.left
    elseif right then
        return Alignment.right
    else
        return Alignment.default
    end
end

---@private
---@param node render.md.Node
---@param num_cols integer
---@return render.md.table.Row?
function Render:parse_row(node, num_cols)
    local pipes, cells = self:parse_cells(node, 'pipe_table_cell')
    if not pipes or not cells or #cells ~= num_cols then
        return nil
    end
    local cols = {} ---@type render.md.table.Col[]
    for i, cell in ipairs(cells) do
        -- account for double width glyphs by replacing cell range with width
        local start_col, end_col = pipes[i].end_col, pipes[i + 1].start_col
        local width = (end_col - start_col)
            - (cell.end_col - cell.start_col)
            + self.context:width(cell)
            + self.config.cell_offset({ node = cell:get() })
        assert(width >= 0, 'invalid table layout')
        cols[#cols + 1] = {
            row = cell.start_row,
            start_col = cell.start_col,
            end_col = cell.end_col,
            width = width,
            space = {
                -- gap between the cell start and the pipe start
                left = math.max(cell.start_col - start_col, 0),
                -- attached to the end of the cell itself
                right = math.max(str.spaces('end', cell.text), 0),
            },
        }
    end
    ---@type render.md.table.Row
    return { node = node, pipes = pipes, cols = cols }
end

---@private
---@param node render.md.Node
---@param cell string
---@return render.md.Node[]?, render.md.Node[]?
function Render:parse_cells(node, cell)
    local pipes = {} ---@type render.md.Node[]
    local cells = {} ---@type render.md.Node[]
    node:for_each_child(function(child)
        if child.type == '|' then
            pipes[#pipes + 1] = child
        elseif child.type == cell then
            cells[#cells + 1] = child
        else
            log.unhandled(self.context.buf, 'markdown', 'cell', child.type)
        end
    end)
    if #pipes == 0 or #cells == 0 or #pipes ~= #cells + 1 then
        return nil, nil
    end
    table.sort(pipes)
    table.sort(cells)
    return pipes, cells
end

---@protected
function Render:run()
    self:delimiter()
    for i, row in ipairs(self.data.rows) do
        if self.data.wrap then
            self:row_wrapped(row, i)
        else
            self:row(row)
        end
    end
    if self.config.border_enabled then
        self:border()
    end
end

---Map of treesitter node types to highlight groups for inline styling
---@type table<string, string>
local inline_highlights = {
    strong_emphasis = '@markup.strong',
    emphasis = '@markup.italic',
    code_span = 'RenderMarkdownCodeInline',
}

---Apply concealment to text within a byte range, returning the processed text
---@private
---@param row_node render.md.Node The row node containing the text
---@param start_byte integer Start byte offset (buffer column)
---@param end_byte integer End byte offset (buffer column)
---@return string processed_text Text with concealment applied
function Render:apply_conceal(row_node, start_byte, end_byte)
    local text = row_node.text
    local row_start = row_node.start_col

    local conceal_line = self.context.conceal:line(row_node)
    local ranges = conceal_line.ranges

    if not self.context.conceal:enabled() or #ranges == 0 then
        local content_start = str.byte_to_col(text, start_byte)
        local content_end = str.byte_to_col(text, end_byte) - 1
        return str.sub(text, content_start, content_end)
    end

    local result = ''
    local pos = start_byte

    for _, range in ipairs(ranges) do
        local conceal_start = range[1] - row_start
        local conceal_end = range[2] - row_start
        local replacement = range[3]

        if conceal_end > start_byte and conceal_start < end_byte then
            local overlap_start = math.max(conceal_start, start_byte)
            local overlap_end = math.min(conceal_end, end_byte)

            if pos < overlap_start then
                local pre_start = str.byte_to_col(text, pos)
                local pre_end = str.byte_to_col(text, overlap_start) - 1
                result = result .. str.sub(text, pre_start, pre_end)
            end

            result = result .. replacement
            pos = overlap_end
        end
    end

    if pos < end_byte then
        local post_start = str.byte_to_col(text, pos)
        local post_end = str.byte_to_col(text, end_byte) - 1
        result = result .. str.sub(text, post_start, post_end)
    end

    return result
end

---Query treesitter for inline formatting elements within a byte range
---@private
---@param row_node render.md.Node The row node
---@param start_buf integer Start byte in buffer coordinates
---@param end_buf integer End byte in buffer coordinates
---@return table[] elements Array of {start_byte, end_byte, highlight} (buffer coords)
function Render:get_inline_elements(row_node, start_buf, end_buf)
    local elements = {}
    local row = row_node.start_row

    local parser = vim.treesitter.get_parser(self.context.buf, 'markdown')
    if not parser then
        return elements
    end

    local inline_parser = nil
    for lang, child in pairs(parser:children()) do
        if lang == 'markdown_inline' then
            inline_parser = child
            break
        end
    end

    if not inline_parser then
        return elements
    end

    local trees = inline_parser:parse()
    if not trees or #trees == 0 then
        return elements
    end

    local query = ts.parse('markdown_inline', [[
        (strong_emphasis) @strong_emphasis
        (emphasis) @emphasis
        (code_span) @code_span
    ]])

    for _, tree in ipairs(trees) do
        local root = tree:root()
        for id, node in query:iter_captures(root, self.context.buf, row, row + 1) do
            local capture_name = query.captures[id]
            local highlight = inline_highlights[capture_name]
            if highlight then
                local sr, sc, _, ec = node:range()
                if sr == row and ec > start_buf and sc < end_buf then
                    elements[#elements + 1] = {
                        start_byte = sc,
                        end_byte = ec,
                        highlight = highlight,
                    }
                end
            end
        end
    end

    table.sort(elements, function(a, b)
        return a.start_byte < b.start_byte
    end)

    return elements
end

---Process cell content, returning chunks with concealment and inline styling applied
---@private
---@param row_node render.md.Node The row node containing the text
---@param start_byte integer Start byte offset (relative to row start)
---@param end_byte integer End byte offset (relative to row start)
---@param default_highlight string Default highlight for non-styled text
---@return table[] chunks Array of {text, highlight} pairs
function Render:process_cell_content(row_node, start_byte, end_byte, default_highlight)
    local text = row_node.text
    local row_start = row_node.start_col

    local start_buf = row_start + start_byte
    local end_buf = row_start + end_byte

    local conceal_line = self.context.conceal:line(row_node)
    local conceal_ranges = conceal_line.ranges

    local inline_elements = self:get_inline_elements(row_node, start_buf, end_buf)

    local conceal_enabled = self.context.conceal:enabled() and #conceal_ranges > 0
    if not conceal_enabled and #inline_elements == 0 then
        local content_start = str.byte_to_col(text, start_byte)
        local content_end = str.byte_to_col(text, end_byte) - 1
        return { { str.sub(text, content_start, content_end), default_highlight } }
    end

    ---@param buf_byte integer Buffer byte position
    ---@return boolean is_concealed, string replacement
    local function check_conceal(buf_byte)
        for _, range in ipairs(conceal_ranges) do
            if buf_byte >= range[1] and buf_byte < range[2] then
                return true, range[3] or ''
            end
        end
        return false, ''
    end

    ---@param buf_byte integer Buffer byte position
    ---@return string? highlight
    local function get_inline_highlight(buf_byte)
        for _, elem in ipairs(inline_elements) do
            if buf_byte >= elem.start_byte and buf_byte < elem.end_byte then
                return elem.highlight
            end
        end
        return nil
    end

    local bytes = vim.str_utf_pos(text)
    local chunks = {}
    local current_text = ''
    local current_highlight = default_highlight
    local processed_conceal_ranges = {}

    for k, char_start_1idx in ipairs(bytes) do
        local char_byte = char_start_1idx - 1

        if char_byte >= end_byte then
            break
        end
        if char_byte < start_byte then
            goto continue
        end

        local char_end_1idx = k < #bytes and bytes[k + 1] - 1 or #text
        local char = text:sub(char_start_1idx, char_end_1idx)

        local buf_pos = row_start + char_byte
        local is_concealed, replacement = check_conceal(buf_pos)

        if is_concealed then
            if #current_text > 0 then
                chunks[#chunks + 1] = { current_text, current_highlight }
                current_text = ''
            end

            local range_key = nil
            for _, range in ipairs(conceal_ranges) do
                if buf_pos >= range[1] and buf_pos < range[2] then
                    range_key = range[1]
                    break
                end
            end

            if range_key and not processed_conceal_ranges[range_key] and #replacement > 0 then
                processed_conceal_ranges[range_key] = true
                local repl_hl = get_inline_highlight(buf_pos) or default_highlight
                chunks[#chunks + 1] = { replacement, repl_hl }
            end
        else
            local char_highlight = get_inline_highlight(buf_pos) or default_highlight

            if char_highlight ~= current_highlight then
                if #current_text > 0 then
                    chunks[#chunks + 1] = { current_text, current_highlight }
                end
                current_text = char
                current_highlight = char_highlight
            else
                current_text = current_text .. char
            end
        end

        ::continue::
    end

    if #current_text > 0 then
        chunks[#chunks + 1] = { current_text, current_highlight }
    end

    if #chunks == 0 then
        return { { '', default_highlight } }
    end

    return chunks
end

---Build a row Line object using calculated column widths (same approach as delimiter)
---This ensures consistent widths for horizontal scroll alignment
---@private
---@param row render.md.table.Row
---@param highlight string
---@return render.md.Line
function Render:build_row_line(row, highlight)
    local line = self:line()
    local icon = self.config.border[10] -- │
    local delim_cols = self.data.delim.cols

    -- Leading indent (spaces before first pipe)
    line:pad(str.spaces('start', row.node.text))

    -- First pipe
    line:text(icon, highlight)

    for i, col in ipairs(row.cols) do
        local delim_col = delim_cols[i]
        local target_width = delim_col.width

        -- Extract cell content between pipes. process_cell_content
        -- queries treesitter for inline formatting (bold/italic/code)
        -- and applies concealment, returning chunks with per-chunk
        -- highlights. Byte offsets here are relative to the row start;
        -- process_cell_content handles the byte->display-column
        -- conversion for multi-byte glyphs (CJK, emoji).
        local row_start = row.node.start_col
        local content_start_byte = row.pipes[i].end_col - row_start
        local content_end_byte = row.pipes[i + 1].start_col - row_start

        local chunks = self:process_cell_content(
            row.node,
            content_start_byte,
            content_end_byte,
            highlight
        )

        local cell_width = 0
        for _, chunk in ipairs(chunks) do
            cell_width = cell_width + str.width(chunk[1])
            line:text(chunk[1], chunk[2])
        end

        -- Pad to match target width (left-align)
        local fill = target_width - cell_width
        if fill > 0 then
            line:pad(fill)
        end

        -- Separator pipe
        line:text(icon, highlight)
    end

    return line
end

---@private
function Render:delimiter()
    local delim, border = self.data.delim, self.config.border

    local indicator, icon = self.config.alignment_indicator, border[11]
    local parts = iter.list.map(delim.cols, function(col)
        -- must have enough space to put the alignment indicator
        -- alignment indicator must be exactly one character wide
        -- do not put an indicator for default alignment
        local add_indicator = col.width >= 3
            and str.width(indicator) == 1
            and col.alignment ~= Alignment.default
        if not add_indicator then
            return icon:rep(col.width)
        end
        if col.alignment == Alignment.left then
            return indicator .. icon:rep(col.width - 1)
        elseif col.alignment == Alignment.right then
            return icon:rep(col.width - 1) .. indicator
        else
            return indicator .. icon:rep(col.width - 2) .. indicator
        end
    end)
    local delimiter = border[4] .. table.concat(parts, border[5]) .. border[6]

    local line = self:line()
    line:pad(str.spaces('start', delim.node.text))
    line:text(delimiter, self.config.head)
    line:pad(str.width(delim.node.text) - line:width())

    -- Apply leftcol trimming for horizontal scroll. Wrap mode and
    -- hscroll-overlay are mutually exclusive (W5 in
    -- cell-wrapping.allium); when wrap is active the table is
    -- width-bounded to the window, so trim has no work to do.
    local leftcol = not self.data.wrap and self.context.view:get_leftcol() or 0
    local start_col = delim.node.start_col
    local trim_amount = math.max(0, leftcol - start_col)

    if trim_amount > 0 then
        local width = line:width()
        if trim_amount < width then
            line = line:sub(trim_amount + 1, width)
            -- leftcol is a display column but extmark col is a byte
            -- offset; convert via the row's text so multi-byte glyphs
            -- (emoji, CJK) before leftcol don't shift the overlay
            -- into offscreen byte positions.
            local mark_col = str.col_to_byte(delim.node.text, leftcol)
            self.marks:add(self.config, 'table_border', delim.node.start_row, mark_col, {
                virt_text = line:get(),
                virt_text_pos = 'overlay',
            })
        end
    else
        self.marks:over(self.config, 'table_border', delim.node, {
            virt_text = line:get(),
            virt_text_pos = 'overlay',
        })
    end
end

---Pad a wrapped cell line up to its content budget, applying the
---column's alignment. The result has length exactly `content_budget`
---unless the segments themselves overflow it, in which case the
---result is the segments unchanged (per-column floors normally
---prevent this; the math.max guard exists as a safety net).
---@private
---@param segs render.md.mark.Line
---@param content_budget integer
---@param alignment render.md.table.Alignment
---@return render.md.Line
function Render:wrap_pad_cell(segs, content_budget, alignment)
    local line = self:line()
    local seg_width = 0
    for _, seg in ipairs(segs) do
        seg_width = seg_width + str.width(seg[1])
    end
    local fill = math.max(0, content_budget - seg_width)
    if alignment == Alignment.right then
        line:pad(fill)
        for _, seg in ipairs(segs) do
            line:text(seg[1], seg[2])
        end
    elseif alignment == Alignment.center then
        local left = math.floor(fill / 2)
        local right = fill - left
        line:pad(left)
        for _, seg in ipairs(segs) do
            line:text(seg[1], seg[2])
        end
        line:pad(right)
    else
        for _, seg in ipairs(segs) do
            line:text(seg[1], seg[2])
        end
        line:pad(fill)
    end
    return line
end

---Compose a single display line of a wrapped row by concatenating each
---column's wrapped contents at index k (or empty if the column has no
---line k), padded to its budget and surrounded by pipes. Used for both
---the overlay (k=1) and virt_lines (k>=2) emissions. Leading indent
---is handled at the caller site (the buffer source carries it for
---k=1; the `Indent` helper prepends it for virt_lines).
---@private
---@param wrap_row render.md.table.WrapRow
---@param k integer 1-based display-line index
---@param highlight string
---@return render.md.Line
function Render:wrap_compose_line(wrap_row, k, highlight)
    local line = self:line()
    local icon = self.config.border[10]
    local padding = self.config.padding
    local delim_cols = self.data.delim.cols

    line:text(icon, highlight)
    for i, cell_lines in ipairs(wrap_row.cells) do
        local segs = cell_lines[k] or {}
        local budget = delim_cols[i].width
        local content_budget = math.max(1, budget - 2 * padding)
        line:pad(padding)
        local content = self:wrap_pad_cell(
            segs,
            content_budget,
            delim_cols[i].alignment
        )
        line:extend(content)
        line:pad(padding)
        line:text(icon, highlight)
    end
    return line
end

---Render a wrapped row. Display line 1 is emitted as a row-line overlay
---(replacing the buffer line), and lines 2..H are emitted as virt_lines
---anchored to the same buffer row. Hscroll trim is intentionally
---bypassed because wrap is mutually exclusive with hscroll-overlay
---(W5 in cell-wrapping.allium).
---@private
---@param row render.md.table.Row
---@param row_idx integer
function Render:row_wrapped(row, row_idx)
    local wrap_row = self.data.wrap.rows[row_idx]
    local header = row.node.type == 'pipe_table_header'
    local highlight = header and self.config.head or self.config.row

    -- Line 1: replace the buffer line with the first wrapped line.
    local first = self:wrap_compose_line(wrap_row, 1, highlight)
    self.marks:over(self.config, 'table_border', row.node, {
        virt_text = first:get(),
        virt_text_pos = 'overlay',
    })

    if wrap_row.height <= 1 then
        return
    end

    -- Lines 2..H: emit as virt_lines so each occupies its own visual
    -- row underneath the buffer line. Indentation is preserved by
    -- prefixing each virtual line with the same leading spaces /
    -- indent guides as the surrounding context produces.
    local virt_lines = {} ---@type render.md.mark.Line[]
    for k = 2, wrap_row.height do
        local line = self:wrap_compose_line(wrap_row, k, highlight)
        local full = self:indent():line(true):extend(line)
        virt_lines[#virt_lines + 1] = full:get()
    end
    if #virt_lines > 0 then
        self.marks:add(
            self.config,
            'virtual_lines',
            row.node.start_row,
            0,
            { virt_lines = virt_lines }
        )
    end
end

---@private
---@param row render.md.table.Row
function Render:row(row)
    local icon = self.config.border[10]
    local header = row.node.type == 'pipe_table_header'
    local highlight = header and self.config.head or self.config.row
    local leftcol = self.context.view:get_leftcol()

    -- When horizontally scrolled, use full-line overlay with calculated widths
    -- This matches delimiter()'s approach to ensure consistent alignment
    if leftcol > 0 then
        local line = self:build_row_line(row, highlight)
        local start_col = row.node.start_col
        local trim_amount = math.max(0, leftcol - start_col)

        if trim_amount > 0 then
            local width = line:width()
            if trim_amount < width then
                line = line:sub(trim_amount + 1, width)
                -- leftcol is a display column but extmark col is a
                -- byte offset; convert via the row's text so rows
                -- containing multi-byte glyphs before leftcol (emoji,
                -- CJK) don't land the overlay at the wrong screen
                -- position.
                local mark_col = str.col_to_byte(row.node.text, leftcol)
                self.marks:add(self.config, 'table_border', row.node.start_row, mark_col, {
                    virt_text = line:get(),
                    virt_text_pos = 'overlay',
                })
            end
        else
            self.marks:over(self.config, 'table_border', row.node, {
                virt_text = line:get(),
                virt_text_pos = 'overlay',
            })
        end
        return
    end

    -- When cell='wrap' but wrap didn't activate (table fits / window
    -- too narrow), fall through to padded behaviour for this row.
    local effective_cell = self.config.cell
    if effective_cell == 'wrap' then
        effective_cell = 'padded'
    end

    if vim.tbl_contains({ 'trimmed', 'padded', 'raw' }, effective_cell) then
        for _, pipe in ipairs(row.pipes) do
            self.marks:over(self.config, 'table_border', pipe, {
                virt_text = { { icon, highlight } },
                virt_text_pos = 'overlay',
            })
        end
    end

    if vim.tbl_contains({ 'trimmed', 'padded' }, effective_cell) then
        for i, col in ipairs(row.cols) do
            local delim = self.data.delim.cols[i]
            local space = col.space
            local fill = delim.width - col.width
            -- delim(20) : --------------------
            -- col(4,7,2): ----XXXXXXX--
            -- fill(7)   :              _______
            if not self.context.conceal:enabled() then
                -- result: ----XXXXXXX--_______
                -- without concealing it is impossible to do full alignment
                self:shift(col, 'right', fill)
            elseif delim.alignment == Alignment.center then
                -- (7 + 2 - 4) // 2 = 5 // 2 = 2 -> move two spaces to the right
                -- result: __----XXXXXXX--_____
                local shift = math.floor((fill + space.right - space.left) / 2)
                self:shift(col, 'left', shift)
                self:shift(col, 'right', fill - shift)
            elseif delim.alignment == Alignment.right then
                -- 2 - 1 = 1 -> conceal one space on right side
                -- result: -_______----XXXXXXX-
                local shift = space.right - self.config.padding
                self:shift(col, 'left', fill + shift)
                self:shift(col, 'right', -shift)
            else
                -- 4 - 1 = 3 -> conceal three spaces on left side
                -- result: -XXXXXXX--_______---
                local shift = space.left - self.config.padding
                self:shift(col, 'left', -shift)
                self:shift(col, 'right', fill + shift)
            end
        end
    elseif effective_cell == 'overlay' then
        self.marks:over(self.config, 'table_border', row.node, {
            virt_text = { { row.node.text:gsub('|', icon), highlight } },
            virt_text_pos = 'overlay',
        })
    end
end

---Use low priority to include pipe marks
---@private
---@param col render.md.table.Col
---@param side 'left'|'right'
---@param amount integer
function Render:shift(col, side, amount)
    local column = side == 'left' and col.start_col or col.end_col
    if amount > 0 then
        self.marks:add(self.config, true, col.row, column, {
            priority = 0,
            virt_text = self:line():pad(amount, self.config.filler):get(),
            virt_text_pos = 'inline',
        })
    elseif amount < 0 then
        amount = amount - self.context.conceal:width('', 1)
        self.marks:add(self.config, true, col.row, column + amount, {
            priority = 0,
            end_col = column,
            conceal = '',
        })
    end
end

---@private
function Render:border()
    local delim = self.data.delim
    local rows = self.data.rows
    local border = self.config.border

    ---@param row render.md.table.Row
    ---@return boolean
    local function width_equal(row)
        if vim.tbl_contains({ 'trimmed', 'padded' }, self.config.cell) then
            -- assume table was modified to match
            return true
        elseif self.config.cell == 'wrap' then
            -- wrap mode rebuilds rows to delim widths (active path) or
            -- falls through to padded (inactive path) - either way the
            -- row widths visually match the delimiter
            return true
        elseif self.config.cell == 'raw' then
            -- want the computed widths to match
            for i, col in ipairs(row.cols) do
                if delim.cols[i].width ~= col.width then
                    return false
                end
            end
            return true
        elseif self.config.cell == 'overlay' then
            -- want the underlying text widths to match
            return str.width(delim.node.text) == str.width(row.node.text)
        else
            return false
        end
    end

    local first, last = rows[1], rows[#rows]
    if not width_equal(first) or not width_equal(last) then
        return
    end

    ---@param node render.md.Node
    ---@return integer
    local function get_spaces(node)
        local _, line = node:line('first', 0)
        return math.max(str.spaces('start', line or ''), node.start_col)
    end

    local first_node = first.node
    local last_node = #rows == 1 and delim.node or last.node
    local spaces = get_spaces(first_node)
    if spaces ~= get_spaces(last_node) then
        return
    end

    local sections = iter.list.map(delim.cols, function(col)
        return border[11]:rep(col.width)
    end)

    ---@param node render.md.Node
    ---@param above boolean
    ---@param chars { [1]: string, [2]: string, [3]: string }
    local function table_border(node, above, chars)
        local text = chars[1] .. table.concat(sections, chars[2]) .. chars[3]
        local highlight = above and self.config.head or self.config.row
        local line = self:line():pad(spaces):text(text, highlight)

        local virtual = self.config.border_virtual
        local row, target = node:line(above and 'above' or 'below', 1)
        local available = target and str.width(target) == 0

        -- Apply leftcol trimming for horizontal scroll
        local leftcol = self.context.view:get_leftcol()

        if not virtual and available and self.context.used:take(row) then
            -- Overlay mode: trim line and render at leftcol position
            if leftcol > 0 then
                local width = line:width()
                if leftcol < width then
                    line = line:sub(leftcol + 1, width)
                else
                    return
                end
            end
            self.marks:add(self.config, 'table_border', row, leftcol, {
                virt_text = line:get(),
                virt_text_pos = 'overlay',
            })
        else
            -- Virtual lines mode: trim full line including indent
            local full_line = self:indent():line(true):extend(line)
            if leftcol > 0 then
                local width = full_line:width()
                if leftcol < width then
                    full_line = full_line:sub(leftcol + 1, width)
                else
                    return
                end
            end
            self.marks:add(self.config, 'virtual_lines', node.start_row, 0, {
                virt_lines = { full_line:get() },
                virt_lines_above = above,
            })
        end
    end

    table_border(first_node, true, { border[1], border[2], border[3] })
    if #rows > 1 then
        table_border(last_node, false, { border[7], border[8], border[9] })
    end
end

return Render
