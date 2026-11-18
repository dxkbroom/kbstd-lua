//! Argument checks with `bad argument #N to 'fn' (...)` errors.
//!
//! Callbacks receive their arguments as [`mlua::Value`]s (typically through
//! [`mlua::MultiValue`]); these helpers validate one value and raise Lua errors
//! in the same format as the C API's `luaL_argerror`.

use mlua::{Error, Result, Value};

/// Format a standard bad-argument error.
pub fn bad_argument(index: usize, name: &str, function: &str, expected: &str) -> Error {
    Error::runtime(format!(
        "bad argument #{index} '{name}' to '{function}' ({expected})"
    ))
}

/// Require `value` (argument `index`) as a UTF-8 string.
///
/// Binary (non-UTF-8) strings report `UTF-8 string expected`; other types
/// report `string expected`.
pub fn string_argument(value: &Value, index: usize, name: &str, function: &str) -> Result<String> {
    match value {
        Value::String(text) => match text.to_str() {
            Ok(text) => Ok(text.to_owned()),
            Err(_) => Err(bad_argument(index, name, function, "UTF-8 string expected")),
        },
        _ => Err(bad_argument(index, name, function, "string expected")),
    }
}

/// Require `value` (argument `index`) as a Lua integer.
///
/// Whole-number floats are accepted, since LuaJIT represents every number as a
/// double.
#[expect(dead_code)]
pub fn integer_argument(value: &Value, index: usize, name: &str, function: &str) -> Result<i64> {
    match value {
        Value::Integer(integer) => Ok(*integer),
        Value::Number(number)
            if number.is_finite()
                && number.fract() == 0.0
                && *number >= i64::MIN as f64
                && *number < i64::MAX as f64 =>
        {
            Ok(*number as i64)
        }
        _ => Err(bad_argument(index, name, function, "integer expected")),
    }
}
