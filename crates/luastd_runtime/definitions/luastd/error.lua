---@meta _

--- A structured error raised by luastd: a table with a shared metatable, so
--- `pcall` callers can branch on `kind` and read context fields.
--- `tostring(err)` is `"<kind>: <message>"`.
---
--- It keeps its identity when it passes through Rust code: re-raising it with
--- `error(err)` and catching it again with `pcall` gives back the same table
--- (ADR 0006).
---@class luastd.Error
---@field kind     string
---@field message  string
---@field cause?   any    what led to this error, often another `luastd.Error`
---@field [string] any    context such as `path`, `permission` or `code`

--- Raised when the host's permissions do not grant an access.
---@class luastd.PermissionDeniedError: luastd.Error
---@field kind       "PermissionDenied"
---@field permission string             deno's permission name, such as `"env"`
---@field target?    string             the descriptor, such as the variable name

--- Raised when an argument has the wrong type or shape.
---@class luastd.InvalidArgumentError: luastd.Error
---@field kind "InvalidArgument"
