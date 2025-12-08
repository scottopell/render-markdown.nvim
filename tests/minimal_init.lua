---@param name string
---@return string
local function get_path(name)
    local data_path = vim.fn.stdpath('data')
    local plugin_path = vim.fs.find(name, { path = data_path })
    assert(#plugin_path == 1, 'plugin must have one path')
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

-- Install parsers if needed (handle both old and new nvim-treesitter APIs)
local ts = require('nvim-treesitter')
if ts.install then
    -- New API (nvim-treesitter 1.0+)
    ts.install({ 'html', 'latex', 'markdown', 'markdown_inline', 'yaml' }):wait()
else
    -- Old API or parsers already installed - just ensure they're available
    local parsers = { 'html', 'latex', 'markdown', 'markdown_inline', 'yaml' }
    for _, lang in ipairs(parsers) do
        pcall(vim.treesitter.language.add, lang)
    end
end

vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('Highlighter', {}),
    pattern = 'markdown',
    callback = function(args)
        vim.treesitter.start(args.buf)
    end,
})

require('mini.icons').setup({})
