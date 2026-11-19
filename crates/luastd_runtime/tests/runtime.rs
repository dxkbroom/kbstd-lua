//! The runtime's sandbox, floor, typestate builder, executor and annotations.

use std::fs;
use std::time::Duration;

use luastd_runtime::deno_permissions::PermissionsContainer;
use luastd_runtime::mlua::{Lua, Result, Table};
use luastd_runtime::{EffectModule, Runtime, annotations, permissions};

fn floor_only() -> Runtime {
    Runtime::builder().build().unwrap()
}

#[test]
fn floor_is_requirable_without_globals() {
    let rt = floor_only();
    rt.lua()
        .load(
            r#"
            for _, name in ipairs({ "luastd", "luastd.formatx", "luastd.math", "luastd.path", "luastd.semver" }) do
                assert(type(require(name)) == "table", name)
                assert(rawget(_G, name) == nil, name .. " leaked into _G")
            end
            assert(rawget(_G, "luastd") == nil)
            assert(tostring(require("luastd.path").new("a") / "b") == "a/b")
            "#,
        )
        .exec()
        .unwrap();
}

#[test]
fn io_and_process_control_are_absent() {
    let rt = floor_only();
    rt.lua()
        .load(
            r#"
            assert(io == nil, "io")
            assert(debug == nil, "debug")
            assert(package == nil, "package")
            assert(dofile == nil and loadfile == nil and loadstring == nil, "file loaders")
            for _, name in ipairs({ "execute", "exit", "remove", "rename", "tmpname", "getenv", "setlocale" }) do
                assert(os[name] == nil, "os." .. name)
            end
            assert(type(os.time()) == "number" and type(os.clock()) == "number")
            assert(type(os.date("%Y")) == "string" and os.difftime(2, 1) == 1)
            "#,
        )
        .exec()
        .unwrap();
}

#[test]
fn require_only_sees_preload() {
    let rt = floor_only();
    let error = rt
        .lua()
        .load(r#"require("luastd_definitely_not_a_module")"#)
        .exec()
        .unwrap_err()
        .to_string();
    assert!(error.contains("luastd_definitely_not_a_module"), "{error}");
    assert!(!error.contains(".lua"), "searched the filesystem: {error}");
}

#[test]
fn load_rejects_bytecode() {
    let rt = floor_only();
    let (ok, message): (bool, Option<String>) = rt
        .lua()
        .load(
            r#"
            local text, text_err = load("return 1")
            assert(text and text() == 1, text_err)
            local env_fn = load("return x", "=env", "t", { x = 7 })
            if env_fn then assert(env_fn() == 7) end
            local chunk, err = load(string.dump(function() return 1 end))
            return chunk ~= nil, err
            "#,
        )
        .eval()
        .unwrap();
    assert!(!ok, "binary chunk loaded");
    assert!(message.is_some());
}

#[test]
fn package_is_opt_in() {
    let rt = Runtime::builder().package(true).build().unwrap();
    let path: String = rt.lua().load("return package.path").eval().unwrap();
    assert!(!path.is_empty());
    rt.lua()
        .load(r#"assert(require("luastd.path"))"#)
        .exec()
        .unwrap();
}

#[test]
#[allow(unsafe_code)]
fn debug_is_opt_in() {
    // SAFETY: test-only; nothing here touches upvalues or the registry.
    let rt = unsafe { Runtime::builder().debug() }.build().unwrap();
    let kind: String = rt
        .lua()
        .load("return type(debug.traceback)")
        .eval()
        .unwrap();
    assert_eq!(kind, "function");
}

struct Probe;

impl EffectModule for Probe {
    const NAME: &'static str = "luastd.probe";

    fn create(lua: &Lua, permissions: &PermissionsContainer) -> Result<Table> {
        let table = lua.create_table()?;
        table.set("env_allowed", permissions.check_env("HOME").is_ok())?;
        Ok(table)
    }
}

#[test]
fn effect_modules_get_the_permissions() {
    let denied = Runtime::builder()
        .permissions(permissions::deny_all())
        .effect::<Probe>()
        .build()
        .unwrap();
    let allowed = Runtime::builder()
        .permissions(permissions::allow_all())
        .effect::<Probe>()
        .build()
        .unwrap();
    let probe = r#"return require("luastd.probe").env_allowed"#;
    assert!(!denied.lua().load(probe).eval::<bool>().unwrap());
    assert!(allowed.lua().load(probe).eval::<bool>().unwrap());
    assert!(allowed.permissions().is_some());
    assert!(floor_only().permissions().is_none());
}

#[test]
fn run_drives_async_lua_and_timers() {
    let rt = floor_only();
    let sleep = rt
        .lua()
        .create_async_function(|_, ms: u64| async move {
            tokio::time::sleep(Duration::from_millis(ms)).await;
            Ok(ms)
        })
        .unwrap();
    rt.lua().globals().set("sleep", sleep).unwrap();
    let total: u64 = rt
        .run(async |lua| {
            let local = tokio::task::spawn_local(async { 1u64 });
            let slept: u64 = lua.load("return sleep(5) + sleep(5)").eval_async().await?;
            Ok(slept + local.await.unwrap())
        })
        .unwrap();
    assert_eq!(total, 11);
}

#[test]
fn annotations_cover_the_floor() {
    let dir = tempfile::tempdir().unwrap();
    let written = annotations::write(dir.path()).unwrap();
    assert_eq!(written.len(), luastd_runtime::luastd::DEFINITIONS.len());
    let path = fs::read_to_string(dir.path().join("luastd/path.lua")).unwrap();
    assert!(path.starts_with("---@meta luastd.path"));
}

#[test]
fn merge_emmyrc_creates_the_file() {
    let dir = tempfile::tempdir().unwrap();
    let emmyrc = dir.path().join("nested/.emmyrc.json");
    annotations::merge_emmyrc(&emmyrc, "./library").unwrap();
    let json: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&emmyrc).unwrap()).unwrap();
    assert_eq!(
        json["workspace"]["library"],
        serde_json::json!(["./library"])
    );
}

#[test]
fn merge_emmyrc_preserves_other_keys_and_is_idempotent() {
    let dir = tempfile::tempdir().unwrap();
    let emmyrc = dir.path().join(".emmyrc.json");
    fs::write(
        &emmyrc,
        r#"{
  "$schema": "https://example.invalid/schema.json",
  "workspace": { "workspaceRoots": ["./spec"], "library": ["./other"] },
  "hint": { "paramHint": true }
}"#,
    )
    .unwrap();
    annotations::merge_emmyrc(&emmyrc, "./library").unwrap();
    annotations::merge_emmyrc(&emmyrc, "./library").unwrap();
    let text = fs::read_to_string(&emmyrc).unwrap();
    let json: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(
        json["workspace"]["library"],
        serde_json::json!(["./other", "./library"])
    );
    assert_eq!(
        json["workspace"]["workspaceRoots"],
        serde_json::json!(["./spec"])
    );
    assert_eq!(json["hint"]["paramHint"], serde_json::json!(true));
    assert!(
        text.find("$schema").unwrap() < text.find("workspace").unwrap(),
        "key order changed"
    );
}

#[test]
fn merge_emmyrc_rejects_a_non_object() {
    let dir = tempfile::tempdir().unwrap();
    let emmyrc = dir.path().join(".emmyrc.json");
    fs::write(&emmyrc, "[]").unwrap();
    let error = annotations::merge_emmyrc(&emmyrc, "./library").unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
}
