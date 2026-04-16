---Centralized per-buffer state registry.
---
---Purpose: make per-buffer cache cleanup correct by construction.
---
---Problem this replaces: subsystems used to each hold a module-level
---`M.cache[buf] = ...` table and clean it (or not) via their own
---ad-hoc reset on `setup()`. There was no BufDelete hook, so entries
---leaked for every buffer ever opened; a uv_timer living inside the
---Decorator cache leaked along with its entry and was never closed.
---Adding a new subsystem required remembering to wire a cleanup path,
---which is exactly the kind of convention that rots.
---
---Design guarantees:
---
---  1. Every cache MUST declare a destructor at define-time. There is
---     no way to `define_cache` without passing one (assert fires at
---     module load). If you have nothing to clean up, pass
---     `function() end` - that is explicit consent, not oversight.
---
---  2. One lifecycle hook per buffer. The first time any store creates
---     an entry for buf, the registry installs a single
---     `vim.api.nvim_buf_attach(..., { on_detach = ... })` handler for
---     that buffer. When nvim fires on_detach (for :bdelete,
---     :bwipeout, implicit close, anything), the registry loops over
---     every store and runs its destructor. No autocmd, no distinction
---     between BufDelete and BufWipeout, no ordering hazards.
---
---  3. Stores are opaque - the returned object exposes only `get` and
---     `peek`. There is no public `entries` table, so callers cannot
---     accidentally write orphan entries that bypass the lifecycle.
---
---  4. Destructors are called in undefined order and each is pcall'd.
---     A throwing destructor is logged and the loop continues, so one
---     broken subsystem cannot leak every other subsystem's state.
---     Destructors must therefore be independent - if subsystem A's
---     destructor needs subsystem B, that is a design smell to fix at
---     the source.

---@class render.md.buffer_state.StoreDef
---@field make fun(buf: integer, ...: any): any
---@field destroy fun(value: any)

---@class render.md.buffer_state.Store<T>
---@field private _impl render.md.buffer_state.StoreImpl
---@field get fun(self, buf: integer, ...: any): any
---@field peek fun(self, buf: integer): any?
---@field drop fun(self, buf: integer)

---@class render.md.buffer_state.StoreImpl
---@field name string
---@field make fun(buf: integer, ...: any): any
---@field destroy fun(value: any)
---@field entries table<integer, any>

---@class render.md.BufferState
local M = {}

---@private
---@type table<string, render.md.buffer_state.StoreImpl>
M._stores = {}

---@private
---@type table<integer, true>
M._attached = {}

