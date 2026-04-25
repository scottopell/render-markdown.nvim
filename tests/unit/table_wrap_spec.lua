---@module 'luassert'

local wrap = require('render-markdown.render.markdown.table_wrap')

---@param chunks render.md.mark.Text[]
---@return string
local function chunk_text(chunks)
    local text = ''
    for _, c in ipairs(chunks) do
        text = text .. c[1]
    end
    return text
end

---@param segs render.md.table.wrap.Segment[]
---@return string
local function seg_text(segs)
    local text = ''
    for _, s in ipairs(segs) do
        text = text .. s.text
    end
    return text
end

describe('table_wrap.tokenise', function()
    it('splits plain text into word/space tokens', function()
        local toks = wrap.tokenise({ { 'hello world here', 'X' } })
        assert.equals(5, #toks)
        assert.equals('word', toks[1].kind)
        assert.equals('hello', seg_text(toks[1].segments))
        assert.equals('space', toks[2].kind)
        assert.equals('word', toks[3].kind)
        assert.equals('world', seg_text(toks[3].segments))
        assert.equals('space', toks[4].kind)
        assert.equals('word', toks[5].kind)
    end)

    it('merges adjacent non-whitespace chunks into a single word', function()
        -- "foo[bar]baz" with bold "bar" -> chunks of 3, but the
        -- combined token has all 3 segments and is still ONE word.
        local toks = wrap.tokenise({
            { 'foo', 'A' },
            { 'bar', 'B' },
            { 'baz', 'A' },
        })
        assert.equals(1, #toks)
        assert.equals('word', toks[1].kind)
        assert.equals(3, #toks[1].segments)
        assert.equals('foo', toks[1].segments[1].text)
        assert.equals('A', toks[1].segments[1].highlight)
        assert.equals('B', toks[1].segments[2].highlight)
        assert.equals(9, toks[1].width)
    end)

    it('treats a chunk-internal space as a real break', function()
        local toks = wrap.tokenise({ { 'foo bar', 'A' } })
        assert.equals(3, #toks)
        assert.equals('word', toks[1].kind)
        assert.equals('foo', seg_text(toks[1].segments))
        assert.equals('space', toks[2].kind)
        assert.equals('word', toks[3].kind)
        assert.equals('bar', seg_text(toks[3].segments))
    end)

    it('returns empty list for empty chunk list', function()
        assert.equals(0, #wrap.tokenise({}))
    end)
end)

describe('table_wrap.pack', function()
    local function lines_text(lines)
        local out = {} ---@type string[]
        for _, line in ipairs(lines) do
            out[#out + 1] = seg_text(line)
        end
        return out
    end

    it('packs words greedily into lines', function()
        local toks = wrap.tokenise({ { 'one two three four five', 'X' } })
        local lines = wrap.pack(toks, 9)
        assert.same({ 'one two', 'three', 'four five' }, lines_text(lines))
    end)

    it('drops the whitespace consumed at a wrap point', function()
        local toks = wrap.tokenise({ { 'aa bb cc', 'X' } })
        local lines = wrap.pack(toks, 4)
        assert.same({ 'aa', 'bb', 'cc' }, lines_text(lines))
    end)

    it('places an oversize token on its own line, allowing overflow', function()
        local toks = wrap.tokenise({
            { 'short verylongwordthatoverflowsbudget tail', 'X' },
        })
        local lines = wrap.pack(toks, 10)
        assert.same({
            'short',
            'verylongwordthatoverflowsbudget',
            'tail',
        }, lines_text(lines))
    end)

    it('preserves the original highlight on every wrapped segment', function()
        -- "before [bold] after" with bold marked. After wrapping we
        -- should still see the bold highlight on the segments derived
        -- from "[bold]".
        local toks = wrap.tokenise({
            { 'before ', 'X' },
            { 'bold', 'B' },
            { ' after', 'X' },
        })
        local lines = wrap.pack(toks, 8)
        local saw_bold = false
        for _, line in ipairs(lines) do
            for _, seg in ipairs(line) do
                if seg.highlight == 'B' then
                    saw_bold = true
                    assert.equals('bold', seg.text)
                end
            end
        end
        assert.is_true(saw_bold)
    end)
end)

describe('table_wrap.wrap', function()
    it('returns one empty line for empty content', function()
        local lines = wrap.wrap({}, 10)
        assert.equals(1, #lines)
        assert.equals(0, #lines[1])
    end)

    it('handles an oversize chunk list whose total width exceeds budget', function()
        local lines = wrap.wrap({ { 'aaa bbb ccc ddd eee', 'X' } }, 7)
        assert.is_true(#lines >= 2)
    end)
end)

describe('table_wrap.allocate_budgets', function()
    it('returns proportional budgets that sum to text_width minus pipes', function()
        local b = wrap.allocate_budgets({ 10, 30 }, 50, 5)
        assert.is_not_nil(b)
        assert(b)
        -- 50 text_width - 3 pipes = 47 distributed across two columns.
        assert.equals(47, b[1] + b[2])
        assert.is_true(b[1] >= 5)
        assert.is_true(b[2] >= 5)
        -- Column 2 (natural 30) should be wider than column 1 (natural 10).
        assert.is_true(b[2] > b[1])
    end)

    it('clamps narrow columns to the floor and reclaims from wide ones', function()
        local b = wrap.allocate_budgets({ 1, 1, 100 }, 30, 5)
        assert.is_not_nil(b)
        assert(b)
        assert.equals(5, b[1])
        assert.equals(5, b[2])
        assert.equals(30 - 4 - 5 - 5, b[3])
    end)

    it('returns nil when text_width cannot satisfy min floor for every col', function()
        -- 4 cols * 5 floor = 20 + 5 pipes = 25 minimum, request 20
        assert.is_nil(wrap.allocate_budgets({ 1, 1, 1, 1 }, 20, 5))
    end)

    it('handles zero columns', function()
        assert.is_nil(wrap.allocate_budgets({}, 80, 5))
    end)

    it('handles zero or negative natural width gracefully', function()
        local b = wrap.allocate_budgets({ 0, 5 }, 30, 5)
        assert.is_not_nil(b)
        assert(b)
        assert.equals(27, b[1] + b[2])
    end)
end)

-- Sanity check the test helpers themselves so we can rely on
-- chunk_text / seg_text not silently masking real bugs.
describe('table_wrap test helpers', function()
    it('chunk_text round-trips simple chunks', function()
        assert.equals('abc', chunk_text({ { 'a', 'X' }, { 'bc', 'Y' } }))
    end)
end)
