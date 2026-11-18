---@meta busted.runner

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

---@class busted.runner.options
---@field standalone? boolean  default true: exit the process when done
---@field output? string  default output handler (utfTerminal on a tty, else plainTerminal)

---Runs busted on the calling file. Put `require 'busted.runner'()` at the top of a spec
---to run it with plain `lua spec.lua`. Only the first call does anything.
---@param options? busted.runner.options
local function runner(options) end

return runner
