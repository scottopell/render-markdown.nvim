local Base = require('render-markdown.render.base')
local env = require('render-markdown.lib.env')

---Wraps text at specified width using word boundaries
---@param text string Text to wrap
---@param width number Maximum width per line
---@return string[] Wrapped lines
local function wrap_text(text, width)
    local lines = {}
    local current = ''

    for word in text:gmatch('%S+') do
        local test_line = current == '' and word or (current .. ' ' .. word)
        if #test_line <= width then
            current = test_line
        else
            if current ~= '' then
                table.insert(lines, current)
            end
            current = word
        end
    end

    if current ~= '' then
        table.insert(lines, current)
    end

    return lines
end

---@class render.md.paragraph.Data
---@field margin number
---@field indent number

---@class render.md.render.Paragraph: render.md.Render
---@field private config render.md.paragraph.Config
---@field private data render.md.paragraph.Data
local Render = setmetatable({}, Base)
Render.__index = Render

---@protected
---@return boolean
function Render:setup()
    self.config = self.context.config.paragraph
    if not self.config.enabled then
        return false
    end
    local margin = self:get_number(self.config.left_margin)
    local indent = self:get_number(self.config.indent)
    local reader_width = self.context.config.reader_width
    -- When reader_width is enabled, we need to render paragraphs even if margin/indent are 0
    -- because we need to add center_offset padding for centering (REQ-RW-010)
    if margin <= 0 and indent <= 0 and (not reader_width or reader_width <= 0) then
        return false
    end
    self.data = { margin = margin, indent = indent }
    return true
end

---@private
---@param value render.md.paragraph.Number
---@return number
function Render:get_number(value)
    if type(value) == 'function' then
        return value({ text = self.node.text })
    else
        return value
    end
end

---@protected
function Render:run()
    local widths = self.node:widths()
    local width = math.max(vim.fn.max(widths), self.config.min_width)
    local reader_width = self.context.config.reader_width
    local center_offset = env.win.center_offset(self.context.win, reader_width)
    local user_margin = env.win.percent(self.context.win, self.data.margin, width, reader_width)
    local margin = center_offset + user_margin

    -- Check if we need to wrap text at reader_width boundary (REQ-RW-003)
    if reader_width and reader_width > 0 then
        local text = self.node.text:gsub('\n', ' ') -- Join multi-line paragraphs
        local text_width = vim.fn.strdisplaywidth(text)

        -- Calculate marker width adjustment for blockquotes and lists
        local marker_width = self:calculate_marker_width()
        local marker_info = self:get_marker_info()

        -- Only apply wrapping if text exceeds available width
        local effective_width = reader_width - marker_width
        if text_width > effective_width then
            self:wrap_paragraph(text, effective_width, center_offset, marker_width, marker_info)
            return
        elseif marker_info and center_offset > 0 then
            -- Non-wrapped paragraph with centering and marker: create virtual line with marker
            self:render_centered_line(text, center_offset, marker_width, marker_info)
            return
        end
    end

    -- Default behavior: just add padding without wrapping
    self:padding(self.node.start_row, self.node.end_row - 1, margin)
    local indent = env.win.percent(self.context.win, self.data.indent, width, reader_width)
    self:padding(self.node.start_row, self.node.start_row, indent)
end

---Calculates the display width used by list markers and blockquote markers
---@private
---@return number Width in characters
function Render:calculate_marker_width()
    local width = 0

    -- Check if paragraph is inside a blockquote
    local in_blockquote = self.node:parent('block_quote')
    if in_blockquote then
        -- Blockquote marker (▋) + space typically uses ~2 characters
        local quote_config = self.context.config.quote
        if quote_config and quote_config.enabled then
            width = width + 2
        end
    end

    -- Check if paragraph is inside a list item
    local in_list = self.node:parent('list_item')
    if in_list then
        -- List marker (●, ○, etc.) + space typically uses ~2 characters
        local bullet_config = self.context.config.bullet
        if bullet_config and bullet_config.enabled then
            width = width + 2
        end
    end

    return width
end

