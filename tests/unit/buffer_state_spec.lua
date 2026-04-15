---@module 'luassert'

local buffer_state = require('render-markdown.lib.buffer_state')

describe('buffer_state', function()
    -- Each test defines a uniquely-named store so they do not collide
    -- via the module-level _stores table. Using the test name as a
    -- suffix keeps assertions readable on failure.
    local function unique_name(suffix)
        return ('test_' .. suffix .. '_' .. tostring(math.random(1, 1e9)))
    end

    before_each(function()
        buffer_state._reset_all()
    end)

    describe('define_cache', function()
        it('requires a string name', function()
            assert.has_error(function()
                buffer_state.define_cache(nil, { make = function() end, destroy = function() end })
            end)
            assert.has_error(function()
                buffer_state.define_cache('', { make = function() end, destroy = function() end })
            end)
        end)

        it('requires both make and destroy', function()
            assert.has_error(function()
                buffer_state.define_cache(unique_name('no_make'), { destroy = function() end })
            end)
            assert.has_error(function()
                buffer_state.define_cache(unique_name('no_destroy'), { make = function() end })
            end)
        end)

        it('rejects duplicate names', function()
            local name = unique_name('dup')
            buffer_state.define_cache(name, { make = function() end, destroy = function() end })
            assert.has_error(function()
                buffer_state.define_cache(name, { make = function() end, destroy = function() end })
            end)
        end)

        it('returns a store with get/peek/drop methods', function()
            local store = buffer_state.define_cache(
                unique_name('shape'),
                { make = function() return {} end, destroy = function() end }
            )
            assert.is_function(store.get)
            assert.is_function(store.peek)
            assert.is_function(store.drop)
        end)
    end)

    describe('get/peek semantics', function()
        local store
        local make_calls
        before_each(function()
            make_calls = 0
            store = buffer_state.define_cache(unique_name('getpeek'), {
                make = function(buf)
                    make_calls = make_calls + 1
                    return { buf = buf, created_at = make_calls }
                end,
                destroy = function() end,
            })
        end)

        it('get creates on first access, returns cache on second', function()
            local a1 = store:get(1)
            assert.equals(1, make_calls)
            local a2 = store:get(1)
            assert.equals(1, make_calls, 'make should not be called a second time')
            assert.equals(a1, a2, 'second get should return the same table')
        end)

        it('get creates distinct entries for distinct buffers', function()
            local a = store:get(1)
            local b = store:get(2)
            assert.equals(2, make_calls)
            assert(a ~= b, 'distinct buffers get distinct entries')
            assert.equals(1, a.buf)
            assert.equals(2, b.buf)
        end)

        it('peek returns nil when no entry exists', function()
            assert.is_nil(store:peek(42))
        end)

        it('peek does not trigger make', function()
            store:peek(99)
            assert.equals(0, make_calls)
        end)

        it('peek returns the cached value after get', function()
            local v = store:get(7)
            assert.equals(v, store:peek(7))
        end)

        it('forwards extra args to make', function()
            local captured
            local with_args = buffer_state.define_cache(unique_name('args'), {
                make = function(buf, a, b)
                    captured = { buf = buf, a = a, b = b }
                    return captured
                end,
                destroy = function() end,
            })
            with_args:get(3, 'x', 42)
            assert.same({ buf = 3, a = 'x', b = 42 }, captured)
        end)
    end)

    describe('drop', function()
        it('removes entry and calls destroy', function()
            local destroyed = {}
            local store = buffer_state.define_cache(unique_name('drop'), {
                make = function(buf) return { id = buf } end,
                destroy = function(v) destroyed[#destroyed + 1] = v.id end,
            })
            store:get(5)
            store:drop(5)
            assert.same({ 5 }, destroyed)
            assert.is_nil(store:peek(5))
        end)

        it('is idempotent on missing entries', function()
            local destroys = 0
            local store = buffer_state.define_cache(unique_name('drop_miss'), {
                make = function() return {} end,
                destroy = function() destroys = destroys + 1 end,
            })
            store:drop(111) -- never got
            store:drop(111) -- still never got
            assert.equals(0, destroys)
        end)
    end)

    describe('on_detach lifecycle', function()
        it('calls every store destructor when a buffer is deleted', function()
            local destroyed_a, destroyed_b = {}, {}
            local store_a = buffer_state.define_cache(unique_name('det_a'), {
                make = function() return { marker = 'a' } end,
                destroy = function(v) destroyed_a[#destroyed_a + 1] = v.marker end,
            })
            local store_b = buffer_state.define_cache(unique_name('det_b'), {
                make = function() return { marker = 'b' } end,
                destroy = function(v) destroyed_b[#destroyed_b + 1] = v.marker end,
            })

            local buf = vim.api.nvim_create_buf(false, true)
            -- Populate both caches via the SAME buffer
            store_a:get(buf)
            store_b:get(buf)
            assert.equals(1, buffer_state._entry_count(store_a._impl.name))
            assert.equals(1, buffer_state._entry_count(store_b._impl.name))

            vim.api.nvim_buf_delete(buf, { force = true })
            -- on_detach is synchronous on delete; poll briefly to be safe
            vim.wait(50, function()
                return buffer_state._entry_count(store_a._impl.name) == 0
                    and buffer_state._entry_count(store_b._impl.name) == 0
            end)

            assert.same({ 'a' }, destroyed_a)
            assert.same({ 'b' }, destroyed_b)
            assert.equals(0, buffer_state._entry_count(store_a._impl.name))
            assert.equals(0, buffer_state._entry_count(store_b._impl.name))
        end)

        it('only destroys the entry for the deleted buffer, not siblings', function()
            local destroyed = {}
            local store = buffer_state.define_cache(unique_name('det_siblings'), {
                make = function(buf) return { id = buf } end,
                destroy = function(v) destroyed[#destroyed + 1] = v.id end,
            })

            local buf_a = vim.api.nvim_create_buf(false, true)
            local buf_b = vim.api.nvim_create_buf(false, true)
            store:get(buf_a)
            store:get(buf_b)

            vim.api.nvim_buf_delete(buf_a, { force = true })
            vim.wait(50, function() return store:peek(buf_a) == nil end)

            assert.same({ buf_a }, destroyed, 'only buf_a should have been destroyed')
            assert.is_nil(store:peek(buf_a))
            assert.is_not_nil(store:peek(buf_b))

            vim.api.nvim_buf_delete(buf_b, { force = true })
        end)

        it('a throwing destructor does not prevent other destructors from running', function()
            local a_calls, c_calls = 0, 0
            local store_a = buffer_state.define_cache(unique_name('throw_a'), {
                make = function() return {} end,
                destroy = function() a_calls = a_calls + 1 end,
            })
            local store_b = buffer_state.define_cache(unique_name('throw_b'), {
                make = function() return {} end,
                destroy = function() error('intentional test failure') end,
            })
            local store_c = buffer_state.define_cache(unique_name('throw_c'), {
                make = function() return {} end,
                destroy = function() c_calls = c_calls + 1 end,
            })

            local buf = vim.api.nvim_create_buf(false, true)
            store_a:get(buf)
            store_b:get(buf)
            store_c:get(buf)

            vim.api.nvim_buf_delete(buf, { force = true })
            vim.wait(50, function() return store_a:peek(buf) == nil end)

            assert.equals(1, a_calls, 'store_a destructor must still run despite store_b throwing')
            assert.equals(1, c_calls, 'store_c destructor must still run despite store_b throwing')
            assert.is_nil(store_a:peek(buf))
            assert.is_nil(store_b:peek(buf))
            assert.is_nil(store_c:peek(buf))
        end)
    end)

    describe('for_each', function()
        it('visits every live entry', function()
            local store = buffer_state.define_cache(unique_name('foreach'), {
                make = function(buf) return { id = buf, visited = false } end,
                destroy = function() end,
            })
            store:get(10)
            store:get(20)
            store:get(30)
            local seen = {}
            store:for_each(function(buf, entry)
                seen[buf] = entry.id
            end)
            assert.same({ [10] = 10, [20] = 20, [30] = 30 }, seen)
        end)

        it('is a no-op on an empty store', function()
            local store = buffer_state.define_cache(unique_name('foreach_empty'), {
                make = function() return {} end,
                destroy = function() end,
            })
            local count = 0
            store:for_each(function() count = count + 1 end)
            assert.equals(0, count)
        end)
    end)

    describe('_reset_all', function()
        it('destroys everything synchronously', function()
            local destroyed = 0
            local store = buffer_state.define_cache(unique_name('reset'), {
                make = function() return {} end,
                destroy = function() destroyed = destroyed + 1 end,
            })
            store:get(1)
            store:get(2)
            store:get(3)
            buffer_state._reset_all()
            assert.equals(3, destroyed)
            assert.equals(0, buffer_state._entry_count(store._impl.name))
        end)
    end)
end)
