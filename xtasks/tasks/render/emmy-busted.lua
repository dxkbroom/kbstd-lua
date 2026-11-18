#!/usr/bin/env -S lx --no-luarc lua --no-loader --only-deps --
--MISE description="Render EmmyLua definitions for busted 2.3 into definitions/busted/"
--MISE sources=[
--MISE   "xtasks/tasks/render/emmy-busted.lua",
--MISE   "xtasks/tasks-lib/fs.lua",
--MISE   "xtasks/tasks-lib/mise_env.lua",
--MISE ]
--MISE outputs=[
--MISE   "definitions/busted/busted.core.lua",
--MISE   "definitions/busted/busted.done.lua",
--MISE   "definitions/busted/busted.fixtures.lua",
--MISE   "definitions/busted/busted.globals.lua",
--MISE   "definitions/busted/busted.lua",
--MISE   "definitions/busted/busted.outputHandlers.base.lua",
--MISE   "definitions/busted/busted.runner.lua",
--MISE   "definitions/busted/busted.status.lua",
--MISE ]
--USAGE flag "-o --out-dir <dir>" help="Output directory, relative to the project root" default="definitions/busted"
-- Generates EmmyLua/LuaCATS meta definitions for busted v2.3.0 (tag v2.3.0, commit 56e6d68).
-- Reuses the luassert types from render:emmy-luassert (luassert, luassert.match, luassert.spy.module, ...).
-- Runs on Lua 5.1-5.5 and LuaJIT. As a module (require), it renders nothing: call
-- M.parse_command / M.main / M.render.

-- Bootstrap: make xtasks/tasks-lib requirable. lx runs Lua in "pure" mode and ignores LUA_PATH,
-- so this stands in for Bun's `~/` import alias. Prefers MISE_CONFIG_ROOT, else this file's location.
do
  local config_root = os.getenv("MISE_CONFIG_ROOT")
  local lib
  if config_root and config_root ~= "" then
    lib = config_root .. "/xtasks/lib"
  else
    local info = debug.getinfo(1, "S")
    local this_file = info and info.source:gsub("^@", "") or "."
    lib = (this_file:match("^(.*)[/\\]") or ".") .. "/../../lib"
  end
  local entry = lib .. "/?.lua;"
  if not package.path:find(entry, 1, true) then
    package.path = entry .. package.path
  end
end

local fs = require("fs")
local mise_env = require("mise_env")

local M = {}

local HDR = "-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.\n"

---@class render.busted.Executor
---@field name string
---@field alias_of? string  descriptor it shares with (documentation only)
---@field doc string

---Executors registered in busted/init.lua, in registration order.
---Every one is exported into the spec environment AND into require('busted').
---@type render.busted.Executor[]
local EXEC = {
  { name = "describe",        doc = "Declares a group of tests. The body runs at load time to collect tests." },
  { name = "context",         alias_of = "describe", doc = "Alias of `describe`." },
  { name = "insulate",        alias_of = "describe", doc = "`describe` that snapshots _G and package.loaded and restores them afterwards." },
  { name = "expose",          alias_of = "describe", doc = "`describe` whose global writes and package.loaded entries leak out to the rest of the file and later files." },
  { name = "it",              doc = "Declares a test. Inside it, `pending(msg)` and `finally(fn)` are available." },
  { name = "spec",            alias_of = "it", doc = "Alias of `it`." },
  { name = "test",            alias_of = "it", doc = "Alias of `it`." },
  { name = "before_each",     doc = "Runs before every test in this block and nested blocks (outermost first)." },
  { name = "after_each",      doc = "Runs after every test in this block and nested blocks (innermost first)." },
  { name = "lazy_setup",      doc = "Runs once before the first test in this block that actually executes; skipped if no test runs." },
  { name = "lazy_teardown",   doc = "Runs once after the block, only if its lazy_setup ran." },
  { name = "strict_setup",    doc = "Runs once when the block starts, even if no test inside runs." },
  { name = "strict_teardown", doc = "Runs once when the block ends, even if no test inside ran." },
  { name = "setup",           alias_of = "strict_setup", doc = "Alias of `strict_setup` (of `lazy_setup` when busted runs with `--lazy`)." },
  { name = "teardown",        alias_of = "strict_teardown", doc = "Alias of `strict_teardown` (of `lazy_teardown` when busted runs with `--lazy`)." },
}

---@param name string
---@param doc string
---@return string
local function exec_fn(name, doc)
  return table.concat({
    "---" .. doc,
    "---Also callable as `" .. name .. "(fn)` or curried: `" .. name .. ' "name" (function() ... end)`.',
    "---@param name string",
    "---@param fn fun()",
    "---@overload fun(fn: fun())",
    "---@overload fun(name: string): fun(fn: fun())",
    "function " .. name .. "(name, fn) end",
    "",
  }, "\n")
end

---Joins `lines` with newlines plus a final newline. An entry may itself span several lines.
---@param lines string[]
---@return string
local function join(lines)
  return table.concat(lines, "\n") .. "\n"
end

