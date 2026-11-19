//! Structured Lua errors: tables with `kind`, `message` and context fields.
//!
//! A Rust callback cannot raise a table (mlua turns a returned error into
//! userdata), so primitives return `ok, value | err` and [`raising`] wraps them
//! in a Lua function that calls `error(err)` with the table intact.

use mlua::{Function, IntoLua, Lua, MultiValue, Result, Table, Value};

const METATABLE: &str = "luastd.Error";

/// A structured error, built in Rust and raised as a Lua table.
#[derive(Clone, Debug)]
pub struct LuaErrorTable {
    pub kind: &'static str,
    pub message: String,
    /// String context such as `permission`, `target` or `path`.
    pub fields: Vec<(&'static str, String)>,
}

impl LuaErrorTable {
    pub fn new(kind: &'static str, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
            fields: Vec::new(),
        }
    }

    pub fn with(mut self, key: &'static str, value: impl Into<String>) -> Self {
        self.fields.push((key, value.into()));
        self
    }

    /// Build the table, with the shared `luastd.Error` metatable.
    pub fn into_table(self, lua: &Lua) -> Result<Table> {
        let table = lua.create_table()?;
        table.set("kind", self.kind)?;
        table.set("message", self.message)?;
        for (key, value) in self.fields {
            table.set(key, value)?;
        }
        table.set_metatable(Some(metatable(lua)?))?;
        Ok(table)
    }
}

impl IntoLua for LuaErrorTable {
    fn into_lua(self, lua: &Lua) -> Result<Value> {
        self.into_table(lua).map(Value::Table)
    }
}

fn metatable(lua: &Lua) -> Result<Table> {
    if let Ok(table) = lua.named_registry_value::<Table>(METATABLE) {
        return Ok(table);
    }
    let table = lua.create_table()?;
    table.set(
        "__tostring",
        lua.create_function(|_, error: Table| {
            Ok(format!(
                "{}: {}",
                error.get::<String>("kind")?,
                error.get::<String>("message")?
            ))
        })?,
    )?;
    lua.set_named_registry_value(METATABLE, &table)?;
    Ok(table)
}

/// The `ok, value | err` convention for primitives that [`raising`] wraps.
pub type Outcome<T> = std::result::Result<T, LuaErrorTable>;

/// Convert an [`Outcome`] into the `true, ...` / `false, err` multivalue.
pub fn outcome_into_lua<T: IntoLua>(lua: &Lua, outcome: Outcome<T>) -> Result<MultiValue> {
    Ok(match outcome {
        Ok(value) => MultiValue::from_vec(vec![Value::Boolean(true), value.into_lua(lua)?]),
        Err(error) => MultiValue::from_vec(vec![Value::Boolean(false), error.into_lua(lua)?]),
    })
}

/// Wrap a primitive returning `ok, ...` so that `false, err` raises `err`.
pub fn raising(lua: &Lua, raw: Function) -> Result<Function> {
    lua.load(
        r#"
        local raw, error = ...
        local function check(ok, ...)
            if ok then return ... end
            error((...), 2)
        end
        return function(...) return check(raw(...)) end
        "#,
    )
    .set_name("=luastd.raising")
    .call((raw, lua.globals().get::<Function>("error")?))
}
