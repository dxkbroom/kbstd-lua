---@meta busted.fixtures

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

---Paths and files relative to the calling spec file. Not a global: `require 'busted.fixtures'`.
---@class busted.fixtures
local fixtures = {}

---Absolute, normalised path of the calling file's directory, with `sub_path` joined on.
---@param sub_path? string
---@return string
function fixtures.path(sub_path) end

---Reads a file relative to the calling file; errors if it can't.
---@param rel_path string
---@param is_bin? boolean
---@return string
function fixtures.read(rel_path, is_bin) end

---Loads and runs a Lua file relative to the calling file ('.lua' is appended if missing).
---@param rel_path string
---@return any ...  whatever the chunk returns
function fixtures.load(rel_path) end

return fixtures
