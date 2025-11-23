---@param name string
---@return string
local function get_path(name)
    local data_path = vim.fn.stdpath('data')
    local plugin_path = vim.fs.find(name, { path = data_path })
    if #plugin_path == 0 then
        error('Plugin ' .. name .. ' not found in ' .. data_path)
    end
    return plugin_path[1]
end

-- settings
vim.opt.lines = 40
vim.opt.columns = 80
vim.opt.tabstop = 4
vim.opt.wrap = false

-- source dependencies first
vim.opt.rtp:prepend(get_path('nvim-treesitter'))
vim.cmd.runtime('plugin/nvim-treesitter.lua')
vim.opt.rtp:prepend(get_path('mini.nvim'))

-- source this plugin
vim.opt.rtp:prepend('.')
vim.cmd.runtime('plugin/render-markdown.lua')

-- used for unit testing
vim.opt.rtp:prepend(get_path('plenary.nvim'))
vim.cmd.runtime('plugin/plenary.vim')

-- Skip treesitter parser installation for quick testing
-- Just set up the FileType autocmd
vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('Highlighter', {}),
    pattern = 'markdown',
    callback = function(args)
        -- Try to start treesitter if parsers are available
        pcall(vim.treesitter.start, args.buf)
    end,
})

-- Setup mini.icons if available
pcall(function()
    require('mini.icons').setup({})
end)
