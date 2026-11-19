# luastd

A Lua standard library written in Rust, plus a runtime that embeds it with
permission-checked IO and structured async.

- `crates/luastd` - pure modules (`require("luastd.path")`).
- `crates/luastd_runtime` - the embedding runtime (work in progress).
- `crates/luastd_lua` - the Lua C module built by [lux](https://github.com/lumen-oss/lux).

See `PLAN.md` for the design and `AGENTS.md` for the commands.
