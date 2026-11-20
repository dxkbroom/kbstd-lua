//! Structured errors (ADR 0006).
//!
//! In Lua a `luastd.Error` is a table with the shared `luastd.Error`
//! metatable: `kind`, `message`, optional `cause`, and any other fields;
//! `tostring` gives `"Kind: message"`.
//!
//! mlua turns any Lua error value that is not its own error userdata into a
//! string when it crosses a Rust frame. So a `luastd.Error` *travels* as an
//! mlua error wrapping [`LuaError`], and the runtime's `error`, `pcall` and
//! `xpcall` convert at the edges: `error(err)` wraps the table, and `pcall`
//! hands Lua code the table back. A slot keeps the table alive while any wrapped
//! copy exists, so the round trip returns the *same* table, and hosts can read
//! it with [`LuaError::find`] and [`LuaError::table`].

use std::borrow::Cow;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::fmt;
use std::sync::{Arc, Mutex, OnceLock, Weak};

use mlua::{Function, IntoLua, Lua, Result, Table, Value};

const METATABLE: &str = "luastd.Error";
const CANCELLED: &str = "luastd.Cancelled";
/// The kind of the cancellation error; see [`cancelled`].
pub const CANCELLED_KIND: &str = "Cancelled";

/// A field value converted only when the error reaches Lua.
type Deferred = Box<dyn FnOnce(&Lua) -> Result<Value> + Send>;

#[derive(Default)]
struct Pending {
    fields: Vec<(Cow<'static, str>, Deferred)>,
    cause: Option<Deferred>,
}

/// A structured error: raised from Rust with `Err(error.into())`, seen by Lua
/// as a `luastd.Error` table.
///
/// Fields and the cause accept any [`IntoLua`] value and are converted lazily,
/// so building an error needs no `Lua` handle.
pub struct LuaError {
    kind: Cow<'static, str>,
    message: String,
    pending: Mutex<Pending>,
    slot: OnceLock<Arc<Slot>>,
}

impl LuaError {
    pub fn new(kind: impl Into<Cow<'static, str>>, message: impl Into<String>) -> Self {
        Self {
            kind: kind.into(),
            message: message.into(),
            pending: Mutex::default(),
            slot: OnceLock::new(),
        }
    }

    /// Add a context field such as `path`, `permission` or `code`.
    pub fn with(
        self,
        key: impl Into<Cow<'static, str>>,
        value: impl IntoLua + Send + 'static,
    ) -> Self {
        self.lock()
            .fields
            .push((key.into(), Box::new(move |lua| value.into_lua(lua))));
        self
    }

    /// Set `cause`: another [`LuaError`], a message, or any Lua value.
    pub fn with_cause(self, cause: impl IntoLua + Send + 'static) -> Self {
        self.lock().cause = Some(Box::new(move |lua| cause.into_lua(lua)));
        self
    }

    /// Cancellation of the calling coroutine (ADR 0005). Its table is the
    /// shared sentinel that the runtime's `pcall` rethrows.
    pub fn cancelled() -> Self {
        Self::new(CANCELLED_KIND, "the coroutine was cancelled")
    }

    pub fn kind(&self) -> &str {
        &self.kind
    }

    pub fn message(&self) -> &str {
        &self.message
    }

    /// The `luastd.Error` inside an mlua error, through any wrapping
    /// (callback errors, context).
    pub fn find(error: &mlua::Error) -> Option<&LuaError> {
        error.downcast_ref::<LuaError>()
    }

    /// The Lua table for this error, built on first use; later calls (and
    /// every wrapped copy) return the same table.
    pub fn table(&self, lua: &Lua) -> Result<Table> {
        if let Some(slot) = self.slot.get() {
            return slots(lua).table(slot.id);
        }
        if self.kind == CANCELLED_KIND {
            let table = cancelled(lua)?;
            let slot = self.slot.get_or_init(|| slots(lua).register(&table));
            return slots(lua).table(slot.id);
        }
        let table = lua.create_table()?;
        table.set("kind", self.kind.as_ref())?;
        table.set("message", self.message.as_str())?;
        let pending = std::mem::take(&mut *self.lock());
        for (key, value) in pending.fields {
            table.set(key.as_ref(), value(lua)?)?;
        }
        if let Some(cause) = pending.cause {
            table.set("cause", cause(lua)?)?;
        }
        table.set_metatable(Some(metatable(lua)?))?;
        let slot = slots(lua).register(&table);
        let slot = self.slot.get_or_init(|| slot);
        slots(lua).table(slot.id)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Pending> {
        self.pending.lock().unwrap_or_else(|e| e.into_inner())
    }
}

impl fmt::Display for LuaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.kind, self.message)
    }
}

