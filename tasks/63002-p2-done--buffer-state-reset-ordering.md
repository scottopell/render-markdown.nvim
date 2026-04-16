---
artifact: hardened reset ordering in state.lua or buffer_state.lua
created: 2026-04-15
priority: p2
status: done
---

# Harden buffer_state._reset_all() ordering

## Summary

`state.setup()` calls `buffer_state._reset_all()` to wipe all per-buffer stores on reconfiguration. This works today because `state.setup` runs before any subsystem populates stores. But the coupling is implicit -- if initialization order changes, stores populated between setup calls could be silently wiped.

## Context

Found during review of `claude/triage-branches-gRg6h`. The `_reset_all` call sits in `state.lua:53` and destroys entries in all stores (decorator, context, state config, manager.attached). The ordering dependency is:

1. `state.setup()` runs, calls `_reset_all()`
2. `ts.setup()` runs
3. `ui.setup()` runs (clears extmark namespace)
4. Later, buffers attach and populate stores

If (3) or any future setup step created store entries before (1) completed, those would survive the reset.

## Done When

- Either: reset is scoped to only the stores that need it, or
- A test asserts that no store has entries before `_reset_all` fires, or
- Documentation makes the ordering contract explicit enough to catch violations in review
