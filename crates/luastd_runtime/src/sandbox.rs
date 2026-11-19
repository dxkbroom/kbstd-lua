//! The global environment every runtime starts from.
//!
//! Standard libraries: everything mlua considers safe except `io`. Then:
//!
//! - `os` keeps only `clock`, `date`, `difftime` and `time`. Process control
//!   (`execute`, `exit`), filesystem (`remove`, `rename`, `tmpname`), `getenv`
//!   and `setlocale` (process-global) are removed; environment reads go
//!   through `luastd.env` with permissions.
//! - `dofile`, `loadfile` (filesystem) and `loadstring` are removed, and `load`
//!   only accepts text chunks: LuaJIT does not verify bytecode.
//! - `require` only sees `package.preload` (the floor and effect modules) and
//!   the `package` global is hidden, unless the host calls [`Builder::package`].
//! - `debug` is absent unless the host calls the unsafe [`Builder::debug`].
//!
//! [`Builder::package`]: crate::Builder::package
//! [`Builder::debug`]: crate::Builder::debug

use mlua::{Function, Lua, LuaOptions, Result, StdLib, Table, Value};

/// `os` functions that only read the clock.
const OS_KEEP: &[&str] = &["clock", "date", "difftime", "time"];

/// Globals that read files or load unverified bytecode.
const GLOBALS_REMOVE: &[&str] = &["dofile", "loadfile", "loadstring"];

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Options {
    pub package: bool,
    pub debug: bool,
}

pub(crate) fn new_lua(options: Options) -> Result<Lua> {
    let libs = StdLib::ALL_SAFE ^ StdLib::IO;
    let lua = if options.debug {
        // SAFETY: the host opted in through the `unsafe fn Builder::debug`,
        // accepting that `debug` can break the sandbox and mlua's invariants.
        #[allow(unsafe_code)]
        unsafe {
            Lua::unsafe_new_with(libs | StdLib::DEBUG, LuaOptions::default())
        }
    } else {
        Lua::new_with(libs, LuaOptions::default())?
    };

    let globals = lua.globals();
    restrict_os(&lua, &globals)?;
    for name in GLOBALS_REMOVE {
        globals.raw_set(*name, Value::Nil)?;
    }
    globals.raw_set("load", text_only_load(&lua, globals.get("load")?)?)?;
    if !options.package {
        let package: Table = globals.get("package")?;
        restrict_package(&package)?;
    }
    Ok(lua)
}

/// Hide `package` and leave only the preload searcher.
///
/// Called after preload is filled; `require` keeps its own reference to the
/// package table, so it still works without the global.
pub(crate) fn hide_package(lua: &Lua, options: Options) -> Result<()> {
    if !options.package {
        lua.globals().raw_set("package", Value::Nil)?;
    }
    Ok(())
}

fn restrict_os(lua: &Lua, globals: &Table) -> Result<()> {
    let os: Table = globals.get("os")?;
    let kept = lua.create_table()?;
    for name in OS_KEEP {
        kept.raw_set(*name, os.get::<Value>(*name)?)?;
    }
    globals.raw_set("os", kept.clone())?;
    if let Ok(package) = globals.get::<Table>("package")
        && let Ok(loaded) = package.get::<Table>("loaded")
    {
        loaded.raw_set("os", kept)?;
        loaded.raw_set("io", Value::Nil)?;
    }
    Ok(())
}

fn restrict_package(package: &Table) -> Result<()> {
    package.raw_set("path", "")?;
    package.raw_set("cpath", "")?;
    // Lua 5.1 / LuaJIT call them `loaders`, 5.2+ `searchers`; the first is preload.
    for key in ["searchers", "loaders"] {
        if let Ok(searchers) = package.get::<Table>(key) {
            let len = searchers.raw_len();
            for index in (2..=len).rev() {
                searchers.raw_remove(index)?;
            }
        }
    }
    Ok(())
}

fn text_only_load(lua: &Lua, load: Function) -> Result<Function> {
    lua.load(
        r##"
        local load, select = ...
        return function(chunk, name, _, ...)
            if select("#", ...) > 0 then
                return load(chunk, name, "t", ...)
            end
            return load(chunk, name, "t")
        end
        "##,
    )
    .set_name("=luastd.sandbox")
    .call((load, lua.globals().get::<Function>("select")?))
}
