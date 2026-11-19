//! Every pure module loads through `package.preload` and does what its stub says.

use luastd::{FLOOR, Module, Path};
use mlua::{Function, Lua, Table};

fn lua_with_floor() -> Lua {
    let lua = Lua::new();
    let preload: Table = lua
        .globals()
        .get::<Table>("package")
        .and_then(|package| package.get("preload"))
        .unwrap();
    for (name, loader) in FLOOR {
        let loader = *loader;
        let function = lua.create_function(move |lua, ()| loader(lua)).unwrap();
        preload.set(*name, function).unwrap();
    }
    lua
}

#[test]
fn floor_names_are_unique_and_namespaced() {
    let mut names: Vec<_> = FLOOR.iter().map(|(name, _)| *name).collect();
    assert!(
        names
            .iter()
            .all(|name| *name == "luastd" || name.starts_with("luastd."))
    );
    names.sort_unstable();
    names.dedup();
    assert_eq!(names.len(), FLOOR.len());
    assert!(names.contains(&Path::NAME));
}

#[test]
fn every_floor_module_is_requirable() {
    let lua = lua_with_floor();
    let require: Function = lua.globals().get("require").unwrap();
    for (name, _) in FLOOR {
        let module: Table = require.call(*name).unwrap();
        assert!(
            module.pairs::<String, mlua::Value>().count() > 0,
            "{name} is empty"
        );
    }
}

#[test]
fn modules_work_together() {
    let lua = lua_with_floor();
    let rendered: String = lua
        .load(
            r#"
            local formatx = require("luastd.formatx")
            local math = require("luastd.math")
            local path = require("luastd.path")
            local semver = require("luastd.semver")
            return formatx.format("{} {} {}", math.add(1, 2), path.new("a") / "b", semver.parse("1.2.3"))
            "#,
        )
        .eval()
        .unwrap();
    assert_eq!(rendered, "3 a/b 1.2.3");
}

#[test]
fn math_add_raises_on_overflow() {
    let lua = lua_with_floor();
    let error = lua
        .load(r#"return require("luastd.math").add(9007199254740992, 9223372036854775807)"#)
        .exec()
        .unwrap_err();
    assert!(
        error.to_string().contains("integer overflow")
            || error.to_string().contains("integer expected"),
        "{error}"
    );
}
