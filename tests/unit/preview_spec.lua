---@module 'luassert'

-- Tests for core/preview.lua after its migration to buffer_state.
-- Zero coverage existed before; these tests also document the
-- src-buffer-dies-first leak that the migration closes (which was a
-- real bug on the pre-migration code path).

local util = require('tests.util')

describe('preview', function()
    local function open_md(lines)
        util.setup.text(lines or { '# Heading', '', 'para' })
        return vim.api.nvim_get_current_buf()
    end

    describe('open / toggle', function()
        it('creates a dst buffer and maps src -> dst', function()
            local preview = require('render-markdown.core.preview')
            local src = open_md()
            preview.open(src)

            local entry = preview._store:peek(src)
            assert.is_not_nil(entry, 'store should hold an entry for src')
            assert(
                vim.api.nvim_buf_is_valid(entry.dst),
                'dst buffer should be valid'
            )
            assert.equals(src, preview.get(entry.dst))
        end)

        it('a second open(src) wipes the dst buffer and drops the entry', function()
            local preview = require('render-markdown.core.preview')
            local src = open_md()
            preview.open(src)
            local entry = preview._store:peek(src)
            local dst = entry.dst

            preview.open(src) -- toggle off
            vim.wait(50)

            assert.is_nil(preview._store:peek(src))
            assert.equals(
                false,
                vim.api.nvim_buf_is_valid(dst),
                'dst should be wiped after toggle'
            )
        end)

        it('returning src rendering after toggle-off', function()
            local preview = require('render-markdown.core.preview')
            local manager = require('render-markdown.core.manager')
            local src = open_md()
            assert.equals(true, manager.attached(src))

            preview.open(src)
            -- rendering is disabled on src while preview is open
            preview.open(src) -- toggle off
            vim.wait(50)

            -- After toggle-off the src is still attached and its
            -- config.enabled has been restored by destroy().
            assert.equals(true, manager.attached(src))
            local state = require('render-markdown.state')
            assert.equals(true, state.get(src).enabled)
        end)
    end)

    describe('dst wipeout path', function()
        it('wiping dst directly drops the store entry and re-enables src', function()
            local preview = require('render-markdown.core.preview')
            local state = require('render-markdown.state')
            local src = open_md()
            preview.open(src)
            local dst = preview._store:peek(src).dst

            -- User closes the preview window, which wipes dst via
            -- bufhidden=wipe (or directly wipes the buffer).
            vim.api.nvim_buf_delete(dst, { force = true })
            vim.wait(50)

            assert.is_nil(preview._store:peek(src))
            assert.equals(
                true,
                state.get(src).enabled,
                'src rendering should be re-enabled after dst wipe'
            )
        end)
    end)

    describe('src death during active preview', function()
        -- This test documents the lifecycle guarantee added by the
        -- buffer_state migration. On pre-migration code, the mapping
        -- was tracked in an M.buffers table keyed by src_buf with
        -- cleanup wired to dst's BufWipeout autocmd. Killing src
        -- while dst was alive left an orphaned dst pointing at a
        -- dead src and a stale entry in the mapping. After the
        -- migration, buffer_state's on_detach hook fires when nvim
        -- destroys src and calls the preview store's destroy, which
        -- wipes dst as a side effect.
        it('deleting src with an active preview wipes dst and clears the entry', function()
            local preview = require('render-markdown.core.preview')
            local src = open_md()
            preview.open(src)
            local dst = preview._store:peek(src).dst
            assert(vim.api.nvim_buf_is_valid(dst))

            vim.api.nvim_buf_delete(src, { force = true })
            -- buffer_state on_detach is synchronous-ish; poll briefly
            vim.wait(100, function()
                return not vim.api.nvim_buf_is_valid(dst)
            end)

            assert.equals(
                false,
                vim.api.nvim_buf_is_valid(src),
                'src should be gone'
            )
            assert.equals(
                false,
                vim.api.nvim_buf_is_valid(dst),
                'dst should be wiped when src is deleted (was the pre-migration leak)'
            )
            assert.is_nil(
                preview._store:peek(src),
                'preview entry for src should be dropped'
            )
        end)
    end)

    describe('store lifecycle integration', function()
        it('open / toggle cycles leave the preview store at baseline entry count', function()
            local preview = require('render-markdown.core.preview')
            local buffer_state = require('render-markdown.lib.buffer_state')
            local baseline = buffer_state._entry_count('preview')

            for _ = 1, 5 do
                local src = open_md()
                preview.open(src)
                preview.open(src) -- toggle off
                vim.wait(20)
            end
            vim.wait(50)

            assert.equals(
                baseline,
                buffer_state._entry_count('preview'),
                'preview store should return to baseline after toggle cycles'
            )
        end)
    end)
end)
