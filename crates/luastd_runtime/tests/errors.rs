//! `luastd.Error`: structured errors that survive Rust frames (ADR 0006).

mod common;

use luastd_runtime::errors::live_error_slots;
use luastd_runtime::mlua::{Function, Lua, Result, Table};
use luastd_runtime::{LuaError, Runtime};

/// A runtime with `raise()` (a Rust callback raising a `LuaError`) and
/// `call(f)` (a Rust frame that calls `f` and propagates its error).
fn runtime() -> Runtime {
    let rt = Runtime::builder().build().unwrap();
    let lua = rt.lua();
    let raise = lua
        .create_function(|_, ()| -> Result<()> {
            Err(LuaError::new("Boom", "it broke")
                .with("code", 42)
                .with("retry", true)
                .with("path", "/tmp/x".to_owned())
                .with_cause(LuaError::new("Inner", "the reason").with("depth", 2))
                .into())
        })
        .unwrap();
    let call = lua
        .create_function(|_, f: Function| f.call::<()>(()))
        .unwrap();
    lua.globals().set("raise", raise).unwrap();
    lua.globals().set("call", call).unwrap();
    rt
}

#[test]
fn error_spec() {
    let rt = runtime();
    common::run_spec(
        &rt,
        "luastd_error_spec.lua",
        include_str!("lua/luastd_error_spec.lua"),
    );
}

#[test]
fn rust_errors_reach_lua_as_tables() {
    let rt = runtime();
    let (kind, code, retry, path, cause, depth, text, same_mt): (
        String,
        i64,
        bool,
        String,
        String,
        i64,
        String,
        bool,
    ) = rt
        .lua()
        .load(
            r#"
            local ok, e = pcall(raise)
            assert(not ok and type(e) == "table")
            return e.kind, e.code, e.retry, e.path, e.cause.kind, e.cause.depth,
                tostring(e), getmetatable(e) == getmetatable(e.cause)
            "#,
        )
        .eval()
        .unwrap();
    assert_eq!(
        (kind.as_str(), code, retry, path.as_str()),
        ("Boom", 42, true, "/tmp/x")
    );
    assert_eq!((cause.as_str(), depth), ("Inner", 2));
    assert_eq!(text, "Boom: it broke");
    assert!(same_mt);
}

#[test]
fn lua_errors_keep_identity_through_rust_frames() {
    let rt = runtime();
    let same: bool = rt
        .lua()
        .load(
            r#"
            local _, original = pcall(raise)
            original.note = "added in Lua"
            local ok, again = pcall(call, function () error(original) end)
            assert(not ok)
            -- and through xpcall's handler
            local _, handled = xpcall(call, function (e) return e end, function () error(original) end)
            return rawequal(original, again) and rawequal(original, handled) and again.note == "added in Lua"
            "#,
        )
        .eval()
        .unwrap();
    assert!(same);
}

#[test]
fn hosts_can_read_errors_that_escape_lua() {
    let rt = runtime();
    let lua: &Lua = rt.lua();
    let error = lua.load("raise()").exec().unwrap_err();
    let found = LuaError::find(&error).expect("a luastd.Error");
    assert_eq!((found.kind(), found.message()), ("Boom", "it broke"));

    let error = lua
        .load(r#"local _, e = pcall(raise); e.extra = "x"; call(function () error(e) end)"#)
        .exec()
        .unwrap_err();
    let table: Table = LuaError::find(&error).unwrap().table(lua).unwrap();
    assert_eq!(table.get::<String>("extra").unwrap(), "x");
    assert_eq!(table.get::<i64>("code").unwrap(), 42);
}

#[test]
fn error_still_adds_positions_to_strings() {
    let rt = runtime();
    let (located, bare): (String, String) = rt
        .lua()
        .load(
            r#"
            local _, a = pcall(function () error("boom") end)
            local _, b = pcall(function () error("bare", 0) end)
            return a, b
            "#,
        )
        .set_name("=t")
        .eval()
        .unwrap();
    assert_eq!(located, "t:2: boom");
    assert_eq!(bare, "bare");
}

#[test]
fn plain_tables_and_values_pass_through_unchanged() {
    let rt = runtime();
    let (kind, number): (String, i64) = rt
        .lua()
        .load(
            r#"
            local _, t = pcall(error, { kind = "Mine" })
            local _, n = pcall(error, 7)
            return t.kind, n
            "#,
        )
        .eval()
        .unwrap();
    assert_eq!((kind.as_str(), number), ("Mine", 7));
}

#[test]
fn slots_are_released_once_wrapped_copies_are_collected() {
    let rt = runtime();
    rt.lua()
        .load(
            r#"
            for _ = 1, 200 do
                local _, e = pcall(raise)
                pcall(call, function () error(e) end)
            end
            collectgarbage(); collectgarbage()
            "#,
        )
        .exec()
        .unwrap();
    // Drained lazily: the next error operation frees collected slots.
    rt.lua()
        .load("pcall(raise); collectgarbage(); collectgarbage(); pcall(raise)")
        .exec()
        .unwrap();
    assert!(
        live_error_slots(rt.lua()) <= 4,
        "{}",
        live_error_slots(rt.lua())
    );
}
