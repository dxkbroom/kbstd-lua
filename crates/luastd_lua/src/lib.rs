//! Lua C module entry points for plain Lua consumers.
//!
//! `require("luastd")` resolves `luaopen_luastd`; `require("luastd.path")`
//! resolves `luaopen_luastd_path` from the same `luastd.so` through Lua's
//! all-in-one loader. Every pure module ([`luastd::FLOOR`]) gets one entry
//! point here.

use luastd::{Formatx, Math, Module, Path, Root, Semver};
use mlua::{Lua, Result, Table};

#[mlua::lua_module]
pub fn luastd(lua: &Lua) -> Result<Table> {
    Root::create(lua)
}

#[mlua::lua_module]
pub fn luastd_formatx(lua: &Lua) -> Result<Table> {
    Formatx::create(lua)
}

#[mlua::lua_module]
pub fn luastd_math(lua: &Lua) -> Result<Table> {
    Math::create(lua)
}

#[mlua::lua_module]
pub fn luastd_path(lua: &Lua) -> Result<Table> {
    Path::create(lua)
}

#[mlua::lua_module]
pub fn luastd_semver(lua: &Lua) -> Result<Table> {
    Semver::create(lua)
}
