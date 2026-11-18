---@meta busted.done

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

-- Leftover from busted 1.x async support. Installed in 2.3.0 but nothing in busted uses it.

---@class busted.done
---@field tokens string[]
---@field tokens_done string[]
---@field ordered boolean
---@field done_cb fun()
---@overload fun(token?: string)
local M = {}

---@param ... string
function M:wait(...) end
---@param ... string
function M:wait_unordered(...) end
---@param ... string
function M:wait_ordered(...) end
---@return string
function M:tokenlist() end
---@param token? string
function M:done(token) end

---@param done_callback fun()
---@return busted.done
function M.new(done_callback) end

return M
