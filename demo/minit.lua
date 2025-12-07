-- General settings
vim.opt.termguicolors = true
vim.opt.cursorline = true

-- Line settings
vim.opt.wrap = false
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.statuscolumn = '%s%=%{v:relnum?v:relnum:v:lnum} '

-- Mode is already in status line plugin
vim.opt.showmode = false

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
assert(vim.uv.fs_stat(lazypath))
vim.opt.rtp:prepend(lazypath)

-- selene: allow(mixed_table)
require('lazy').setup({
    dev = { path = '~/dev' },
    spec = {
        {
            'folke/tokyonight.nvim',
            config = function()
                ---@diagnostic disable-next-line: missing-fields
                require('tokyonight').setup({ style = 'night' })
                vim.cmd.colorscheme('tokyonight')
            end,
        },
        {
            'nvim-lualine/lualine.nvim',
            dependencies = { 'nvim-mini/mini.nvim' },
            config = function()
                require('lualine').setup({
                    sections = {
                        lualine_a = { 'mode' },
                        lualine_b = { { 'filename', path = 0 } },
                        lualine_c = {},
                        lualine_x = {},
                        lualine_y = {},
                        lualine_z = { 'location' },
                    },
                })
            end,
        },
        {
            'nvim-treesitter/nvim-treesitter',
            build = ':TSUpdate',
            config = function()
                require('nvim-treesitter.configs').setup({
                    ensure_installed = { 'html', 'markdown', 'markdown_inline' },
                    highlight = { enable = true },
                })
            end,
        },
        {
            'nvim-mini/mini.nvim',
            config = function()
                local icons = require('mini.icons')
                icons.setup({})
                icons.mock_nvim_web_devicons()
            end,
        },
        {
            'MeanderingProgrammer/render-markdown.nvim',
            dev = true,
            dependencies = {
                'nvim-treesitter/nvim-treesitter',
                'nvim-mini/mini.nvim',
            },
            config = function()
                require('render-markdown').setup({
                    anti_conceal = {
                        enabled = false,
                    },
                })

                -- Quick reload for development iteration
                vim.keymap.set('n', '<leader>r', function()
                    for name, _ in pairs(package.loaded) do
                        if name:match('^render%-markdown') then
                            package.loaded[name] = nil
                        end
                    end
                    require('render-markdown').setup({})
                    vim.cmd('e')
                    print('render-markdown reloaded')
                end, { desc = 'Reload render-markdown' })

                -- Show leftcol for debugging
                vim.keymap.set('n', '<leader>l', function()
                    print('leftcol = ' .. vim.fn.winsaveview().leftcol)
                end, { desc = 'Show leftcol' })
            end,
        },
    },
})