impl fmt::Debug for LuaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LuaError")
            .field("kind", &self.kind)
            .field("message", &self.message)
            .finish_non_exhaustive()
    }
}

impl std::error::Error for LuaError {}

impl From<LuaError> for mlua::Error {
    fn from(error: LuaError) -> Self {
        mlua::Error::external(error)
    }
}

impl IntoLua for LuaError {
    fn into_lua(self, lua: &Lua) -> Result<Value> {
        self.table(lua).map(Value::Table)
    }
}

/// Keeps a Lua table reachable while a wrapped copy of its error exists.
struct Slot {
    id: u64,
    freed: Arc<Mutex<Vec<u64>>>,
}

impl Drop for Slot {
    fn drop(&mut self) {
        // May run on any thread (mlua errors are Send); the Lua side drains it.
        if let Ok(mut freed) = self.freed.lock() {
            freed.push(self.id);
        }
    }
}

#[derive(Clone, Default)]
struct Slots(Arc<SlotsInner>);

#[derive(Default)]
struct SlotsInner {
    next: Mutex<u64>,
    freed: Arc<Mutex<Vec<u64>>>,
}

/// The Lua half of the slots; lives in app data on the Lua thread.
#[derive(Default)]
struct SlotTables {
    tables: RefCell<HashMap<u64, Table>>,
    by_table: RefCell<HashMap<usize, (u64, Weak<Slot>)>>,
    live: Cell<usize>,
}

struct SlotsRef<'lua> {
    lua: &'lua Lua,
    shared: Slots,
}

fn slots(lua: &Lua) -> SlotsRef<'_> {
    if lua.app_data_ref::<Slots>().is_none() {
        lua.set_app_data(Slots::default());
        lua.set_app_data(SlotTables::default());
    }
    let shared = lua
        .app_data_ref::<Slots>()
        .expect("installed above")
        .clone();
    let refs = SlotsRef { lua, shared };
    refs.drain();
    refs
}

impl SlotsRef<'_> {
    fn local(&self) -> mlua::AppDataRef<'_, SlotTables> {
        self.lua
            .app_data_ref::<SlotTables>()
            .expect("installed with Slots")
    }

    fn drain(&self) {
        let freed: Vec<u64> = std::mem::take(
            &mut *self
                .shared
                .0
                .freed
                .lock()
                .unwrap_or_else(|e| e.into_inner()),
        );
        if freed.is_empty() {
            return;
        }
        let local = self.local();
        let mut tables = local.tables.borrow_mut();
        let mut by_table = local.by_table.borrow_mut();
        for id in freed {
            if let Some(table) = tables.remove(&id) {
                let key = table.to_pointer() as usize;
                if by_table.get(&key).is_some_and(|(slot, _)| *slot == id) {
                    by_table.remove(&key);
                }
            }
        }
        local.live.set(tables.len());
    }

    /// The slot for `table`, reusing a live one so identity is preserved.
    fn register(&self, table: &Table) -> Arc<Slot> {
        let key = table.to_pointer() as usize;
        let local = self.local();
        if let Some(slot) = local
            .by_table
            .borrow()
            .get(&key)
            .and_then(|(_, w)| w.upgrade())
        {
            return slot;
        }
        let id = {
            let mut next = self.shared.0.next.lock().unwrap_or_else(|e| e.into_inner());
            *next += 1;
            *next
        };
        let slot = Arc::new(Slot {
            id,
            freed: self.shared.0.freed.clone(),
        });
        local.tables.borrow_mut().insert(id, table.clone());
        local
            .by_table
            .borrow_mut()
            .insert(key, (id, Arc::downgrade(&slot)));
        local.live.set(local.tables.borrow().len());
        slot
    }

    fn table(&self, id: u64) -> Result<Table> {
        self.local()
            .tables
            .borrow()
            .get(&id)
            .cloned()
            .ok_or_else(|| mlua::Error::runtime("luastd.Error from another Lua state"))
    }
}