---Gets marker information (icon, highlight) if paragraph is inside a blockquote or list
---@private
---@return {icon: string, highlight: string}? Marker info or nil
function Render:get_marker_info()
    -- Check if paragraph is inside a blockquote
    local in_blockquote = self.node:parent('block_quote')
    if in_blockquote then
        local quote_config = self.context.config.quote
        if quote_config and quote_config.enabled and quote_config.icon then
            return {
                icon = quote_config.icon .. ' ',
                highlight = quote_config.highlight or 'RenderMarkdownQuote'
            }
        end
    end

    -- Check if paragraph is inside a list item
    local in_list = self.node:parent('list_item')
    if in_list then
        local bullet_config = self.context.config.bullet
        if bullet_config and bullet_config.enabled then
            -- Get the list marker to determine icon
            local marker = in_list:child_at(0)
            if marker then
                local level = in_list:level_in('list', 'section')
                local index = in_list:sibling_count('list_item')
                local bullet_ctx = { level = level, index = index, value = marker.text }

                -- Determine if ordered or unordered list
                local ordered_types = { 'list_marker_dot', 'list_marker_parenthesis' }
                local ordered = vim.tbl_contains(ordered_types, marker.type)
                local icons = ordered and bullet_config.ordered_icons or bullet_config.icons

                -- Get icon (similar to bullet.lua logic)
                local icon
                if type(icons) == 'function' then
                    icon = icons(bullet_ctx)
                else
                    local value = icons[((level - 1) % #icons) + 1]
                    if type(value) == 'table' then
                        icon = value[math.min(index, #value)]
                    else
                        icon = value
                    end
                end

                -- Get highlight
                local highlight
                if type(bullet_config.highlight) == 'function' then
                    highlight = bullet_config.highlight(bullet_ctx)
                else
                    highlight = bullet_config.highlight
                end

                if icon and highlight then
                    return {
                        icon = icon .. ' ',
                        highlight = highlight
                    }
                end
            end
        end
    end

    return nil
end

---@private
---@param start_row integer
---@param end_row integer
---@param amount integer
function Render:padding(start_row, end_row, amount)
    local line = self:line():pad(amount):get()
    if #line == 0 then
        return
    end
    for row = start_row, end_row do
        self.marks:add(self.config, false, row, 0, {
            priority = 100,
            virt_text = line,
            virt_text_pos = 'inline',
        })
    end
end

---Renders a single centered line with marker (non-wrapped paragraph with centering)
---@private
---@param text string Paragraph text
---@param center_offset number Left padding for centering
---@param marker_width number Width used by marker
---@param marker_info {icon: string, highlight: string} Marker to include
function Render:render_centered_line(text, center_offset, marker_width, marker_info)
    -- Create single virtual line with marker and text
    local marker_padding = string.rep(' ', center_offset)
    local text_padding = string.rep(' ', marker_width - vim.fn.strdisplaywidth(marker_info.icon))
    local line = {
        { marker_padding .. marker_info.icon, marker_info.highlight },
        { text_padding .. text, 'Normal' }
    }

    -- Add virtual line above the original paragraph
    self.marks:add(self.config, false, self.node.start_row, 0, {
        priority = 100,
        virt_lines = { line },
        virt_lines_above = true,
    })

    -- Conceal original paragraph line (including marker)
    for row = self.node.start_row, self.node.end_row - 1 do
        local line_content = vim.api.nvim_buf_get_lines(self.context.buf, row, row + 1, false)[1]
        if line_content then
            self.marks:add(self.config, false, row, 0, {
                priority = 100,
                end_col = #line_content,
                conceal = '',
            })
        end
    end
end

---Wraps paragraph at reader_width boundary using virtual lines + concealment
---This achieves REQ-RW-003: text wrapping at reader_width instead of window edge
---Accounts for blockquote and list markers when calculating available width
---@private
---@param text string Full paragraph text
---@param effective_width number Maximum width before wrapping (already accounts for markers)
---@param center_offset number Left padding for centering
---@param marker_width number Width used by blockquote/list markers
---@param marker_info {icon: string, highlight: string}? Optional marker to include in first line
function Render:wrap_paragraph(text, effective_width, center_offset, marker_width, marker_info)
    -- Wrap text at effective width (reader_width - marker_width)
    local wrapped_lines = wrap_text(text, effective_width)

    -- Create virtual lines with centering and marker offset for each wrapped line
    local virt_lines = {}
    for i, line_text in ipairs(wrapped_lines) do
        if i == 1 and marker_info then
            -- First line: include marker at center_offset, text at center_offset + marker_width
            local marker_padding = string.rep(' ', center_offset)
            local text_padding = string.rep(' ', marker_width - vim.fn.strdisplaywidth(marker_info.icon))
            local line = {
                { marker_padding .. marker_info.icon, marker_info.highlight },
                { text_padding .. line_text, 'Normal' }
            }
            table.insert(virt_lines, line)
        else
            -- Continuation lines: just text with full padding
            local padding = string.rep(' ', center_offset + marker_width)
            local centered = padding .. line_text
            table.insert(virt_lines, { { centered, 'Normal' } })
        end
    end

    -- Add virtual lines above the original paragraph
    self.marks:add(self.config, false, self.node.start_row, 0, {
        priority = 100,
        virt_lines = virt_lines,
        virt_lines_above = true,
    })

    -- Conceal all original lines of the paragraph (including markers on the same line)
    for row = self.node.start_row, self.node.end_row - 1 do
        local line_content = vim.api.nvim_buf_get_lines(self.context.buf, row, row + 1, false)[1]
        if line_content then
            self.marks:add(self.config, false, row, 0, {
                priority = 100,
                end_col = #line_content,
                conceal = '',
            })
        end
    end
end

return Render
