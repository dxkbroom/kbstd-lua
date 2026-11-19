---
status: accepted
---

# Structured errors are Lua tables that travel as mlua errors

Lua code wants errors it can inspect: `err.kind`, `err.path`, `err.cause`.
mlua, though, turns every error value except its own error userdata into a
string when it crosses a Rust frame, so a table raised by Lua and passed through
a Rust callback, or returned to the host, loses its fields.

A `luastd.Error` is therefore a table with a shared metatable while Lua code
holds it, and an mlua error wrapping `LuaError` while it travels. The runtime's
`error` wraps a `luastd.Error` table before raising it, and its `pcall` and
`xpcall` unwrap what they catch. A slot keeps the table alive while any wrapped
copy exists, so the round trip returns the same table. Rust raises with
`Err(LuaError::new(kind, message).with(key, value).into())`; fields are
converted to Lua values only when Lua first sees the error.

## Considered Options

- **Userdata with `__index`:** survives Rust only if it is mlua's own error
  userdata, whose metatable is internal and protected, so its fields could not
  be read from Lua.
- **Return `ok, err` pairs from Rust and raise from Lua wrappers:** works for
  luastd's own functions, but errors raised by Lua callbacks that Rust calls are
  still stringified, and hosts only ever see strings.

## Consequences

- `error`, `pcall` and `xpcall` are replaced globals, next to ADR 0005's.
- Errors caught by `coroutine.resume` or `coroutine.wrap` arrive in their wrapped
  (userdata) form.
- Hosts read escaped errors with `LuaError::find(&err)` and `LuaError::table`.
- Plain tables raised by Lua code are not `luastd.Error`s and are still
  stringified across Rust frames.