---@return string
local function render_globals()
  local g = { "---@meta _", "", HDR, [==[
-- Names busted injects into every spec file's environment (busted/init.lua).
-- Not injected: `file` (registered then hidden), and publish/subscribe/... (only on require('busted')).
-- busted 2.x has no async/done/wait (busted/done.lua ships but nothing uses it).
]==] }
  g[#g + 1] = [==[
-- Blocks ---------------------------------------------------------------------
]==]
  for _, e in ipairs(EXEC) do
    g[#g + 1] = exec_fn(e.name, e.doc)
  end
  g[#g + 1] = [==[
---In a block body: declares a pending test (`pending("name")`; a function argument is ignored).
---Inside an `it`: stops the test right there and marks it pending (`pending("reason")`).
---@param name? string
---@param fn? fun()
function pending(name, fn) end

---Only inside an `it`: runs `fn` after the test body, even if it failed (cleanup).
---In 2.3.0 a second call replaces the first; chaining several arrived after 2.3.0.
---@param fn fun()
function finally(fn) end

---Only in a `describe`-like body or at file level: shuffles the tests and blocks in this block.
---`randomize()` / `randomize(true)` turn it on, `randomize(false)` off; a number sets the seed:
---`randomize(1234)` or `randomize(true, 1234)`. `--sort-tests` wins over it.
---@param enable_or_seed? boolean|number|string
---@param seed? number|string
function randomize(enable_or_seed, seed) end

-- luassert, exported as-is ----------------------------------------------------

---luassert, with failures raised through `busted.fail`.
---@type luassert
assert = nil

---@type luassert.spy.module
spy = nil

---@type luassert.stub.module
stub = nil

---@type luassert.mock.module
mock = nil

---@type luassert.match
match = nil]==]
  return join(g)
end

---@return string
local function render_busted()
  local m = { "---@meta busted", "", HDR, [==[
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
---@overload fun(core: busted.core): busted]==] }
  for _, e in ipairs(EXEC) do
    m[#m + 1] = "---@field " .. e.name .. " busted.executor"
  end
  m[#m + 1] = [==[
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

return busted]==]
  return join(m)
end

---Renders every output file as { file name, content } pairs, in write order.
---@return [string, string][]
function M.render()
  return {
    { "busted.globals.lua", render_globals() },
    { "busted.lua", render_busted() },
    { "busted.core.lua", join({ "---@meta busted.core", "", HDR, [==[
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

return new]==] }) },
    { "busted.fixtures.lua", join({ "---@meta busted.fixtures", "", HDR, [==[
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

return fixtures]==] }) },
    { "busted.runner.lua", join({ "---@meta busted.runner", "", HDR, [==[
---@class busted.runner.options
---@field standalone? boolean  default true: exit the process when done
---@field output? string  default output handler (utfTerminal on a tty, else plainTerminal)

---Runs busted on the calling file. Put `require 'busted.runner'()` at the top of a spec
---to run it with plain `lua spec.lua`. Only the first call does anything.
---@param options? busted.runner.options
local function runner(options) end

return runner]==] }) },
    { "busted.status.lua", join({ "---@meta busted.status", "", HDR, [==[
---Maps 'success'/'pending'/'failure'/'error', true, false and nil to a status object.
---@param initial? any
---@return busted.status
local function status(initial) end

return status]==] }) },
    { "busted.done.lua", join({ "---@meta busted.done", "", HDR, [==[
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

return M]==] }) },
    { "busted.outputHandlers.base.lua", join({ "---@meta busted.outputHandlers.base", "", HDR, [==[
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

return base]==] }) },
  }
end

---@class render.busted.Command
---@field out_dir string  --out-dir: output directory, relative to the project root (or absolute)

---Builds the Command from the `usage_*` variables mise sets from the `--USAGE` spec.
---@param getenv? fun(name: string): string?  defaults to os.getenv
---@return render.busted.Command?
---@return string? err
function M.parse_command(getenv)
  getenv = getenv or os.getenv
  local out_dir = (getenv("usage_out_dir") or ""):match("^%s*(.-)%s*$") or ""
  if out_dir == "" then
    return nil, "missing usage_out_dir (run via `mise run render:emmy-busted`, or set usage_out_dir)"
  end
  ---@type render.busted.Command
  local command = { out_dir = out_dir }
  return command
end

---Renders every file and writes them under `mise.project_root/command.out_dir`.
---@param command render.busted.Command
---@param mise mise.Env
---@return integer exit_code
function M.main(command, mise)
  local dir = fs.resolve(mise.project_root, command.out_dir)
  fs.mkdir_p(dir)
  for _, file in ipairs(M.render()) do
    fs.write_file(dir .. "/" .. file[1], file[2])
  end
  return 0
end
-- Entry point (Lua's `import.meta.main`): the main chunk run as a script has no Lua caller
-- at stack level 4, while require/dofile from Lua code does. (5.1 has no thread-less overload
-- in the annotations, hence the diagnostic suppression.)
---@diagnostic disable-next-line: missing-parameter
if not pcall(debug.getlocal, 4, 1) then
  local command, err = M.parse_command()
  if command then
    os.exit(M.main(command, mise_env.resolve()))
  end
  io.stderr:write("render:emmy-busted: ", err or "invalid arguments", "\n")
  os.exit(2)
end

return M
