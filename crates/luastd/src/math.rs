//! The `luastd.math` Lua module.
//!
//! Integer helpers that complement Lua's builtin `math`. Ported from the
//! earlier `kbstd.math`, which only had `add`.

use mlua::Table;
use mlua::prelude::*;

use crate::Module;
use crate::util::{bad_argument, integer_argument};

/// The `luastd.math` module.
pub struct Math;

impl Module for Math {
    const NAME: &'static str = "luastd.math";

    fn create(lua: &Lua) -> LuaResult<Table> {
        let table = lua.create_table()?;
        table.set("add", lua.create_function(math_add)?)?;
        Ok(table)
    }
}

/// `math.add(left, right) -> integer`
///
/// Adds two integers, raising instead of wrapping on overflow.
fn math_add(_: &Lua, (left, right): (LuaValue, LuaValue)) -> LuaResult<i64> {
    let left = integer_argument(&left, 1, "left", "add")?;
    let right = integer_argument(&right, 2, "right", "add")?;
    left.checked_add(right)
        .ok_or_else(|| bad_argument(2, "right", "add", "integer overflow"))
}
