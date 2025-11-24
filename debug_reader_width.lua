-- Debug script to check reader_width status
local env = require('render-markdown.lib.env')
local state = require('render-markdown.state')

local buf = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()

print("=== Reader Width Debug Info ===")
print("Buffer:", buf)
print("Window:", win)

-- Get config
local config = state.get(buf)
if config then
    print("\nConfig:")
    print("  reader_width:", config.reader_width)
else
    print("\nConfig: NOT FOUND")
    return
end

-- Get window info
local win_width = vim.api.nvim_win_get_width(win)
local infos = vim.fn.getwininfo(win)
local textoff = #infos == 1 and infos[1].textoff or 0

print("\nWindow Info:")
print("  Total width:", win_width)
print("  Text offset (line numbers, signs, etc):", textoff)
print("  Available width:", win_width - textoff)

-- Calculate center offset
local center_offset = env.win.center_offset(win, config.reader_width)
print("\nCenter Offset Calculation:")
print("  reader_width:", config.reader_width)
print("  Calculated center_offset:", center_offset)
print("  Expected formula: floor((", win_width - textoff, "-", config.reader_width, ") / 2) =", math.floor(((win_width - textoff) - config.reader_width) / 2))

-- Check window options
print("\nWindow Options:")
print("  wrap:", vim.api.nvim_get_option_value('wrap', { win = win }))
print("  linebreak:", vim.api.nvim_get_option_value('linebreak', { win = win }))
print("  breakindent:", vim.api.nvim_get_option_value('breakindent', { win = win }))
print("  breakindentopt:", vim.api.nvim_get_option_value('breakindentopt', { win = win }))

-- Check rendering state
print("\nRendering:")
print("  Plugin enabled:", config.enabled)
print("  Current mode:", vim.fn.mode(true))

print("\n=== End Debug Info ===")
