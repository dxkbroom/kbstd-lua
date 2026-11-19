---
status: accepted
---

# The runtime replaces pcall and xpcall with cancellation-aware versions

Cancelling a coroutine raises a cancellation error at its next suspension point.
A plain `pcall` catches every error, so a loop like
`while true do pcall(function() async.delay(1000) end) end` swallows the
cancellation and the Job never stops. `luastd_runtime` replaces the global
`pcall` and `xpcall` with versions that catch ordinary errors as usual but
rethrow the cancellation error. Cleanup on cancellation is spelled
`async.finally(fn, cleanup)` or `scope:on_cancel(fn)`, the equivalent of
Kotlin's `try/finally`.

## Considered Options

- **Ship `async.pcall` and document the trap:** keeps the builtins untouched,
  but every plugin author has to remember it, and one forgotten `pcall` in a
  dependency makes a scope uncancellable.

## Consequences

- Sandboxing the global environment is already the runtime's job (no builtin
  `io` or `os.execute`), so this is one more replaced global, not a new kind of
  intrusion.
- The cdylib (`luastd_lua`) does not own the Lua state and does not replace
  `pcall`; async there is only as safe as the host makes it.

## Note: one cancellation value

The cancellation error is a single `luastd.Error` table (`kind = "Cancelled"`),
recognised by identity. mlua turns a table error that crosses a Rust callback
into a string, so the user-facing `luastd.async` functions are written in Lua
(`crates/luastd_runtime/src/async.lua`) and raise it themselves; Rust
primitives only report that cancellation happened.
