//! [`Runtime`]: one Lua state plus the executor it runs on (ADR 0003).

use std::rc::Rc;

use deno_permissions::PermissionsContainer;
use mlua::{Lua, Result, Table};
use tokio::task::LocalSet;

use crate::Prompter;
use crate::builder::{Builder, NoPermissions, install_preload};
use crate::prompt::{PrompterSlot, install_global_prompter};
use crate::sandbox::{self, Options};

type EffectLoader = fn(&Lua, &PermissionsContainer) -> Result<Table>;

/// A sandboxed Lua state with the floor installed, and the current-thread
/// tokio runtime plus [`LocalSet`] that drives it.
///
/// `Runtime` is not `Send` (ADR 0002): keep it on the thread that built it.
pub struct Runtime {
    lua: Lua,
    permissions: Option<PermissionsContainer>,
    tokio: tokio::runtime::Runtime,
    local: LocalSet,
}

impl Runtime {
    /// Start configuring a runtime.
    pub fn builder() -> Builder<NoPermissions> {
        Builder::new()
    }

    pub(crate) fn new(
        options: Options,
        permissions: Option<PermissionsContainer>,
        prompter: Option<Rc<dyn Prompter>>,
        effects: &[(&'static str, EffectLoader)],
    ) -> Result<Self> {
        let lua = sandbox::new_lua(options)?;
        crate::errors::install(&lua)?;
        if permissions.is_some() {
            // deno's default prompter blocks on the TTY (ADR 0004).
            install_global_prompter();
        }
        if let Some(prompter) = prompter {
            lua.set_app_data(PrompterSlot(prompter));
        }
        for (name, loader) in luastd::FLOOR {
            let loader = *loader;
            install_preload(&lua, name, lua.create_function(move |lua, ()| loader(lua))?)?;
        }
        if let Some(permissions) = &permissions {
            for (name, loader) in effects {
                let loader = *loader;
                let permissions = permissions.clone();
                install_preload(
                    &lua,
                    name,
                    lua.create_function(move |lua, ()| loader(lua, &permissions))?,
                )?;
            }
        }
        sandbox::hide_package(&lua, options)?;

        let tokio = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(mlua::Error::external)?;
        Ok(Self {
            lua,
            permissions,
            tokio,
            local: LocalSet::new(),
        })
    }

    /// The Lua state, for synchronous setup outside [`Runtime::run`].
    pub fn lua(&self) -> &Lua {
        &self.lua
    }

    /// The permissions effect modules check against, if any.
    pub fn permissions(&self) -> Option<&PermissionsContainer> {
        self.permissions.as_ref()
    }

    /// Drive `main` to completion on this runtime's executor.
    ///
    /// `main` is the host's own loop: load the user's init chunk with
    /// `exec_async`, then `select!` over input, timers and messages from Lua.
    /// Everything runs on the current thread, so `main` may hold the `Lua`
    /// across awaits and use `tokio::task::spawn_local`.
    ///
    /// ```
    /// # use luastd_runtime::Runtime;
    /// let rt = Runtime::builder().build()?;
    /// let sum: i64 = rt.run(async |lua| lua.load("return 1 + 2").eval_async().await)?;
    /// assert_eq!(sum, 3);
    /// # Ok::<(), luastd_runtime::mlua::Error>(())
    /// ```
    ///
    /// # Panics
    ///
    /// When called from inside another tokio runtime, including a nested
    /// `run`.
    pub fn run<T>(&self, main: impl AsyncFnOnce(Lua) -> Result<T>) -> Result<T> {
        // Hook: the async layer opens the implicit root scope around `main`
        // here (PLAN.md, `luastd/async`).
        self.local.block_on(&self.tokio, main(self.lua.clone()))
    }
}
