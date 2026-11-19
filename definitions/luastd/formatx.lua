---@meta luastd.formatx

--- A value that can be formatted by `luastd.formatx`.
---
--- Open by design: anything Lua can `tostring` is acceptable. This is not a
--- closed union of host types. Under the hood arguments are passed to
--- `formatx::FormatValue` (`Display + Debug`).
---@alias luastd.formatx.Value any

--- Named format arguments: string keys to formatable values.
---@alias luastd.formatx.Named { [string]: luastd.formatx.Value }

--- A parsed format string.
---
--- Backed by `formatx::Template`. Construction parses once; later
--- `render` / `render_lenient` / `contains` / `placeholders` reuse that
--- parse. `tostring` returns the original source string.
---
--- Construct with `formatx.new`. There is no runtime `formatx.Template` class
--- table.
---@class luastd.formatx.Template
local Template = {}

--- Return whether the template has a named placeholder `{name}`.
---@param name string
---@return boolean
function Template:contains(name) end

--- Return the names of every named placeholder, in source order.
---
--- Positional placeholders (`{}`, `{0}`) are omitted.
---@return string[]
function Template:placeholders() end

--- Format this template in strict mode.
---
--- Positional arguments are the formatable varargs. If the last argument is a
--- table, it is treated as named arguments (string keys only). Any value with
--- a Lua `tostring` is accepted. Extra arguments that no placeholder
--- references are ignored. Raises on a missing argument
--- (`missing argument: \`name\``) or an unsupported format trait.
---@param ... luastd.formatx.Value | luastd.formatx.Named
---@return string
function Template:render(...) end

--- Format this template in lenient mode.
---
--- Same argument rules as `render`, but missing arguments become `""`
--- instead of raising.
---@param ... luastd.formatx.Value | luastd.formatx.Named
---@return string
function Template:render_lenient(...) end

--- Runtime `std::fmt`-style string formatting.
---
--- Wraps the Rust `formatx` crate: runtime templates with `{}`, `{name}`,
--- width/precision/align/sign, and Debug (`{:?}` / `{:#?}`). Hex, octal,
--- binary, exp, and pointer traits are not supported. Arguments are any
--- Lua value that can be `tostring`'d; they map to `formatx::FormatValue`
--- (`Display + Debug`).
--- Construct reusable templates with `formatx.new`. One-shot helpers
--- (`format` / `formatl`) skip a reusable parse when you do not
--- need one.
---@class luastd.formatx
local formatx = {}

--- Parse `source` into a reusable template.
---
--- Pays for parsing here so later renders do not re-parse. Raises on a
--- malformed format string (unmatched braces, invalid specs, etc.). The
--- error text comes from `formatx` (`parse error at byte ...`).
---@param source string
---@return luastd.formatx.Template
function formatx.new(source) end

--- Format `template` in strict mode (like `formatx!`).
---
--- Positional arguments are the formatable varargs. If the last argument is a
--- table, it is treated as named arguments (string keys only). Any value with
--- a Lua `tostring` is accepted. Extra arguments that no placeholder
--- references are ignored. Raises on a parse error, a missing argument, or
--- an unsupported format trait.
---@param template string
---@param ...      luastd.formatx.Value | luastd.formatx.Named
---@return string
function formatx.format(template, ...) end

--- Format `template` in lenient mode (like `formatxl!`).
---
--- Same argument rules as `format`, but missing arguments become `""`
--- instead of raising. Parse errors and unsupported traits still raise.
---@param template string
---@param ...      luastd.formatx.Value | luastd.formatx.Named
---@return string
function formatx.formatl(template, ...) end

return formatx
