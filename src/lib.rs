#[allow(unused_imports)]
#[allow(dead_code)]
use mlua::{ExternalError, IntoLua, Lua, Result, Table, Value};

mod path;
mod util;

#[mlua::lua_module]
pub fn kbstd(lua: &Lua) -> Result<mlua::Table> {
    let table = lua.create_table()?;
    table.set("version", lua.create_string("0.0.1")?)?;

    Ok(table)
}

#[mlua::lua_module]
pub fn kbstd_path(lua: &Lua) -> Result<mlua::Table> {
    path::create_path_lib(lua)
}
