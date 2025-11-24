-- Debug script to check config.win_options
local state = require('render-markdown.state')
local buf = vim.api.nvim_get_current_buf()

print("=== Config Debug ===")
local config = state.get(buf)

if not config then
    print("ERROR: No config found for buffer", buf)
    return
end

print("\nreader_width:", config.reader_width)
print("\nwin_options:")
for name, value in pairs(config.win_options) do
    print("  " .. name .. ":")
    if type(value) == "table" then
        print("    default:", value.default)
        print("    rendered:", value.rendered)
    else
        print("    value:", value)
    end
end

print("\n=== End Config Debug ===")
