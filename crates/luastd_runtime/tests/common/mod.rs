//! Runs `tests/lua/*_spec.lua` (and the Kotlin ports in `tests/lua/kotlinx/`)
//! inside a runtime with the busted-shaped harness and `luastd_test`.

#![allow(dead_code)]

use std::rc::Rc;

use luastd_runtime::mlua::{Function, Lua, Result, Table, Value};
use luastd_runtime::{LuaError, Runtime, set_unhandled_handler};

const HARNESS: &str = include_str!("../lua/harness.lua");
const LUASTD_TEST: &str = include_str!("../lua/luastd_test.lua");

/// Load `luastd_test.lua` with its Rust helpers and make it `require`-able.
///
/// The sandbox hides `package`, so the module goes straight into the
/// registry's `_LOADED` table, which `require` consults first.
fn install_luastd_test(lua: &Lua) -> Result<()> {
    let native = lua.create_table()?;
    native.set(
        "error",
        lua.create_function(|lua, (kind, message): (String, Option<String>)| {
            LuaError::new(kind, message.unwrap_or_default()).table(lua)
        })?,
    )?;
    native.set(
        "set_unhandled",
        lua.create_function(|lua, handler: Option<Function>| {
            let handler = handler.map(|f| -> luastd_runtime::UnhandledHandler {
                Rc::new(move |_: &Lua, value: Value| {
                    if let Err(error) = f.call::<()>(value) {
                        eprintln!("luastd_test: unhandled-failure handler failed: {error}");
                    }
                })
            });
            set_unhandled_handler(lua, handler)?;
            Ok(())
        })?,
    )?;
    let module: Table = lua
        .load(LUASTD_TEST)
        .set_name("@tests/lua/luastd_test.lua")
        .call(native)?;
    let loaded: Table = lua.named_registry_value("_LOADED")?;
    loaded.set("luastd_test", module)
}

/// Run one spec file on `rt`; panics with every failing test.
pub fn run_spec(rt: &Runtime, name: &str, source: &str) -> usize {
    let (passed, failures, skipped): (usize, Vec<String>, usize) = rt
        .run(async |lua| -> Result<(usize, Vec<String>, usize)> {
            let run: Function = lua.load(HARNESS).set_name("=harness").eval()?;
            install_luastd_test(&lua)?;
            lua.load(source)
                .set_name(format!("@tests/lua/{name}"))
                .exec_async()
                .await?;
            run.call_async(()).await
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(failures.is_empty(), "{name}:\n{}", failures.join("\n"));
    assert!(passed > 0, "{name}: no tests ran");
    eprintln!("{name}: {passed} passed, {skipped} pending");
    passed
}
