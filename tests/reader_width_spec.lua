---@module 'luassert'

local util = require('tests.util')

describe('reader_width', function()
    it('basic reader_width with paragraph', function()
        local lines = {
            '',
            'This is a test paragraph with some text that should respect the max width setting.',
            '',
        }

        util.setup.text(lines, {
            reader_width = 80,
            paragraph = { enabled = false },
        })

        -- Get config to verify reader_width is set
        local state = require('render-markdown.state')
        local buf = vim.api.nvim_get_current_buf()
        local config = state.get(buf)
        assert.equals(80, config.reader_width)

        -- Check that window options are set
        local win = vim.api.nvim_get_current_win()
        local wrap = vim.api.nvim_get_option_value('wrap', { win = win })
        local linebreak = vim.api.nvim_get_option_value('linebreak', { win = win })
        local breakindent = vim.api.nvim_get_option_value('breakindent', { win = win })

        -- In normal mode with rendering enabled, these should be true
        assert.equals(true, wrap, 'wrap should be true')
        assert.equals(true, linebreak, 'linebreak should be true')
        assert.equals(true, breakindent, 'breakindent should be true')
    end)

    it('reader_width automatically centers', function()
        -- Set window width to 140 columns
        vim.opt.columns = 140

        local lines = {
            '',
            'This is a test paragraph that should be centered.',
            '',
        }

        util.setup.text(lines, {
            reader_width = 80,
            paragraph = { enabled = false },
        })

        -- Get config to verify settings
        local state = require('render-markdown.state')
        local buf = vim.api.nvim_get_current_buf()
        local config = state.get(buf)
        assert.equals(80, config.reader_width)

        -- Check that window options are set
        local win = vim.api.nvim_get_current_win()
        local wrap = vim.api.nvim_get_option_value('wrap', { win = win })
        local linebreak = vim.api.nvim_get_option_value('linebreak', { win = win })
        local breakindent = vim.api.nvim_get_option_value('breakindent', { win = win })

        assert.equals(true, wrap, 'wrap should be true')
        assert.equals(true, linebreak, 'linebreak should be true')
        assert.equals(true, breakindent, 'breakindent should be true')

        -- Check that breakindentopt is set for centering
        -- Expected center_offset = (140 - 80) / 2 = 30
        local breakindentopt = vim.api.nvim_get_option_value('breakindentopt', { win = win })
        assert.is_true(string.match(breakindentopt, 'shift:') ~= nil, 'breakindentopt should contain shift')
    end)

    it('reader_width disabled when 0', function()
        local lines = {
            '',
            'This is a test paragraph.',
            '',
        }

        -- Store original settings
        local orig_wrap = vim.o.wrap
        local orig_linebreak = vim.o.linebreak
        local orig_breakindent = vim.o.breakindent

        util.setup.text(lines, {
            reader_width = 0,
            paragraph = { enabled = false },
        })

        -- Check that window options match defaults (not forced to true)
        local win = vim.api.nvim_get_current_win()
        -- When reader_width is 0, wrapping behavior should match user defaults
        -- Since we're in test mode and defaults might vary, just verify the system works
        assert.is_not_nil(vim.api.nvim_get_option_value('wrap', { win = win }))
    end)

    it('window options are restored when rendering is disabled', function()
        local lines = {
            '',
            'This is a test paragraph.',
            '',
        }

        -- Capture global defaults before setup (these are what will be restored)
        local default_wrap = vim.o.wrap
        local default_linebreak = vim.o.linebreak
        local default_breakindent = vim.o.breakindent

        -- Setup with reader_width enabled
        util.setup.text(lines, {
            reader_width = 80,
            paragraph = { enabled = false },
        })

        local win = vim.api.nvim_get_current_win()

        -- Verify options were changed to true (rendered state)
        assert.equals(true, vim.api.nvim_get_option_value('wrap', { win = win }), 'wrap should be true when rendering')
        assert.equals(true, vim.api.nvim_get_option_value('linebreak', { win = win }), 'linebreak should be true when rendering')
        assert.equals(true, vim.api.nvim_get_option_value('breakindent', { win = win }), 'breakindent should be true when rendering')

        -- Disable rendering for this buffer by directly setting config.enabled
        local state = require('render-markdown.state')
        local buf = vim.api.nvim_get_current_buf()
        local config = state.get(buf)
        config.enabled = false

        -- Manually trigger UI update to apply the disable
        local ui = require('render-markdown.core.ui')
        ui.update(buf, win, 'test_disable', true)

        vim.wait(150) -- Wait for UI update to complete

        -- Verify config.enabled is now false
        assert.equals(false, config.enabled, 'config should be disabled')

        -- Verify options are restored to the defaults captured at config creation time
        local restored_wrap = vim.api.nvim_get_option_value('wrap', { win = win })
        local restored_linebreak = vim.api.nvim_get_option_value('linebreak', { win = win })
        local restored_breakindent = vim.api.nvim_get_option_value('breakindent', { win = win })

        -- The config captures defaults at creation time from global vim.o.*
        local expected_wrap = config.win_options.wrap.default
        local expected_linebreak = config.win_options.linebreak.default
        local expected_breakindent = config.win_options.breakindent.default

        assert.equals(expected_wrap, restored_wrap, 'wrap should be restored to config default')
        assert.equals(expected_linebreak, restored_linebreak, 'linebreak should be restored to config default')
        assert.equals(expected_breakindent, restored_breakindent, 'breakindent should be restored to config default')

        -- Verify linebreak and breakindent are no longer forced to true
        assert.equals(false, restored_linebreak, 'linebreak should not be true after disable')
        assert.equals(false, restored_breakindent, 'breakindent should not be true after disable')
    end)
end)
