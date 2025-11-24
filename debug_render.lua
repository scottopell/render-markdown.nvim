-- Debug script to check why rendering might be disabled
local env = require('render-markdown.lib.env')
local state = require('render-markdown.state')

local buf = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()
local config = state.get(buf)

print("=== Render State Debug ===")

-- Check all the conditions from ui.lua:102-105
print("\nCondition 1 - config.enabled:", config.enabled)

print("\nCondition 2 - mode check:")
local mode = env.mode.get()
print("  Current mode:", mode)
print("  config.resolved:render(mode):", config.resolved:render(mode))

print("\nCondition 3 - diff check:")
local in_diff = env.win.get(win, 'diff')
print("  in_diff:", in_diff)
print("  state.render_in_diff:", state.render_in_diff)
print("  (state.render_in_diff or not in_diff):", (state.render_in_diff or not in_diff))

print("\nCondition 4 - horizontal scroll check:")
local view = env.win.view(win)
print("  leftcol:", view.leftcol)
print("  (leftcol == 0):", view.leftcol == 0)

print("\nFinal render decision:")
local render = config.enabled
    and config.resolved:render(mode)
    and (state.render_in_diff or not in_diff)
    and view.leftcol == 0
print("  render:", render)
print("  next_state:", render and 'rendered' or 'default')

print("\n=== End Render State Debug ===")
