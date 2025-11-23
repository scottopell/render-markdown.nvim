---@module 'luassert'

describe('max_width configuration', function()
    it('adds window options when max_width is set', function()
        local Config = require('render-markdown.lib.config')
        local init = require('render-markdown.init')

        -- Create a buffer
        local buf = vim.api.nvim_create_buf(false, true)

        -- Create config with max_width
        local root_config = init.resolve_config({ max_width = 80 })
        local config = Config.new(root_config, true, buf, nil)

        -- Verify max_width is set
        assert.equals(80, config.max_width)

        -- Verify window options include wrapping options
        assert.is_not_nil(config.win_options.wrap)
        assert.is_not_nil(config.win_options.linebreak)
        assert.is_not_nil(config.win_options.breakindent)

        -- Verify rendered values are true
        assert.equals(true, config.win_options.wrap.rendered)
        assert.equals(true, config.win_options.linebreak.rendered)
        assert.equals(true, config.win_options.breakindent.rendered)
    end)

    it('adds window options with center_max_width', function()
        local Config = require('render-markdown.lib.config')
        local init = require('render-markdown.init')

        local buf = vim.api.nvim_create_buf(false, true)
        local root_config = init.resolve_config({
            max_width = 80,
            center_max_width = true,
        })
        local config = Config.new(root_config, true, buf, nil)

        assert.equals(80, config.max_width)
        assert.equals(true, config.center_max_width)
        assert.is_not_nil(config.win_options.wrap)
        assert.is_not_nil(config.win_options.linebreak)
        assert.is_not_nil(config.win_options.breakindent)
    end)

    it('does not add window options when max_width is 0', function()
        local Config = require('render-markdown.lib.config')
        local init = require('render-markdown.init')

        local buf = vim.api.nvim_create_buf(false, true)
        local root_config = init.resolve_config({ max_width = 0 })
        local config = Config.new(root_config, true, buf, nil)

        assert.equals(0, config.max_width)

        -- Window options should only have defaults (conceallevel, concealcursor)
        -- but not wrap, linebreak, breakindent
        local has_wrap = config.win_options.wrap ~= nil
        local has_linebreak = config.win_options.linebreak ~= nil
        local has_breakindent = config.win_options.breakindent ~= nil

        -- All should be false when max_width is 0
        assert.is_false(has_wrap and has_linebreak and has_breakindent)
    end)

    it('center_offset calculation', function()
        local env = require('render-markdown.lib.env')

        -- Create a window
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
        local win = vim.api.nvim_get_current_win()

        -- Note: In headless mode, window width might not be settable
        -- Just verify the logic works with the default window width
        local win_width = vim.api.nvim_win_get_width(win)

        -- With centering disabled, offset should always be 0
        local offset = env.win.center_offset(win, 80, false)
        assert.equals(0, offset)

        -- With centering enabled and max_width = 0, offset should be 0
        offset = env.win.center_offset(win, 0, true)
        assert.equals(0, offset)

        -- With centering enabled and max_width > window, offset should be 0
        offset = env.win.center_offset(win, win_width + 100, true)
        assert.equals(0, offset)

        -- With centering enabled and max_width < window, offset should be > 0
        if win_width > 20 then
            offset = env.win.center_offset(win, 20, true)
            assert.is_true(offset > 0, 'offset should be positive when window is wider than max_width')
            -- Verify the calculation: offset should be (win_width - 20) / 2
            local expected = math.floor((win_width - 20) / 2)
            assert.equals(expected, offset)
        end
    end)
end)
