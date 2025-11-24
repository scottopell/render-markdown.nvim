# Test Reader Width

## This is a heading

This is a paragraph with some text that should be constrained to the reader width and centered in the window.

Another paragraph here with more text to test the wrapping behavior when lines are longer than the configured reader width setting. This is a test of how far it scrolls horizontally.

### Smaller Heading

- List item one
- List item two with a longer description that might wrap when the lines are super long like this is
- List item three

```lua
-- Code block test
local function test()
  print("This code block should also respect reader_width")
end
```

> A blockquote that should also be constrained and centered properly within the reader width configuration.

---

Final paragraph to test everything.
