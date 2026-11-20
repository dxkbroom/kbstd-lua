//! Every pure module loads through `package.preload` and does what its stub says.

use luastd::{DEFINITIONS, FLOOR, Module, Path};
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
            local path = require("luastd.path")
            local semver = require("luastd.semver")
            return formatx.format("{} {} {}", 3, path.new("a") / "b", semver.parse("1.2.3"))
            "#,
        )
        .eval()
        .unwrap();
    assert_eq!(rendered, "3 a/b 1.2.3");
}

#[test]
fn every_floor_module_has_a_definition_file() {
    for (name, _) in FLOOR {
        let file = match name.strip_prefix("luastd.") {
            Some(rest) => format!("luastd/{}.lua", rest.replace('.', "/")),
            None => "luastd/init.lua".to_owned(),
        };
        let (_, contents) = DEFINITIONS
            .iter()
            .find(|(path, _)| *path == file)
            .unwrap_or_else(|| panic!("{name} has no {file}"));
        assert!(contents.starts_with(&format!("---@meta {name}")), "{file}");
    }
}
