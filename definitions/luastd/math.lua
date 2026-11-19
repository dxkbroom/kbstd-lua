---@meta luastd.math

--- Integer helpers that complement Lua's builtin `math`.
---@class luastd.math
local math = {}

--- Add two integers.
---
--- Raises instead of wrapping on overflow. Whole-number floats are accepted,
--- since LuaJIT represents every number as a double.
---@param left  integer
---@param right integer
---@return integer
function math.add(left, right) end

return math
