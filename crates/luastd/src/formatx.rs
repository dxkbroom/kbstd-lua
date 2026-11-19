//! The `luastd.formatx` Lua module.
//!
//! Wraps the `formatx` crate for runtime `std::fmt`-style templates. The
//! one-shot helpers (`format` / `formatl`) and reusable templates from
//! `formatx.new` share the same argument rules: positional values plus an
//! optional trailing table of named values. Strings, numbers, booleans and
//! userdata with `__tostring` are accepted.
//!
//! A template owns its source string and the parsed `formatx::Template` via
//! [`self_cell`], so `formatx.new` parses once and later renders reuse it.
//!
//! The earlier `kbstd.formatx` also had `f` / `fl`, which read the caller's
//! locals through the `debug` library. They were dropped: they need `debug`,
//! which is the host's choice, not part of the floor.

use std::fmt;

use ::formatx::{FormatArg, Template as FormatxTemplate};
use mlua::{
    Error as LuaError, Function, Lua, MetaMethod as LuaMetaMethod, MultiValue as LuaMultiValue,
    Result as LuaResult, Table, UserData, UserDataFields as LuaUserDataFields,
    UserDataMethods as LuaUserDataMethods, Value,
};
use self_cell::self_cell;

use crate::Module;
use crate::util::{bad_argument, string_argument};

pub const TYPE_NAME: &str = "luastd.formatx.Template";

/// The `luastd.formatx` module.
pub struct Formatx;

impl Module for Formatx {
    const NAME: &'static str = "luastd.formatx";

    fn create(lua: &Lua) -> LuaResult<Table> {
        let table = lua.create_table()?;
        table.set("new", lua.create_function(template_new)?)?;
        table.set("format", lua.create_function(formatx_format)?)?;
        table.set("formatl", lua.create_function(formatx_formatl)?)?;
        Ok(table)
    }
}

/// Lifetime-bound parsed template stored inside [`Template`].
type ParsedTemplate<'a> = FormatxTemplate<'a>;

self_cell!(
    /// A parsed format string exposed to Lua.
    pub struct Template {
        owner: String,

        #[covariant]
        dependent: ParsedTemplate,
    }

    impl {Debug}
);

impl fmt::Display for Template {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.borrow_owner())
    }
}

impl Template {
    fn parse(source: String) -> Result<Self, ::formatx::Error> {
        Self::try_new(source, |source| FormatxTemplate::new(source))
    }
}

impl UserData for Template {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        fields.add_meta_field(LuaMetaMethod::Type, TYPE_NAME);
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("contains", |_, this, name: Value| {
            let name = string_argument(&name, 2, "name", "contains")?;
            Ok(this.borrow_dependent().contains(&name))
        });

        methods.add_method("placeholders", |lua, this, ()| {
            let names = this
                .borrow_dependent()
                .placeholders()
                .into_iter()
                .map(str::to_owned)
                .collect::<Vec<_>>();
            lua.create_sequence_from(names)
        });

        methods.add_method("render", |lua, this, args: LuaMultiValue| {
            template_render_with(lua, this, args, "render", false)
        });

        methods.add_method("render_lenient", |lua, this, args: LuaMultiValue| {
            template_render_with(lua, this, args, "render_lenient", true)
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            Ok(this.borrow_owner().clone())
        });
    }
}

/// Owned format argument, kept alive for the duration of a render.
enum OwnedArg {
    Str(String),
    Int(i64),
    Float(f64),
    Bool(bool),
}

impl OwnedArg {
    fn as_format_arg(&self) -> FormatArg<'_> {
        match self {
            Self::Str(value) => FormatArg::from(value.as_str()),
            Self::Int(value) => FormatArg::from(value),
            Self::Float(value) => FormatArg::from(value),
            Self::Bool(value) => FormatArg::from(value),
        }
    }
}

/// Positional args plus named `(name, value)` pairs for one render.
type CollectedArgs = (Vec<OwnedArg>, Vec<(String, OwnedArg)>);

/// `formatx.format(template, ...) -> string`
fn formatx_format(lua: &Lua, args: LuaMultiValue) -> LuaResult<String> {
    format_with(lua, args, "format", false)
}

/// `formatx.formatl(template, ...) -> string`
fn formatx_formatl(lua: &Lua, args: LuaMultiValue) -> LuaResult<String> {
    format_with(lua, args, "formatl", true)
}

