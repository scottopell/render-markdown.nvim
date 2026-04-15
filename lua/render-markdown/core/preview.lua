local buffer_state = require('render-markdown.lib.buffer_state')
local env = require('render-markdown.lib.env')
local manager = require('render-markdown.core.manager')

---@class render.md.Preview
local M = {}

---@private
M.group = vim.api.nvim_create_augroup('RenderMarkdownPreview', {})

---@class render.md.preview.Entry
---@field src integer the source buffer
---@field dst integer the destination (preview) buffer

---@private
---Store keyed by src_buf, value is an Entry with src + dst. The
---destructor is invoked in two situations:
---  * the user toggles the preview off (M.open called a second
---    time for an already-previewed src), which calls store:drop;
---  * the src buffer is deleted via nvim_buf_delete or any other
---    form of buffer death, which buffer_state's on_detach hook
---    converts into store:drop via the registry-wide detach sweep.
---
---In either situation the destructor:
---  * wipes the dst buffer if it is still valid (it may not be
---    during reentry from the dst BufWipeout autocmd);
---  * clears the src's preview-scoped autocmds if src is still
---    valid (clearing autocmds on an invalid buffer errors);
---  * re-enables rendering for src if src is still valid and
---    still attached to the plugin.
---
---Before this migration, the cleanup path above lived in a
---BufWipeout autocmd on the dst buffer. That autocmd only fires
---when dst is wiped, so killing src while dst was alive left an
---orphaned dst pointing at a dead src and a stale entry in the
---mapping table. The on_detach flow inherited from buffer_state
---closes that leak.
---@type render.md.buffer_state.Store
M._store = buffer_state.define_cache('preview', {
    make = function(src_buf)
        local dst_buf = M._build_dst(src_buf)
        M._wire_src_autocmds(src_buf, dst_buf)
        M._wire_dst_wipeout(src_buf, dst_buf)
        -- disable rendering for the source buffer so the preview
        -- shows the rendered markdown and the source shows raw text
        manager.set_buf(src_buf, false)
        return { src = src_buf, dst = dst_buf }
    end,
    destroy = function(entry)
        -- destroy fires in three contexts:
        --   1. user toggles preview off via M.open: no textlock,
        --      direct buffer mutations are legal;
        --   2. dst's own BufWipeout autocmd: dst is mid-wipe, so
        --      re-wiping it raises E937;
        --   3. src's on_detach fires during nvim_buf_delete(src):
        --      nvim is in textlock and synchronous buffer or
        --      window mutation raises E565.
        --
        -- All three are handled by deferring the dst wipe and the
        -- src set_buf to vim.schedule. That pushes the work out
        -- of any restricted context; the inner is_valid checks
        -- turn the already-wiped case (2) into a no-op, and the
        -- valid case (1, 3) completes on the next event loop tick.
        --
        -- Callers that want to observe the teardown synchronously
        -- (for tests, mostly) need to vim.wait until is_valid(dst)
        -- flips to false. The M.open toggle path already fits this
        -- shape and existing preview tests confirm the scheduled
        -- wipe lands within a single vim.wait(50).
        local dst = entry.dst
        local src = entry.src
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(dst) then
                pcall(vim.api.nvim_buf_delete, dst, { force = true })
            end
            if vim.api.nvim_buf_is_valid(src) then
                pcall(vim.api.nvim_clear_autocmds, {
                    group = M.group,
                    buffer = src,
                })
                if manager.attached(src) then
                    manager.set_buf(src, true)
                end
            end
        end)
    end,
})

---@param dst_buf integer
---@return integer? src buffer that owns dst_buf, or nil
function M.get(dst_buf)
    local result = nil
    M._store:for_each(function(src, entry)
        if entry.dst == dst_buf then
            result = src
        end
    end)
    return result
end

