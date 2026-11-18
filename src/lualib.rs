#[allow(unused_imports)]
use mlua::{ExternalError, IntoLua, Lua, Result, Table, Value};

#[mlua::lua_module]
pub fn kbstd(lua: &Lua) -> Result<mlua::Table> {
    let table = lua.create_table()?;
    table.set("version", lua.create_string("0.0.1")?)?;

    Ok(table)
}
