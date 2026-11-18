---@meta busted

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

-- Shared types -----------------------------------------------------------------

---A registered block function: describe, it, before_each, ... (busted/core.lua `register`).
---@class busted.executor
---@overload fun(name: string, fn: fun())
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())

---Mediator channel, e.g. {'test','end'}, {'suite','start'}, {'error','it'}, {'failure'}, {'exit'}.
---Publishing on {'a','b'} also notifies subscribers of {'a'}.
---Known channels: suite start/end/reset, file start/end, describe start/end, test start/end,
---{status, descriptor} for 'error'/'failure' (status 'error'|'failure', descriptor of the failing block),
---register <descriptor>, error output/helper/file, pending, exit.
---@alias busted.channel string[]

---@alias busted.status_name 'success'|'pending'|'failure'|'error'

---@class busted.subscribe_options
---@field predicate? fun(...: any): boolean  only call the subscriber when this returns true
---@field priority? integer  position in the channel's callback list (1 = first)

---Return `nil, true` to let the remaining subscribers run; a falsy 2nd value stops propagation.
---@alias busted.subscriber_fn fun(...: any): any, boolean?

---@class busted.subscriber
---@field id integer
---@field fn busted.subscriber_fn
---@field options busted.subscribe_options
---@field channel table
---@field update fun(self: busted.subscriber, options?: { fn?: busted.subscriber_fn, options?: busted.subscribe_options })

---@class busted.attributes
---@field envmode? 'insulate'|'expose'|'unwrap'
---@field default_fn? fun()

---A node in the test tree: the suite, a file, a describe, an it, a hook, ...
---@class busted.element
---@field descriptor string  'suite'|'file'|'describe'|'it'|'pending'|'before_each'|...
---@field name? string
---@field run? function
---@field trace? table  debug.getinfo-style table where the block was declared
---@field attributes busted.attributes
---@field env? table  per-block environment overlay
---@field starttime? number
---@field endtime? number
---@field starttick? number
---@field endtick? number
---@field duration? number  seconds (monotonic)
---@field randomseed? number  set on blocks whose children were shuffled
---@field message? string

---@class busted.status
---@field success fun(self: busted.status): boolean
---@field pending fun(self: busted.status): boolean
---@field failure fun(self: busted.status): boolean
---@field error fun(self: busted.status): boolean
---@field get fun(self: busted.status): busted.status_name
---@field set fun(self: busted.status, status: any)
---@field update fun(self: busted.status, status: any)  keeps an existing failure/error

-- require('busted') -------------------------------------------------------------

---The busted API table. Once the runner has initialised it, every field is read from busted.api;
---writing to it raises 'Attempt to modify busted'. Calling it (`require('busted')(core)`) is
---what the runner does to initialise it.
---@class busted
---@overload fun(core: busted.core): busted
---@field describe busted.executor
---@field context busted.executor
---@field insulate busted.executor
---@field expose busted.executor
---@field it busted.executor
---@field spec busted.executor
---@field test busted.executor
---@field before_each busted.executor
---@field after_each busted.executor
---@field lazy_setup busted.executor
---@field lazy_teardown busted.executor
---@field strict_setup busted.executor
---@field strict_teardown busted.executor
---@field setup busted.executor
---@field teardown busted.executor
---@field pending fun(name?: string, fn?: fun())
---@field assert luassert
---@field spy luassert.spy.module
---@field stub luassert.stub.module
---@field mock luassert.mock.module
---@field match luassert.match
---@field version string  '2.3.0'
local busted = {}

---@param channel busted.channel
---@param ... any
---@return any[] results  first return value of each subscriber that returned one
function busted.publish(channel, ...) end

---@param channel busted.channel
---@param fn busted.subscriber_fn
---@param options? busted.subscribe_options
---@return busted.subscriber
function busted.subscribe(channel, fn, options) end

---@param id integer  subscriber.id
---@param channel busted.channel
---@return busted.subscriber?
function busted.unsubscribe(id, channel) end

---Gives `callable` (or its __call) an environment where `var` is `value`, falling back to its old env.
---@param callable function|table
---@param var string
---@param value any
function busted.bindfenv(callable, var, value) end

---Raises a test failure (as opposed to an error).
---@param msg any
---@param level? integer
function busted.fail(msg, level) end

---Wall-clock time in seconds (luasystem).
---@return number
function busted.gettime() end

---Monotonic time in seconds (luasystem).
---@return number
function busted.monotime() end

---@param seconds number
function busted.sleep(seconds) end

---@param element busted.element
---@return busted.element?
function busted.parent(element) end

---@param element busted.element
---@return busted.element[]
function busted.children(element) end

return busted
