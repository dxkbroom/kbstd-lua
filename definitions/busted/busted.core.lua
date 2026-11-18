---@meta busted.core

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

---The context stack (busted/context.lua).
---@class busted.context
---@field get fun(key?: string): any  current element, or one of its fields
---@field set fun(key: string, value: any)
---@field clear fun()
---@field attach fun(child: busted.element)
---@field children fun(parent: busted.element): busted.element[]
---@field parent fun(child: busted.element): busted.element?
---@field push fun(current: busted.element)
---@field pop fun()

---The object behind require('busted'); helpers and output handlers mostly use the busted API instead.
---@class busted.core
---@field version string
---@field api table<string, any>  what require('busted') exposes
---@field executors table<string, busted.executor>
---@field context busted.context
---@field status fun(initial?: any): busted.status
---@field randomize? boolean  --shuffle-tests
---@field randomseed? number
---@field sort? boolean  --sort-tests
---@field skipAll? boolean  set after an error unless --keep-going
---@field gettime fun(): number
---@field monotime fun(): number
---@field sleep fun(seconds: number)
---@field publish fun(channel: busted.channel, ...: any): any[]
---@field subscribe fun(channel: busted.channel, fn: busted.subscriber_fn, options?: busted.subscribe_options): busted.subscriber
---@field unsubscribe fun(id: integer, channel: busted.channel): busted.subscriber?
---@field getTrace fun(element: busted.element, level?: integer, msg?: any): table
---@field rewriteMessage fun(element: busted.element, message: any, trace?: table): string
---@field getFile fun(element: busted.element): { name: string, getTrace: function, rewriteMessage?: function }?
---@field fail fun(msg: any, level?: integer)
---@field pending fun(msg?: string)
---@field bindfenv fun(callable: function|table, var: string, value: any)
---@field wrap fun(callable: function|table)  runs `callable` in busted's environment
---@field safe fun(descriptor: string, run: function, element: busted.element): busted.status, ...
---@field safe_publish fun(descriptor: string, channel: busted.channel, element: busted.element, ...: any): boolean
---@field exportApi fun(key: string, value: any)  adds to require('busted') only
---@field export fun(key: string, value: any)  adds to require('busted') and the spec environment
---@field hide fun(key: string)  removes from both
---@field register fun(descriptor: string, executor?: string|function|busted.attributes, attributes?: busted.attributes)
---@field execute fun(current?: busted.element)

---@return busted.core
local function new() end

return new
