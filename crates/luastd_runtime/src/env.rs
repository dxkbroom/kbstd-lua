//! The `luastd.env` effect module (cargo feature `env`).
//!
//! Reads the process environment through permission checks. Writes never
//! touch the process: `set` and `unset` change this runtime's overlay, which
//! later reads see and which `luastd.process` will hand to children.
//! `std::env::set_var` is `unsafe` in Rust 2024 because other threads may read
//! the environment concurrently, and the host owns that decision.
//!
//! Every function is `---@async`: when deno would prompt it awaits the host's
//! [`Prompter`](crate::Prompter). The `*_sync` variants never prompt; a
//! `prompt` state raises `PermissionDenied`.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::rc::Rc;

use deno_permissions::PermissionsContainer;
use mlua::{Function, Lua, MultiValue, Result, Table, Value};

use crate::EffectModule;
use crate::errors::{LuaErrorTable, Outcome, outcome_into_lua, raising};
use crate::prompt::{EnvDescriptor, check, check_now};

/// Variables set (`Some`) or unset (`None`) by Lua in this runtime.
#[derive(Clone, Default, Debug)]
pub struct EnvOverlay(Rc<RefCell<HashMap<String, Option<String>>>>);

impl EnvOverlay {
    /// The value Lua sees for `name`: the overlay first, then the process.
    pub fn get(&self, name: &str) -> Option<String> {
        match self.0.borrow().get(name) {
            Some(value) => value.clone(),
            None => std::env::var(name).ok(),
        }
    }

    /// Every variable Lua sees, sorted by name.
    pub fn vars(&self) -> BTreeMap<String, String> {
        let mut vars: BTreeMap<_, _> = std::env::vars().collect();
        for (name, value) in self.0.borrow().iter() {
            match value {
                Some(value) => vars.insert(name.clone(), value.clone()),
                None => vars.remove(name),
            };
        }
        vars
    }

    fn set(&self, name: String, value: Option<String>) {
        self.0.borrow_mut().insert(name, value);
    }
}

/// The `luastd.env` module.
pub struct Env;

#[derive(Clone, Copy)]
enum Op {
    Get,
    Has,
    Set,
    Unset,
    Vars,
}

impl Op {
    const ALL: [(Op, &'static str); 5] = [
        (Op::Get, "get"),
        (Op::Has, "has"),
        (Op::Set, "set"),
        (Op::Unset, "unset"),
        (Op::Vars, "vars"),
    ];
}

impl EffectModule for Env {
    const NAME: &'static str = "luastd.env";

    fn create(lua: &Lua, permissions: &PermissionsContainer) -> Result<Table> {
        let overlay = match lua.app_data_ref::<EnvOverlay>() {
            Some(overlay) => overlay.clone(),
            None => {
                let overlay = EnvOverlay::default();
                lua.set_app_data(overlay.clone());
                overlay
            }
        };
        let module = lua.create_table()?;
        for (op, name) in Op::ALL {
            let (permissions_async, overlay_async) = (permissions.clone(), overlay.clone());
            let raw = lua.create_async_function(move |lua, args: MultiValue| {
                let (permissions, overlay) = (permissions_async.clone(), overlay_async.clone());
                async move {
                    let outcome = match parse(op, name, &args) {
                        Ok(call) => {
                            match check(&lua, &permissions, EnvDescriptor(call.var())).await {
                                Ok(()) => run(&lua, &overlay, call),
                                Err(error) => Err(error),
                            }
                        }
                        Err(error) => Err(error),
                    };
                    outcome_into_lua(&lua, outcome)
                }
            })?;
            module.set(name, raising(lua, raw)?)?;

            let (permissions, overlay) = (permissions.clone(), overlay.clone());
            let raw_sync: Function = lua.create_function(move |lua, args: MultiValue| {
                let outcome = parse(op, name, &args).and_then(|call| {
                    check_now(&permissions, EnvDescriptor(call.var()))?;
                    run(lua, &overlay, call)
                });
                outcome_into_lua(lua, outcome)
            })?;
            module.set(format!("{name}_sync"), raising(lua, raw_sync)?)?;
        }
        Ok(module)
    }
}

enum Call {
    Get(String),
    Has(String),
    Set(String, String),
    Unset(String),
    Vars,
}

impl Call {
    fn var(&self) -> Option<&str> {
        match self {
            Call::Get(name) | Call::Has(name) | Call::Set(name, _) | Call::Unset(name) => {
                Some(name)
            }
            Call::Vars => None,
        }
    }
}

fn parse(op: Op, function: &str, args: &MultiValue) -> Outcome<Call> {
    let string = |index: usize, what: &str| -> Outcome<String> {
        match args.get(index - 1) {
            Some(Value::String(text)) => text
                .to_str()
                .map(|text| text.to_owned())
                .map_err(|_| bad_argument(index, what, function, "UTF-8 string expected")),
            _ => Err(bad_argument(index, what, function, "string expected")),
        }
    };
    let name = |index| -> Outcome<String> {
        let name = string(index, "name")?;
        if name.is_empty() || name.contains(['=', '\0']) {
            return Err(bad_argument(
                index,
                "name",
                function,
                "valid variable name expected",
            ));
        }
        Ok(name)
    };
    Ok(match op {
        Op::Get => Call::Get(name(1)?),
        Op::Has => Call::Has(name(1)?),
        Op::Set => {
            let var = name(1)?;
            let value = string(2, "value")?;
            if value.contains('\0') {
                return Err(bad_argument(
                    2,
                    "value",
                    function,
                    "string without NUL expected",
                ));
            }
            Call::Set(var, value)
        }
        Op::Unset => Call::Unset(name(1)?),
        Op::Vars => Call::Vars,
    })
}

fn bad_argument(index: usize, name: &str, function: &str, expected: &str) -> LuaErrorTable {
    LuaErrorTable::new(
        "InvalidArgument",
        format!("bad argument #{index} '{name}' to '{function}' ({expected})"),
    )
}

fn run(lua: &Lua, overlay: &EnvOverlay, call: Call) -> Outcome<Value> {
    let value = match call {
        Call::Get(name) => match overlay.get(&name) {
            Some(value) => Value::String(lua.create_string(value).map_err(internal)?),
            None => Value::Nil,
        },
        Call::Has(name) => Value::Boolean(overlay.get(&name).is_some()),
        Call::Set(name, value) => {
            overlay.set(name, Some(value));
            Value::Nil
        }
        Call::Unset(name) => {
            overlay.set(name, None);
            Value::Nil
        }
        Call::Vars => Value::Table(lua.create_table_from(overlay.vars()).map_err(internal)?),
    };
    Ok(value)
}

fn internal(error: mlua::Error) -> LuaErrorTable {
    LuaErrorTable::new("Internal", error.to_string())
}