/// How many error tables are kept alive by wrapped copies (for tests).
#[doc(hidden)]
pub fn live_error_slots(lua: &Lua) -> usize {
    let refs = slots(lua);
    refs.local().live.get()
}

/// The single cancellation error every luastd suspension point raises.
///
/// `pcall`/`xpcall` recognise it by identity and rethrow it (ADR 0005).
pub fn cancelled(lua: &Lua) -> Result<Table> {
    if let Ok(table) = lua.named_registry_value::<Table>(CANCELLED) {
        return Ok(table);
    }
    let table = lua.create_table()?;
    table.set("kind", CANCELLED_KIND)?;
    table.set("message", "the coroutine was cancelled")?;
    table.set_metatable(Some(metatable(lua)?))?;
    lua.set_named_registry_value(CANCELLED, &table)?;
    Ok(table)
}

fn metatable(lua: &Lua) -> Result<Table> {
    if let Ok(table) = lua.named_registry_value::<Table>(METATABLE) {
        return Ok(table);
    }
    let table = lua.create_table()?;
    table.set(
        "__tostring",
        lua.create_function(|_, error: Table| {
            Ok(format!(
                "{}: {}",
                error.get::<String>("kind")?,
                error.get::<String>("message")?
            ))
        })?,
    )?;
    lua.set_named_registry_value(METATABLE, &table)?;
    Ok(table)
}

/// Wrap a `luastd.Error` table so it survives Rust frames.
fn wrap(lua: &Lua, table: Table) -> Result<Value> {
    let kind: String = table.get::<Option<String>>("kind")?.unwrap_or_default();
    let message: String = table.get::<Option<String>>("message")?.unwrap_or_default();
    let error = LuaError::new(kind, message);
    let slot = slots(lua).register(&table);
    let _ = error.slot.set(slot);
    Ok(Value::Error(Box::new(error.into())))
}

/// The `luastd.Error` table inside a wrapped error, or `value` unchanged.
fn unwrap(lua: &Lua, value: Value) -> Result<Value> {
    if let Value::Error(error) = &value
        && let Some(error) = LuaError::find(error)
    {
        return error.table(lua).map(Value::Table);
    }
    Ok(value)
}

/// Replace `error`, `pcall` and `xpcall` so `luastd.Error` tables keep their
/// identity across Rust frames. Later layers wrap these, never the builtins.
pub(crate) fn install(lua: &Lua) -> Result<()> {
    let globals = lua.globals();
    let (error, pcall, xpcall): (Function, Function, Function) = lua
        .load(
            r#"
            local wrap, unwrap, meta, raw_error, raw_pcall, raw_xpcall = ...
            local function normalize(err)
                if type(err) == "userdata" then return unwrap(err) end
                return err
            end
            local function caught(ok, ...)
                if ok then return true, ... end
                return false, normalize((...))
            end
            local function error(value, level)
                if rawequal(getmetatable(value), meta) then value = wrap(value) end
                -- One more level for this wrapper; 0 still means no position.
                raw_error(value, level == 0 and 0 or (level or 1) + 1)
            end
            local function pcall(f, ...)
                return caught(raw_pcall(f, ...))
            end
            local function xpcall(f, handler, ...)
                return raw_xpcall(f, function (err) return handler(normalize(err)) end, ...)
            end
            return error, pcall, xpcall
            "#,
        )
        .set_name("=luastd.errors")
        .call((
            lua.create_function(wrap)?,
            lua.create_function(unwrap)?,
            metatable(lua)?,
            globals.get::<Function>("error")?,
            globals.get::<Function>("pcall")?,
            globals.get::<Function>("xpcall")?,
        ))?;
    globals.set("error", error)?;
    globals.set("pcall", pcall)?;
    globals.set("xpcall", xpcall)?;
    Ok(())
}