---Define a per-buffer cache. Returns an opaque store handle; the
---backing table is not exposed.
---
---@param name string unique identifier, for error messages and tests
---@param opts render.md.buffer_state.StoreDef
---@return render.md.buffer_state.Store
function M.define_cache(name, opts)
    assert(type(name) == 'string' and #name > 0, 'buffer_state: name required')
    assert(not M._stores[name], 'buffer_state: duplicate store name: ' .. name)
    assert(type(opts) == 'table', 'buffer_state: opts table required')
    assert(type(opts.make) == 'function', 'buffer_state: opts.make required')
    assert(
        type(opts.destroy) == 'function',
        'buffer_state: opts.destroy required (pass function() end for no-op)'
    )

    ---@type render.md.buffer_state.StoreImpl
    local impl = {
        name = name,
        make = opts.make,
        destroy = opts.destroy,
        entries = {},
    }
    M._stores[name] = impl

    local store = {}
    store._impl = impl

    ---Get or create an entry for `buf`. Forwards extra args to `make`
    ---only on the first access; subsequent accesses return the cached
    ---value regardless of args.
    ---@param buf integer
    ---@return any
    function store:get(buf, ...)
        local entry = impl.entries[buf]
        if entry == nil then
            entry = impl.make(buf, ...)
            impl.entries[buf] = entry
            M._ensure_attached(buf)
        end
        return entry
    end

    ---Return the cached entry for `buf` without creating one.
    ---@param buf integer
    ---@return any?
    function store:peek(buf)
        return impl.entries[buf]
    end

    ---Explicitly drop the entry for `buf`, invoking its destructor.
    ---Idempotent; safe to call when no entry exists.
    ---@param buf integer
    function store:drop(buf)
        local entry = impl.entries[buf]
        if entry ~= nil then
            impl.entries[buf] = nil
            local ok, err = pcall(impl.destroy, entry)
            if not ok then
                M._destroy_error(impl.name, buf, err)
            end
        end
    end

    ---Iterate every live entry in the store, invoking `fn(buf, entry)`.
    ---Iteration order is undefined. The callback must not mutate the
    ---store (no get/drop for other buffers during iteration).
    ---@param fn fun(buf: integer, entry: any)
    function store:for_each(fn)
        for buf, entry in pairs(impl.entries) do
            fn(buf, entry)
        end
    end

    return store
end

---@private
---Install a single on_detach hook for `buf`. Idempotent.
---@param buf integer
function M._ensure_attached(buf)
    if M._attached[buf] then
        return
    end
    M._attached[buf] = true
    local ok = pcall(vim.api.nvim_buf_attach, buf, false, {
        on_detach = function(_, detached_buf)
            M._on_detach(detached_buf)
        end,
    })
    if not ok then
        -- Could not attach (buffer already invalid, etc.). We still
        -- hold entries; they will be reaped by _reset_all or process
        -- exit. Mark as not-attached so a future successful create
        -- can retry.
        M._attached[buf] = nil
    end
end

---@private
---Fires when nvim destroys `buf`. Runs every store's destructor on
---its entry (if any) in undefined order, pcall-wrapped.
---@param buf integer
function M._on_detach(buf)
    M._attached[buf] = nil
    for _, impl in pairs(M._stores) do
        local entry = impl.entries[buf]
        if entry ~= nil then
            impl.entries[buf] = nil
            local ok, err = pcall(impl.destroy, entry)
            if not ok then
                M._destroy_error(impl.name, buf, err)
            end
        end
    end
end

---@private
---@param name string
---@param buf integer
---@param err any
function M._destroy_error(name, buf, err)
    vim.schedule(function()
        vim.notify(
            ('[render-markdown] buffer_state destroy failed for %s[%d]: %s'):format(
                name,
                buf,
                tostring(err)
            ),
            vim.log.levels.ERROR
        )
    end)
end

---@private
---True after the first _reset_all call. Used to distinguish the
---initial setup (stores should be empty; entries would indicate
---an ordering bug) from subsequent reconfigurations (entries are
---expected and legitimately cleared).
M._reset_seen = false

---Synchronously wipe every store, calling all destructors.
---Called from state.setup() to get a clean slate on reconfiguration,
---and from tests. Warns only on the first call if any entries
---existed, since the initial setup should run before any buffer
---populates stores. Subsequent calls (reconfiguration) expect to
---find entries and silently wipe them.
function M._reset_all()
    local had_entries = false
    for _, impl in pairs(M._stores) do
        for buf, entry in pairs(impl.entries) do
            had_entries = true
            impl.entries[buf] = nil
            pcall(impl.destroy, entry)
        end
    end
    if had_entries and not M._reset_seen then
        vim.schedule(function()
            vim.notify(
                '[render-markdown] buffer_state._reset_all found live entries on initial setup -- ordering may be wrong',
                vim.log.levels.WARN
            )
        end)
    end
    M._reset_seen = true
    M._attached = {}
end

---Test hook: number of stores currently registered.
---@return integer
function M._store_count()
    local n = 0
    for _ in pairs(M._stores) do
        n = n + 1
    end
    return n
end

---Test hook: number of live entries in a given store.
---@param name string
---@return integer
function M._entry_count(name)
    local impl = assert(M._stores[name], 'no such store: ' .. name)
    local n = 0
    for _ in pairs(impl.entries) do
        n = n + 1
    end
    return n
end

return M