---@param src_buf? integer
function M.open(src_buf)
    src_buf = src_buf or env.buf.current()
    if not manager.attached(src_buf) then
        return
    end
    if M._store:peek(src_buf) ~= nil then
        -- toggle off: drop the entry, which destroy() wipes dst and
        -- re-enables src rendering
        M._store:drop(src_buf)
        return
    end
    -- toggle on: create via make
    M._store:get(src_buf)
end

---@private
---@param src_buf integer
---@return integer dst_buf
function M._build_dst(src_buf)
    local dst_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(dst_buf, false, { split = 'right' })

    env.buf.set(dst_buf, 'bufhidden', 'wipe')
    env.buf.set(dst_buf, 'buftype', 'nofile')
    env.buf.set(dst_buf, 'filetype', env.buf.get(src_buf, 'filetype'))
    env.buf.set(dst_buf, 'modifiable', false)
    env.buf.set(dst_buf, 'swapfile', false)

    M.copy_lines(src_buf, dst_buf)
    M.copy_cursor(env.buf.win(src_buf), env.buf.win(dst_buf))

    return dst_buf
end

---@private
---@param src_buf integer
---@param dst_buf integer
function M._wire_src_autocmds(src_buf, dst_buf)
    local src_win = env.buf.win(src_buf)
    local dst_win = env.buf.win(dst_buf)

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = M.group,
        buffer = src_buf,
        callback = function(args)
            if env.valid(src_buf, src_win) and env.valid(dst_buf, dst_win) then
                M.copy_cursor(src_win, dst_win)
                M.copy_event(args, dst_buf)
            end
        end,
    })

    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = M.group,
        buffer = src_buf,
        callback = function(args)
            if env.valid(src_buf, src_win) and env.valid(dst_buf, dst_win) then
                -- also need to copy cursor due to event ordering
                M.copy_lines(src_buf, dst_buf)
                M.copy_cursor(src_win, dst_win)
                M.copy_event(args, dst_buf)
            end
        end,
    })
end

---@private
---@param src_buf integer
---@param dst_buf integer
function M._wire_dst_wipeout(src_buf, dst_buf)
    vim.api.nvim_create_autocmd('BufWipeout', {
        group = M.group,
        buffer = dst_buf,
        once = true,
        callback = function()
            -- Dropping the entry from the store calls destroy(),
            -- which handles clearing the src autocmds and
            -- re-enabling rendering. destroy() also tries to
            -- wipe dst - but dst is already mid-wipe when we get
            -- here, so the is_valid guard inside destroy() makes
            -- that a no-op.
            M._store:drop(src_buf)
        end,
    })
end

---@private
---@param src integer
---@param dst integer
function M.copy_lines(src, dst)
    local src_lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
    local dst_lines = vim.api.nvim_buf_get_lines(dst, 0, -1, false)

    local src_text = table.concat(src_lines, '\n') .. '\n'
    local dst_text = table.concat(dst_lines, '\n') .. '\n'
    local diff = vim.diff(dst_text, src_text, { result_type = 'indices' })
    assert(type(diff) == 'table', 'diff must provide indices')

    env.buf.set(dst, 'modifiable', true)
    for i = 1, #diff do
        local hunk = diff[#diff - i + 1]
        local start_a, count_a, start_b, count_b = unpack(hunk)
        local line_start = start_a - 1
        local line_end = start_a + count_a - 1
        if count_a == 0 then
            line_start = line_start + 1
            line_end = line_end + 1
        end
        vim.api.nvim_buf_set_lines(dst, line_start, line_end, false, {
            unpack(src_lines, start_b, start_b + count_b - 1),
        })
    end
    env.buf.set(dst, 'modifiable', false)
end

---@private
---@param src integer
---@param dst integer
function M.copy_cursor(src, dst)
    local cursor = vim.api.nvim_win_get_cursor(src)
    pcall(vim.api.nvim_win_set_cursor, dst, cursor)
end

---@private
---@param args vim.api.keyset.create_autocmd.callback_args
---@param buf integer
function M.copy_event(args, buf)
    vim.api.nvim_exec_autocmds(args.event, { buffer = buf })
end

return M
