---@module 'luassert'

-- Regression coverage for buffer lifecycle and multi-buffer scenarios.
-- Written against current code to establish a baseline before a
-- refactor that touches the per-buffer caches in state.lua,
-- core/ui.lua, request/context.lua, and core/manager.lua. These tests
-- assert properties that must hold both before and after the refactor.
-- Properties specific to the new cleanup semantics (timer closed,
-- cache entries pruned on BufDelete, etc.) live in
-- buffer_state_spec.lua alongside the buffer_state module.

local util = require('tests.util')

describe('buffer lifecycle', function()
    describe('multi-buffer rendering', function()
        local md_a = { '# Heading A', '', 'some paragraph' }
        local md_b = { '# Heading B', '', '- item one', '- item two' }

        ---Initialize the plugin via setup.text and return its scratch buf.
        local function init_with(lines)
            util.setup.text(lines)
            util.setup.view({ leftcol = 0 })
            return vim.api.nvim_get_current_buf()
        end

        ---Create an additional scratch buffer without re-initializing
        ---the plugin (setup.init clears all namespaces, which would
        ---wipe prior buffers' marks - not what a multi-buffer test
        ---wants to observe).
        local function add_buf(lines)
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(buf)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].filetype = 'markdown'
            vim.wait(0)
            require('render-markdown.api').render({ buf = buf, win = vim.api.nvim_get_current_win() })
            vim.wait(0)
            return buf
        end

        local function mark_count(buf)
            local ui = require('render-markdown.core.ui')
            return #vim.api.nvim_buf_get_extmarks(buf, ui.ns, 0, -1, {})
        end

        it('renders two different buffers in sequence', function()
            local buf_a = init_with(md_a)
            local n_a = mark_count(buf_a)
            assert(n_a > 0, 'buffer A should have marks')

            local buf_b = add_buf(md_b)
            local n_b = mark_count(buf_b)
            assert(n_b > 0, 'buffer B should have marks')

            -- Rendering B must not touch A's marks
            assert.equals(
                n_a,
                mark_count(buf_a),
                'rendering buffer B should not change buffer A marks'
            )
        end)

        it('returning to a prior buffer re-renders correctly', function()
            local buf_a = init_with(md_a)
            local n_a = mark_count(buf_a)

            add_buf(md_b)

            -- Switch back to A and re-render
            vim.api.nvim_set_current_buf(buf_a)
            util.setup.view({ leftcol = 0 })
            assert(mark_count(buf_a) > 0, 'buffer A should still have marks after switching back')
            assert.equals(n_a, mark_count(buf_a), 'buffer A mark count should be stable')
        end)

        it('each buffer has its own Decorator entry', function()
            local buf_a = init_with(md_a)
            local buf_b = add_buf(md_b)

            local ui = require('render-markdown.core.ui')
            local dec_a = ui.get(buf_a)
            local dec_b = ui.get(buf_b)

            assert(dec_a ~= nil, 'decorator for A should exist')
            assert(dec_b ~= nil, 'decorator for B should exist')
            assert(dec_a ~= dec_b, 'decorators should be distinct objects')
        end)

        it('each buffer has its own Config entry', function()
            local buf_a = init_with(md_a)
            local buf_b = add_buf(md_b)

            local state = require('render-markdown.state')
            local cfg_a = state.get(buf_a)
            local cfg_b = state.get(buf_b)
            assert(cfg_a ~= nil, 'config for A should exist')
            assert(cfg_b ~= nil, 'config for B should exist')
        end)
    end)

    describe('buffer deletion does not break subsequent renders', function()
        local md = { '# Heading', '', 'paragraph' }

        it('deleting a rendered buffer then rendering a fresh one works', function()
            util.setup.text(md)
            util.setup.view({ leftcol = 0 })
            local buf_a = vim.api.nvim_get_current_buf()
            assert(vim.api.nvim_buf_is_valid(buf_a))

            -- Delete buffer A
            vim.api.nvim_buf_delete(buf_a, { force = true })
            assert(not vim.api.nvim_buf_is_valid(buf_a))

            -- Now render a fresh buffer; it must still work
            util.setup.text(md)
            util.setup.view({ leftcol = 0 })
            local buf_b = vim.api.nvim_get_current_buf()
            assert(buf_b ~= buf_a, 'new buffer should have a different id')

            local ui = require('render-markdown.core.ui')
            local marks = vim.api.nvim_buf_get_extmarks(buf_b, ui.ns, 0, -1, {})
            assert(#marks > 0, 'new buffer should render after prior was deleted')
        end)

        it('creating and deleting 10 buffers in a loop does not crash', function()
            for _ = 1, 10 do
                util.setup.text(md)
                util.setup.view({ leftcol = 0 })
                local buf = vim.api.nvim_get_current_buf()
                vim.api.nvim_buf_delete(buf, { force = true })
            end
            -- Smoke: one more render still works
            util.setup.text(md)
            util.setup.view({ leftcol = 0 })
            local buf = vim.api.nvim_get_current_buf()
            local ui = require('render-markdown.core.ui')
            assert(#vim.api.nvim_buf_get_extmarks(buf, ui.ns, 0, -1, {}) > 0)
        end)
    end)

    describe('manager attach tracking', function()
        it('attached buffer reports attached=true; fresh buffer reports false', function()
            util.setup.text({ '# A', '', 'text' })
            util.setup.view({ leftcol = 0 })
            local buf = vim.api.nvim_get_current_buf()

            local manager = require('render-markdown.core.manager')
            assert.equals(true, manager.attached(buf))

            -- A brand new unrelated buffer that was never attached
            local fresh = vim.api.nvim_create_buf(false, true)
            assert.equals(false, manager.attached(fresh))
            vim.api.nvim_buf_delete(fresh, { force = true })
        end)
    end)
end)
