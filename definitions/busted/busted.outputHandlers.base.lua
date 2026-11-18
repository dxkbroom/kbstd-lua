---@meta busted.outputHandlers.base

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

---@class busted.output_options
---@field defaultOutput? string
---@field enableSound? boolean
---@field verbose? boolean
---@field suppressPending? boolean
---@field language? string
---@field deferPrint? boolean
---@field arguments? string[]  from -Xoutput

---@class busted.formatted
---@field name string  full test name
---@field element table  copy of the element without functions/env
---@field trace? table
---@field message? string
---@field randomseed? number
---@field isError? boolean

---A custom output handler is `return function(options) local h = require('busted.outputHandlers.base')() ... return h end`.
---@class busted.output_handler
---@field options busted.output_options
---@field successes busted.formatted[]
---@field successesCount integer
---@field pendings busted.formatted[]
---@field pendingsCount integer
---@field failures busted.formatted[]
---@field failuresCount integer
---@field errors busted.formatted[]
---@field errorsCount integer
---@field inProgress table<string, table>
---@field startTick? number
---@field startTime? number
---@field endTick? number
---@field endTime? number
---@field subscribe fun(self: busted.output_handler, options: busted.output_options)
---@field cancelOnPending fun(element: busted.element, parent: busted.element?, status?: string): boolean
---@field getFullName fun(element: busted.element): string
---@field format fun(element: busted.element, parent: busted.element?, message?: string, debug?: table, isError?: boolean): busted.formatted
---@field getDuration fun(): number
---@field baseSuiteStart fun(suite: busted.element): nil, boolean
---@field baseSuiteReset fun(): nil, boolean
---@field baseSuiteEnd fun(suite: busted.element): nil, boolean
---@field baseTestStart fun(element: busted.element, parent: busted.element?): nil, boolean
---@field baseTestEnd fun(element: busted.element, parent: busted.element?, status: busted.status_name, debug?: table): nil, boolean
---@field basePending fun(element: busted.element, parent: busted.element?, message?: string, debug?: table): nil, boolean
---@field baseTestFailure fun(element: busted.element, parent: busted.element?, message?: string, debug?: table): nil, boolean
---@field baseTestError fun(element: busted.element, parent: busted.element?, message?: string, debug?: table): nil, boolean
---@field baseError fun(element: busted.element, parent: busted.element?, message?: string, debug?: table): nil, boolean
---@field [string] any  your own suiteStart/testEnd/... callbacks

---@return busted.output_handler
local function base() end

return base
