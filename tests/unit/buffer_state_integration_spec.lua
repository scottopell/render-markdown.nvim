---@module 'luassert'

-- Integration tests for the buffer_state lifecycle guarantees as
-- wired up through the real plugin (state.lua, core/ui.lua,
-- request/context.lua, core/manager.lua). Each test asserts a
-- property that was not true on the pre-refactor code:
--
--   * decorator timer is stopped and closed on buffer deletion
--   * per-buffer config / decorator / context entries are pruned
--     from every cache on buffer deletion
--   * manager.attached(buf) returns false after the buffer is gone
--   * no buffer-keyed table grows unboundedly across repeated
--     open/close cycles

local util = require('tests.util')
local buffer_state = require('render-markdown.lib.buffer_state')

describe('buffer_state integration', function()
    ---Add a rendered scratch buffer without re-initializing the plugin.
    ---@return integer
    local function add_rendered_buf()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '# Heading',
            '',
            'paragraph text',
            '',
            '| A | B |',
            '|---|---|',
            '| x | y |',
        })
        vim.bo[buf].filetype = 'markdown'
        vim.wait(0)
        require('render-markdown.api').render({
            buf = buf,
            win = vim.api.nvim_get_current_win(),
        })
        vim.wait(0)
        return buf
    end

    ---Wait until `predicate` returns true or the 100 ms timeout expires.
    local function wait_for(predicate)
        vim.wait(100, predicate)
    end

    describe('decorator timer lifecycle', function()
        it("closes the decorator's uv_timer when its buffer dies", function()
            util.setup.text({ '# Top', 'para' }) -- init plugin
            local buf = add_rendered_buf()

            local ui = require('render-markdown.core.ui')
            local decorator = ui.get(buf)
            local timer = decorator.timer
            assert(timer ~= nil, 'decorator should own a timer')
            -- A valid uv_timer responds to is_closing() with false
            assert.equals(false, timer:is_closing())

            vim.api.nvim_buf_delete(buf, { force = true })
            wait_for(function()
                return timer:is_closing()
            end)

            assert.equals(
                true,
                timer:is_closing(),
                "decorator timer must be closed after buffer deletion "
                    .. "(was not before the buffer_state refactor)"
            )
        end)

        it('never lets the decorator store hold a dead buffer', function()
            util.setup.text({ '# Top', 'para' })
            local buf = add_rendered_buf()

            local ui = require('render-markdown.core.ui')
            assert.is_not_nil(ui._store:peek(buf))

            vim.api.nvim_buf_delete(buf, { force = true })
            wait_for(function() return ui._store:peek(buf) == nil end)

            assert.is_nil(
                ui._store:peek(buf),
                'decorator cache entry must be gone after bufdelete'
            )
        end)
    end)

    describe('state cache lifecycle', function()
        it('state store drops its entry on buffer deletion', function()
            util.setup.text({ '# Top', 'para' })
            local buf = add_rendered_buf()

            local state = require('render-markdown.state')
            assert.is_not_nil(state._store:peek(buf))

            vim.api.nvim_buf_delete(buf, { force = true })
            wait_for(function() return state._store:peek(buf) == nil end)

            assert.is_nil(state._store:peek(buf))
        end)
    end)

    describe('context cache lifecycle', function()
        it('context store drops its entry on buffer deletion', function()
            util.setup.text({ '# Top', 'para' })
            local buf = add_rendered_buf()

            local ctx_mgr = require('render-markdown.request.context')
            assert.is_not_nil(ctx_mgr._store:peek(buf))

            vim.api.nvim_buf_delete(buf, { force = true })
            wait_for(function() return ctx_mgr._store:peek(buf) == nil end)

            assert.is_nil(ctx_mgr._store:peek(buf))
        end)
    end)

    describe('manager.attached lifecycle', function()
        it('manager.attached returns false after the buffer dies', function()
            util.setup.text({ '# Top', 'para' })
            local buf = add_rendered_buf()

            local manager = require('render-markdown.core.manager')
            assert.equals(true, manager.attached(buf))

            vim.api.nvim_buf_delete(buf, { force = true })
            wait_for(function() return not manager.attached(buf) end)

            assert.equals(
                false,
                manager.attached(buf),
                'manager.attached must flip to false once nvim has deleted the buf'
            )
        end)
    end)

    describe('no unbounded growth across open/close cycles', function()
        it('every buffer-keyed store returns to zero entries after cycles', function()
            util.setup.text({ '# Top', 'para' })

            local state = require('render-markdown.state')
            local ui = require('render-markdown.core.ui')
            local ctx_mgr = require('render-markdown.request.context')
            local manager = require('render-markdown.core.manager')

            local baseline = {
                state = buffer_state._entry_count(state._store._impl.name),
                decorator = buffer_state._entry_count(ui._store._impl.name),
                context = buffer_state._entry_count(ctx_mgr._store._impl.name),
                attached = buffer_state._entry_count(manager._attached_store._impl.name),
            }

            for _ = 1, 20 do
                local buf = add_rendered_buf()
                vim.api.nvim_buf_delete(buf, { force = true })
            end
            -- Let any pending detach callbacks flush
            vim.wait(50)

            local after = {
                state = buffer_state._entry_count(state._store._impl.name),
                decorator = buffer_state._entry_count(ui._store._impl.name),
                context = buffer_state._entry_count(ctx_mgr._store._impl.name),
                attached = buffer_state._entry_count(manager._attached_store._impl.name),
            }

            assert.same(
                baseline,
                after,
                'buffer-keyed stores must return to their baseline counts after 20 open/close cycles'
            )
        end)
    end)
end)
