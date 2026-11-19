//! Embedding runtime for luastd.
//!
//! A host builds a [`Runtime`] with [`Runtime::builder`]. The floor (every
//! pure module in [`luastd::FLOOR`]) is always installed under
//! `package.preload`, so Lua code reaches it with `require("luastd.path")`;
//! nothing is added to `_G`. Effect modules need permissions first:
//!
//! ```
//! # use luastd_runtime::{EffectModule, Runtime, permissions, mlua::{Lua, Result, Table}};
//! # use luastd_runtime::deno_permissions::PermissionsContainer;
//! # struct Fs;
//! # impl EffectModule for Fs {
//! #     const NAME: &'static str = "luastd.fs";
//! #     fn create(lua: &Lua, _: &PermissionsContainer) -> Result<Table> { lua.create_table() }
//! # }
//! let rt = Runtime::builder()
//!     .permissions(permissions::deny_all())
//!     .effect::<Fs>()
//!     .build()?;
//! # Ok::<(), luastd_runtime::mlua::Error>(())
//! ```
//!
//! `.effect` only exists after `.permissions`, so this does not compile:
//!
//! ```compile_fail
//! # use luastd_runtime::{EffectModule, Runtime, mlua::{Lua, Result, Table}};
//! # use luastd_runtime::deno_permissions::PermissionsContainer;
//! # struct Fs;
//! # impl EffectModule for Fs {
//! #     const NAME: &'static str = "luastd.fs";
//! #     fn create(lua: &Lua, _: &PermissionsContainer) -> Result<Table> { lua.create_table() }
//! # }
//! let rt = Runtime::builder().effect::<Fs>().build();
//! ```

pub mod annotations;
mod builder;
pub mod permissions;
mod runtime;
mod sandbox;

pub use builder::{Builder, NoPermissions, WithPermissions};
pub use runtime::Runtime;

pub use deno_permissions;
pub use luastd;
pub use mlua;

use deno_permissions::PermissionsContainer;
use mlua::{Lua, Result, Table};

/// A module that performs IO and checks every access against the host's
/// [`PermissionsContainer`].
///
/// Installed with [`Builder::effect`], which only exists once the builder has
/// permissions. The cargo feature decides whether a module is compiled in; the
/// container decides what it may touch at runtime.
pub trait EffectModule {
    /// The `require` name, such as `"luastd.fs"`.
    const NAME: &'static str;

    /// Build the module table; closures keep their own clone of `permissions`.
    fn create(lua: &Lua, permissions: &PermissionsContainer) -> Result<Table>;
}
