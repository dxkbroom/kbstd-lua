#!/usr/bin/env -S lx --no-luarc lua --no-loader --only-deps --
--MISE description="Render EmmyLua definitions for luassert into definitions/luassert/"
--MISE sources=[
--MISE   "xtasks/tasks/render/emmy-luassert.lua",
--MISE   "xtasks/tasks-lib/fs.lua",
--MISE   "xtasks/tasks-lib/mise_env.lua",
--MISE ]
--MISE outputs=[
--MISE   "definitions/luassert/luassert.lua",
--MISE   "definitions/luassert/luassert.match.lua",
--MISE   "definitions/luassert/luassert.mock.lua",
--MISE   "definitions/luassert/luassert.spy.lua",
--MISE   "definitions/luassert/luassert.stub.lua",
--MISE ]
--USAGE flag "-o --out-dir <dir>" help="Output directory, relative to the project root" default="definitions/luassert"
-- Generates EmmyLua/LuaCATS meta definitions for luassert (upstream master, v1.8.0).
-- Runs on Lua 5.1-5.5 and LuaJIT. Tables are arrays of pairs so the output order is stable.
-- As a module (require), it renders nothing: call M.parse_command / M.main / M.render.

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

---Assertion name -> signature alias suffix.
---@type [string, string][]
local A = {
  { "true",               "is_true" },
  { "false",              "is_false" },
  { "boolean",            "type" },
  { "number",             "type" },
  { "string",             "type" },
  { "table",              "type" },
  { "nil",                "type" },
  { "userdata",           "type" },
  { "function",           "type" },
  { "thread",             "type" },
  { "returned_arguments", "returned_arguments" },
  { "same",               "same" },
  { "matches",            "matches" },
  { "match",              "matches" },
  { "near",               "near" },
  { "equals",             "equals" },
  { "equal",              "equals" },
  { "unique",             "unique" },
  { "error",              "error" },
  { "errors",             "error" },
  { "error_matches",      "error_matches" },
  { "error_match",        "error_matches" },
  { "matches_error",      "error_matches" },
  { "match_error",        "error_matches" },
  { "truthy",             "truthy" },
  { "falsy",              "falsy" },
  { "returned_with",      "returned_with" },
  { "called_with",        "called_with" },
  { "called",             "called" },
  { "called_at_least",    "called_n" },
  { "called_at_most",     "called_n" },
  { "called_more_than",   "called_n" },
  { "called_less_than",   "called_n" },
  { "holes",              "holes" },
}

---Signature alias suffix -> function type.
---@type [string, string][]
local SIG = {
  { "is_true",            "fun(value: any, message?: string): any" },
  { "is_false",           "fun(value: any, message?: string): any" },
  { "type",               "fun(value: any, message?: string): any" },
  { "returned_arguments", "fun(count: integer, ...: any): any" },
  { "same",               "fun(expected: any, actual: any, message?: string): any" },
  { "matches",            "fun(pattern: string, actual: string|number, init?: integer, plain?: boolean, message?: string): any" },
  { "near",               "fun(expected: number, actual: number, tolerance: number, message?: string): any" },
  { "equals",             "fun(expected: any, actual: any, message?: string): any" },
  { "unique",             "fun(list: table, deep?: boolean, message?: string): any" },
  { "error",              "fun(fn: function, expected_err?: any, message?: string): any" },
  { "error_matches",      "fun(fn: function, pattern: string, init?: integer, plain?: boolean, message?: string): string?" },
  { "truthy",             "fun(value: any, message?: string): any" },
  { "falsy",              "fun(value: any, message?: string): any" },
  { "returned_with",      "fun(...: any)" },
  { "called_with",        "fun(...: any)" },
  { "called",             "fun(times?: integer)" },
  { "called_n",           "fun(times: integer)" },
  { "holes",              "fun(length?: integer): integer?" },
}

---@type table<string, true?>
local KEYWORDS = { ["true"] = true, ["false"] = true, ["nil"] = true, ["function"] = true, ["not"] = true }