fn format_with(lua: &Lua, args: LuaMultiValue, function: &str, lenient: bool) -> LuaResult<String> {
    let mut args = args.into_vec();
    if args.is_empty() {
        return Err(bad_argument(1, "template", function, "string expected"));
    }
    let template = string_argument(&args.remove(0), 1, "template", function)?;
    let (positional, named) = collect_arguments(lua, &args, 2, function)?;
    let parsed =
        FormatxTemplate::new(&template).map_err(|error| LuaError::runtime(error.to_string()))?;
    render_template(&parsed, &positional, &named, lenient)
        .map_err(|error| LuaError::runtime(error.to_string()))
}

/// `formatx.new(source) -> Template`
fn template_new(_: &Lua, source: Value) -> LuaResult<Template> {
    let source = string_argument(&source, 1, "source", "new")?;
    Template::parse(source).map_err(|error| LuaError::runtime(error.to_string()))
}

fn template_render_with(
    lua: &Lua,
    this: &Template,
    args: LuaMultiValue,
    function: &str,
    lenient: bool,
) -> LuaResult<String> {
    let args = args.into_vec();
    let (positional, named) = collect_arguments(lua, &args, 2, function)?;
    render_template(this.borrow_dependent(), &positional, &named, lenient)
        .map_err(|error| LuaError::runtime(error.to_string()))
}

fn render_template(
    template: &FormatxTemplate<'_>,
    positional: &[OwnedArg],
    named: &[(String, OwnedArg)],
    lenient: bool,
) -> Result<String, ::formatx::Error> {
    let mut renderer = template.render();
    for argument in positional {
        renderer.arg(argument.as_format_arg());
    }
    for (name, argument) in named {
        renderer.named(name.as_str(), argument.as_format_arg());
    }
    if lenient {
        renderer.finish_lenient()
    } else {
        renderer.finish()
    }
}

fn collect_arguments(
    lua: &Lua,
    args: &[Value],
    start_index: usize,
    function: &str,
) -> LuaResult<CollectedArgs> {
    let (named, positional_args) = match args.split_last() {
        Some((Value::Table(table), rest)) => (
            named_arguments(lua, table, start_index + rest.len(), function)?,
            rest,
        ),
        _ => (Vec::new(), args),
    };

    let mut positional = Vec::with_capacity(positional_args.len());
    for (offset, value) in positional_args.iter().enumerate() {
        positional.push(format_value(lua, value, start_index + offset, function)?);
    }
    Ok((positional, named))
}

fn named_arguments(
    lua: &Lua,
    table: &Table,
    index: usize,
    function: &str,
) -> LuaResult<Vec<(String, OwnedArg)>> {
    let not_named = || bad_argument(index, "...", function, "named arguments table expected");
    let mut named = Vec::new();
    for pair in table.pairs::<Value, Value>() {
        let (key, entry) = pair?;
        let Value::String(text) = key else {
            return Err(not_named());
        };
        let name = text.to_str().map_err(|_| not_named())?.to_owned();
        named.push((name, format_value(lua, &entry, index, function)?));
    }
    Ok(named)
}

fn format_value(lua: &Lua, value: &Value, index: usize, function: &str) -> LuaResult<OwnedArg> {
    let expected = "string, number, boolean, or tostringable expected";
    match value {
        Value::String(text) => match text.to_str() {
            Ok(text) => Ok(OwnedArg::Str(text.to_owned())),
            Err(_) => Err(bad_argument(index, "...", function, expected)),
        },
        Value::Integer(integer) => Ok(OwnedArg::Int(*integer)),
        Value::Number(number)
            if number.fract() == 0.0 && number.is_finite() && number.abs() < 2f64.powi(53) =>
        {
            // LuaJIT has no integer subtype; keep `3` rendering as `3`.
            Ok(OwnedArg::Int(*number as i64))
        }
        Value::Number(number) => Ok(OwnedArg::Float(*number)),
        Value::Boolean(boolean) => Ok(OwnedArg::Bool(*boolean)),
        Value::UserData(_) => {
            let tostring: Function = lua.globals().get("tostring")?;
            Ok(OwnedArg::Str(tostring.call(value.clone())?))
        }
        _ => Err(bad_argument(index, "...", function, expected)),
    }
}
