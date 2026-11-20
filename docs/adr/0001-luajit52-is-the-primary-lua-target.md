---
status: accepted
---

# LuaJIT 2.1 with 5.2 compatibility is the primary Lua target

luastd's primary target is LuaJIT 2.1 built with `LUAJIT_ENABLE_LUA52COMPAT`, which
is mlua's `luajit52` feature. It is the same engine and speed as Neovim's LuaJIT,
plus a handful of Lua 5.2 behaviours that make the runtime and plugin code nicer to
write. The crates still never pick a Lua version themselves; the host does, and
plain `luajit` (what Neovim ships) stays supported.

## Facts (checked 2026-11-18)

- Neovim's bundled LuaJIT is pinned in `cmake.deps/deps.txt` to
  `luajit/luajit@63c8f1a9b479ba5518cf6a170ff7729178bc3cfd` (2.1 rolling), and
  `cmake.deps/cmake/BuildLuajit.cmake` passes no `LUAJIT_ENABLE_LUA52COMPAT`.
- `:h lua-compat`: "Lua 5.1 is the permanent interface for Nvim Lua".
- A local Neovim 0.12.6 reports `LuaJIT 2.1.1792588164`, and `table.pack` is `nil`.
- `LUAJIT_ENABLE_LUA52COMPAT` adds: `table.pack`/`table.unpack`, `__pairs`/`__ipairs`,
  `__len` on tables, `load` with mode and env, `xpcall` extra arguments,
  `os.exit(true)`, and a second return from `coroutine.running()`. It does not add
  integers, `_ENV`, or anything from 5.3+.

## Considered Options

- **`luajit` (Neovim's build):** maximum compatibility with Neovim plugin code, but
  loses the 5.2 conveniences for no benefit to our own hosts.

## Consequences

- "Dropping Lua 5.1" means dropping PUC-Rio Lua 5.1 only.
- Lua code shipped by luastd itself (stubs, specs, helpers) must not depend on the
  5.2 additions, so it keeps working on a plain `luajit` host.
- Async relies on yielding across `pcall` and metamethods, which LuaJIT and PUC
  Lua 5.2+ support and PUC Lua 5.1 does not.
- Supported targets: `luajit52` (primary), `luajit`, `lua52`–`lua55`.
