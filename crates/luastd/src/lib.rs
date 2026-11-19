//! Pure luastd modules: data-only, no IO.
//!
//! Every module here implements [`Module`] and is part of the floor that every
//! runtime installs (see `GLOSSARY.md`). `clippy.toml` in this crate disallows
//! the filesystem, environment and process APIs.

use mlua::{Lua, Result, Table};

pub mod formatx;
pub mod math;
pub mod path;
pub mod semver;
pub mod util;

pub use formatx::Formatx;
pub use math::Math;
pub use path::Path;
pub use semver::Semver;

/// A pure Lua module: builds its table from nothing but the Lua state.
///
/// Implemented on unit structs so hosts and builders can name modules as types
/// (`Path`, `Semver`, ...).
pub trait Module {
    /// The `require` name, such as `"luastd.path"`.
    const NAME: &'static str;

    /// Build the module table.
    fn create(lua: &Lua) -> Result<Table>;
}

/// A type-erased module constructor, as stored in [`FLOOR`].
pub type Loader = fn(&Lua) -> Result<Table>;

/// Every pure module as `(require name, constructor)`, in install order.
pub const FLOOR: &[(&str, Loader)] = &[
    (Root::NAME, Root::create),
    (Formatx::NAME, Formatx::create),
    (Math::NAME, Math::create),
    (Path::NAME, Path::create),
    (Semver::NAME, Semver::create),
];

/// The `luastd` root module: package metadata only.
pub struct Root;

impl Module for Root {
    const NAME: &'static str = "luastd";

    fn create(lua: &Lua) -> Result<Table> {
        let table = lua.create_table()?;
        table.set("version", env!("CARGO_PKG_VERSION"))?;
        Ok(table)
    }
}
