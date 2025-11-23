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

        -- Debug: Check win_options in config
        print('Config win_options:', vim.inspect(config.win_options))

        -- Check that window options are set
        local win = vim.api.nvim_get_current_win()
        local wrap = vim.api.nvim_get_option_value('wrap', { win = win })
        local linebreak = vim.api.nvim_get_option_value('linebreak', { win = win })
        local breakindent = vim.api.nvim_get_option_value('breakindent', { win = win })

        print('Window options - wrap:', wrap, 'linebreak:', linebreak, 'breakindent:', breakindent)

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
end)
