-- Simple diagnostic to test window option setting
print("=== Window Options Diagnostic ===")

-- Create a buffer
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
local win = vim.api.nvim_get_current_win()

print("Initial values:")
print("  wrap:", vim.api.nvim_get_option_value('wrap', { win = win }))
print("  linebreak:", vim.api.nvim_get_option_value('linebreak', { win = win }))
print("  breakindent:", vim.api.nvim_get_option_value('breakindent', { win = win }))

-- Try to set them
print("\nSetting options to true...")
vim.api.nvim_set_option_value('wrap', true, { scope = 'local', win = win })
vim.api.nvim_set_option_value('linebreak', true, { scope = 'local', win = win })
vim.api.nvim_set_option_value('breakindent', true, { scope = 'local', win = win })

print("After setting:")
print("  wrap:", vim.api.nvim_get_option_value('wrap', { win = win }))
print("  linebreak:", vim.api.nvim_get_option_value('linebreak', { win = win }))
print("  breakindent:", vim.api.nvim_get_option_value('breakindent', { win = win }))

print("\n=== Test via env.win.set ===")
local env = require('render-markdown.lib.env')
env.win.set(win, 'linebreak', false)
env.win.set(win, 'breakindent', false)
print("After setting to false:")
print("  linebreak:", vim.api.nvim_get_option_value('linebreak', { win = win }))
print("  breakindent:", vim.api.nvim_get_option_value('breakindent', { win = win }))

env.win.set(win, 'linebreak', true)
env.win.set(win, 'breakindent', true)
print("After setting to true via env.win.set:")
print("  linebreak:", vim.api.nvim_get_option_value('linebreak', { win = win }))
print("  breakindent:", vim.api.nvim_get_option_value('breakindent', { win = win }))
