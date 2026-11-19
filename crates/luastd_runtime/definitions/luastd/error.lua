---@meta _

--- A structured error raised by luastd: a table, so `pcall` callers can
--- branch on `kind`. `tostring(err)` is `"<kind>: <message>"`.
---@class luastd.Error
---@field kind    string
---@field message string

--- Raised when the host's permissions do not grant an access.
---@class luastd.PermissionDeniedError: luastd.Error
---@field kind       "PermissionDenied"
---@field permission string             deno's permission name, such as `"env"`
---@field target?    string             the descriptor, such as the variable name

--- Raised when an argument has the wrong type or shape.
---@class luastd.InvalidArgumentError: luastd.Error
---@field kind "InvalidArgument"
