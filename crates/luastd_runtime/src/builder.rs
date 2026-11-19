//! The typestate [`Builder`] for [`Runtime`].

use std::rc::Rc;

use deno_permissions::PermissionsContainer;
use mlua::{Lua, Result, Table};

use crate::sandbox::Options;
use crate::{EffectModule, Prompter, Runtime};

/// Builder state before permissions: only the floor can be installed.
#[derive(Debug, Default)]
pub struct NoPermissions;

/// Builder state with permissions: effect modules can be installed.
pub struct WithPermissions {
    permissions: PermissionsContainer,
    prompter: Option<Rc<dyn Prompter>>,
}

type EffectLoader = fn(&Lua, &PermissionsContainer) -> Result<Table>;

/// Configures a [`Runtime`]. Start with [`Runtime::builder`].
///
/// The floor is always installed. [`Builder::permissions`] moves to
/// `Builder<WithPermissions>`, the only state with [`Builder::effect`].
#[must_use]
pub struct Builder<P = NoPermissions> {
    state: P,
    options: Options,
    effects: Vec<(&'static str, EffectLoader)>,
}

impl Builder<NoPermissions> {
    pub(crate) fn new() -> Self {
        Self {
            state: NoPermissions,
            options: Options::default(),
            effects: Vec::new(),
        }
    }

    /// Hand the runtime its permissions, unlocking [`Builder::effect`].
    pub fn permissions(self, permissions: PermissionsContainer) -> Builder<WithPermissions> {
        Builder {
            state: WithPermissions {
                permissions,
                prompter: None,
            },
            options: self.options,
            effects: self.effects,
        }
    }

    /// Build a runtime with only the floor.
    pub fn build(self) -> Result<Runtime> {
        Runtime::new(self.options, None, None, &[])
    }
}

impl Builder<WithPermissions> {
    /// Install the effect module `M` under `package.preload[M::NAME]`.
    pub fn effect<M: EffectModule>(mut self) -> Self {
        self.effects.push((M::NAME, M::create));
        self
    }

    /// Answer deno's `prompt` state with the host's async [`Prompter`]
    /// (ADR 0004). Without one, `prompt` counts as denied.
    pub fn prompter(mut self, prompter: impl Prompter + 'static) -> Self {
        self.state.prompter = Some(Rc::new(prompter));
        self
    }

    /// Build a runtime with the floor and every requested effect module.
    pub fn build(self) -> Result<Runtime> {
        Runtime::new(
            self.options,
            Some(self.state.permissions),
            self.state.prompter,
            &self.effects,
        )
    }
}

impl<P> Builder<P> {
    /// Expose the `package` global with Lua's own searchers and paths.
    ///
    /// Off by default: `require` then only sees `package.preload`. Turning it
    /// on lets Lua code load `.lua` files through `package.path` without any
    /// permission check, so it is the host's call.
    pub fn package(mut self, expose: bool) -> Self {
        self.options.package = expose;
        self
    }

    /// Load the `debug` library.
    ///
    /// # Safety
    ///
    /// `debug` can read and replace upvalues, metatables and the registry,
    /// which breaks the sandbox and can violate mlua's memory-safety
    /// invariants (see `mlua::Lua::unsafe_new_with`).
    #[allow(unsafe_code)]
    pub unsafe fn debug(mut self) -> Self {
        self.options.debug = true;
        self
    }
}

pub(crate) fn install_preload(lua: &Lua, name: &str, loader: mlua::Function) -> Result<()> {
    let package: Table = lua.globals().get("package")?;
    let preload: Table = package.get("preload")?;
    preload.set(name, loader)?;
    Ok(())
}