---Lua keywords can't be dot-accessed; luassert lowercases tokens, so a capital works.
---@param n string
---@return string
local function keyname(n)
  if KEYWORDS[n] then
    return n:sub(1, 1):upper() .. n:sub(2)
  end
  return n
end

local FILLER = { "a", "an", "the", "is", "are", "was", "has", "does" }

---Modifier -> its negation, in output order.
---@type [string, string][]
local NEG = {
  { "is",   "not" },
  { "are",  "not" },
  { "was",  "not" },
  { "has",  "no" },
  { "does", "not" },
}
---@type table<string, string>
local NEG_OF = {}
for _, p in ipairs(NEG) do
  NEG_OF[p[1]] = p[2]
end

---Compound prefixes: assert.is_not_nil, assert.has_no_errors, ...
---@type string[]
local PREFIXES = { "not", "no" }
for _, m in ipairs({ "is", "are", "was", "has", "does" }) do
  PREFIXES[#PREFIXES + 1] = m
  PREFIXES[#PREFIXES + 1] = m .. "_" .. NEG_OF[m]
end

---Matcher name -> constructor type.
---@type [string, string][]
local MATCHERS = {
  { "true",     "fun(): luassert.matcher" },
  { "false",    "fun(): luassert.matcher" },
  { "nil",      "fun(): luassert.matcher" },
  { "boolean",  "fun(): luassert.matcher" },
  { "number",   "fun(): luassert.matcher" },
  { "string",   "fun(): luassert.matcher" },
  { "table",    "fun(): luassert.matcher" },
  { "function", "fun(): luassert.matcher" },
  { "userdata", "fun(): luassert.matcher" },
  { "thread",   "fun(): luassert.matcher" },
  { "ref",      "fun(obj: any): luassert.matcher" },
  { "same",     "fun(expected: any): luassert.matcher" },
  { "matches",  "fun(pattern: string, init?: integer, plain?: boolean): luassert.matcher" },
  { "match",    "fun(pattern: string, init?: integer, plain?: boolean): luassert.matcher" },
  { "near",     "fun(expected: number, tolerance: number): luassert.matcher" },
  { "equals",   "fun(expected: any): luassert.matcher" },
  { "equal",    "fun(expected: any): luassert.matcher" },
  { "unique",   "fun(deep?: boolean): luassert.matcher" },
  { "truthy",   "fun(): luassert.matcher" },
  { "falsy",    "fun(): luassert.matcher" },
  { "none_of",  "fun(...: luassert.matcher): luassert.matcher" },
  { "any_of",   "fun(...: luassert.matcher): luassert.matcher" },
  { "all_of",   "fun(...: luassert.matcher): luassert.matcher" },
}

---Renders luassert.lua.
---@return string
local function render_luassert()
  ---@type string[]
  local o = {}

  ---@param s string
  local function w(s)
    o[#o + 1] = s
  end

  w[==[
---@meta luassert

-- Generated from lunarmodules/luassert master (v1.8.0) by `mise run render:emmy-luassert`. Do not edit by hand.
-- Lua keywords (true/false/nil/function/not) can't follow a dot, so they're typed
-- capitalized (assert.True, assert.is.Not). luassert lowercases tokens, so that works at runtime.

-- Assertion signatures ----------------------------------------------------
]==]
  for _, p in ipairs(SIG) do
    w("---@alias luassert.fn." .. p[1] .. " " .. p[2])
  end
  w("")

  w[==[
-- Matcher ------------------------------------------------------------------

---@class luassert.matcher
---@field name string
---@field mod boolean
---@field arguments table
---@operator call(any): boolean

-- Modifiers: plain words, and the ones that take an argument ---------------

---@class luassert.modifiers]==]
  for _, m in ipairs(FILLER) do
    w("---@field " .. m .. " luassert.chain")
  end
  w[==[
---@field Not luassert.chain  flips polarity (`not` is a keyword)
---@field no  luassert.chain  flips polarity]==]
  for _, p in ipairs(NEG) do
    w("---@field " .. p[1] .. "_" .. p[2] .. " luassert.chain")
  end
  w[==[
---@field message fun(msg: string): luassert.chain  sets the failure message for the rest of the chain
---@field spy  fun(s: luassert.spy|luassert.stub, message?: string): luassert.chain  sets the payload for called*/returned_with
---@field stub fun(s: luassert.stub, message?: string): luassert.chain
---@field array fun(arr: table): luassert.chain  sets the array for holes()

-- Assertions (bare names) --------------------------------------------------

---@class luassert.assertions]==]
  for _, p in ipairs(A) do
    w("---@field " .. keyname(p[1]) .. " luassert.fn." .. p[2])
  end
  w("")

  w[==[
-- Compound underscore forms: assert.is_not_nil, assert.has_no_errors, ... ---

---@class luassert.compound]==]
  for _, pre in ipairs(PREFIXES) do
    for _, p in ipairs(A) do
      w("---@field " .. pre .. "_" .. p[1] .. " luassert.fn." .. p[2])
    end
  end
  w("")

  w[==[
-- A chain in progress (what every modifier returns) ------------------------

---@class luassert.chain: luassert.modifiers, luassert.assertions, luassert.compound

-- The module ---------------------------------------------------------------

---@class luassert: luassert.chain
---@overload fun(v: any, message?: any, level?: luassert.level, ...: any): any, any, any, ...
---@field _COPYRIGHT string
---@field _DESCRIPTION string
---@field _VERSION string
local luassert = {}

---@class luassert.level
---@field level integer

---@alias luassert.namespace 'modifier'|'assertion'|'matcher'|string

---@return luassert.chain
function luassert.state() end

---@param nspace luassert.namespace
---@param name string
---@param callback fun(state: luassert.chain, arguments: table, level: integer): boolean?, table?
---@param positive_message? string  say key, used when the chain is positive
---@param negative_message? string  say key, used when the chain is negated
function luassert:register(nspace, name, callback, positive_message, negative_message) end

---@param nspace luassert.namespace
---@param name string
function luassert:unregister(nspace, name) end

---@param callback fun(value: any, fmtargs?: table): string?
function luassert:add_formatter(callback) end

---@param fmtr function
function luassert:remove_formatter(fmtr) end

---@param args table
---@return table
function luassert:format(args) end

---@param name string
---@param value any
function luassert:set_parameter(name, value) end

---@param name string
---@return any
function luassert:get_parameter(name) end

---@param spy luassert.spy
function luassert:add_spy(spy) end

---@return { revert: fun(self) }
function luassert:snapshot() end

---@param level integer
---@return luassert.level
function luassert:level(level) end

---@param level any
---@return integer?
function luassert:get_level(level) end
]==]

  w[==[
-- luassert.match -----------------------------------------------------------

---@class luassert.match.chain]==]
  for _, m in ipairs(FILLER) do
    w("---@field " .. m .. " luassert.match.chain")
  end
  w[==[
---@field Not luassert.match.chain
---@field no  luassert.match.chain]==]
  for _, p in ipairs(NEG) do
    w("---@field " .. p[1] .. "_" .. p[2] .. " luassert.match.chain")
  end
  for _, p in ipairs(MATCHERS) do
    w("---@field " .. keyname(p[1]) .. " " .. p[2])
  end
  for _, pre in ipairs(PREFIXES) do
    for _, p in ipairs(MATCHERS) do
      w("---@field " .. pre .. "_" .. p[1] .. " " .. p[2])
    end
  end
  w[==[

---@class luassert.match: luassert.match.chain
---@field _ luassert.matcher  matches anything
local match = {}

---@return luassert.match.chain
function match.state() end

---@param object any
---@return boolean
function match.is_matcher(object) end

---@param object any
---@return boolean
function match.is_ref_matcher(object) end

-- spy / stub (the parts the assertions rely on) ----------------------------

---@class luassert.spy
---@field calls { refs: any[], vals: any[] }[]
---@field returnvals any[][]
---@field callback function
---@operator call(...): any
---@field called fun(self, times?: integer, compare?: fun(count: integer, expected: integer): boolean): boolean, integer
---@field called_with fun(self, args: table): boolean, table
---@field returned_with fun(self, args: table): boolean, table
---@field clear fun(self): luassert.spy
---@field revert fun(self): any

---@class luassert.stub: luassert.spy
---@field returns fun(...: any): luassert.stub  dot-call: s.returns(1, 2)
---@field invokes fun(fn: function): luassert.stub
---@field by_default { returns: fun(...: any): luassert.stub, invokes: fun(fn: function): luassert.stub }
---@field on_call_with fun(...: any): { returns: fun(...: any): luassert.stub, invokes: fun(fn: function): luassert.stub }

return luassert]==]
  return table.concat(o, "\n") .. "\n"
end

---Static module files: require 'luassert.spy' / ... (busted exports these as spy/stub/mock).
---@type [string, string][]
local STATIC = {
  { "luassert.spy.lua", [==[
---@meta luassert.spy

---@class luassert.spy.module
---@overload fun(callback?: function): luassert.spy  same as spy.new
local spy = {}

---Wraps `callback` (default: a no-op) in a callable spy that records calls and return values.
---@param callback? function|table  function or callable table
---@return luassert.spy
function spy.new(callback) end

---Replaces `target_table[target_key]` with a spy around it; `revert()` puts the original back.
---@param target_table table
---@param target_key any
---@return luassert.spy
function spy.on(target_table, target_key) end

---@param object any
---@return boolean
function spy.is_spy(object) end

return spy
]==] },
  { "luassert.stub.lua", [==[
---@meta luassert.stub

---@class luassert.stub.module
---@overload fun(object?: table, key?: any, ...: any): luassert.stub  same as stub.new
local stub = {}

---Replaces `object[key]` with a stub. Extra args are its return values; a single callable extra arg
---is invoked instead. With no args at all you get a blank stub on a throwaway table.
---@param object? table
---@param key? any
---@param ... any  return values, or one function to call
---@return luassert.stub
function stub.new(object, key, ...) end

return stub
]==] },
  { "luassert.mock.lua", [==[
---@meta luassert.mock

---@class luassert.mock.module
---@overload fun(object: table, dostub?: boolean, func?: function): table  same as mock.new
local mock = {}

---Walks `object` (recursively) and replaces every function with a spy, or a stub when `dostub`
---is true (`func` becomes the stubs' implementation). Mutates and returns `object`.
---@generic T
---@param object T
---@param dostub? boolean
---@param func? function
---@return T
function mock.new(object, dostub, func) end

---Calls `clear()` on every spy/stub inside `object`.
---@generic T
---@param object T
---@return T
function mock.clear(object) end

---Calls `revert()` on every spy/stub inside `object`, restoring the originals.
---@generic T
---@param object T
---@return T
function mock.revert(object) end

return mock
]==] },
  { "luassert.match.lua", [==[
---@meta luassert.match

---@type luassert.match
local match

return match
]==] },
}

---Renders every output file as { file name, content } pairs, in write order.
---@return [string, string][]
function M.render()
  ---@type [string, string][]
  local files = { { "luassert.lua", render_luassert() } }
  for _, file in ipairs(STATIC) do
    files[#files + 1] = file
  end
  return files
end

---@class render.luassert.Command
---@field out_dir string  --out-dir: output directory, relative to the project root (or absolute)

---Builds the Command from the `usage_*` variables mise sets from the `--USAGE` spec.
---@param getenv? fun(name: string): string?  defaults to os.getenv
---@return render.luassert.Command?
---@return string? err
function M.parse_command(getenv)
  getenv = getenv or os.getenv
  local out_dir = (getenv("usage_out_dir") or ""):match("^%s*(.-)%s*$") or ""
  if out_dir == "" then
    return nil, "missing usage_out_dir (run via `mise run render:emmy-luassert`, or set usage_out_dir)"
  end
  ---@type render.luassert.Command
  local command = { out_dir = out_dir }
  return command
end

---Renders every file and writes them under `mise.project_root/command.out_dir`.
---@param command render.luassert.Command
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
  io.stderr:write("render:emmy-luassert: ", err or "invalid arguments", "\n")
  os.exit(2)
end

return M
