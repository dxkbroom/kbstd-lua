//! Lua C module entry points for plain Lua consumers.
//!
//! `require("luastd")` resolves `luaopen_luastd`; `require("luastd.path")`
//! resolves `luaopen_luastd_path` from the same `luastd.so` through Lua's
//! all-in-one loader.

use mlua::{Lua, Result, Table};

#[mlua::lua_module]
pub fn luastd(lua: &Lua) -> Result<Table> {
    let table = lua.create_table()?;
    table.set("version", env!("CARGO_PKG_VERSION"))?;
    Ok(table)
}

#[mlua::lua_module]
pub fn luastd_path(lua: &Lua) -> Result<Table> {
    luastd::path::create_path_lib(lua)
}
