---@meta _

-- Generated from lunarmodules/busted v2.3.0 by `mise run render:emmy-busted`. Do not edit by hand.

-- Names busted injects into every spec file's environment (busted/init.lua).
-- Not injected: `file` (registered then hidden), and publish/subscribe/... (only on require('busted')).
-- busted 2.x has no async/done/wait (busted/done.lua ships but nothing uses it).

-- Blocks ---------------------------------------------------------------------

---Declares a group of tests. The body runs at load time to collect tests.
---Also callable as `describe(fn)` or curried: `describe "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function describe(name, fn) end

---Alias of `describe`.
---Also callable as `context(fn)` or curried: `context "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function context(name, fn) end

---`describe` that snapshots _G and package.loaded and restores them afterwards.
---Also callable as `insulate(fn)` or curried: `insulate "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function insulate(name, fn) end

---`describe` whose global writes and package.loaded entries leak out to the rest of the file and later files.
---Also callable as `expose(fn)` or curried: `expose "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function expose(name, fn) end

---Declares a test. Inside it, `pending(msg)` and `finally(fn)` are available.
---Also callable as `it(fn)` or curried: `it "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function it(name, fn) end

---Alias of `it`.
---Also callable as `spec(fn)` or curried: `spec "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function spec(name, fn) end

---Alias of `it`.
---Also callable as `test(fn)` or curried: `test "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function test(name, fn) end

---Runs before every test in this block and nested blocks (outermost first).
---Also callable as `before_each(fn)` or curried: `before_each "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function before_each(name, fn) end

---Runs after every test in this block and nested blocks (innermost first).
---Also callable as `after_each(fn)` or curried: `after_each "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function after_each(name, fn) end

---Runs once before the first test in this block that actually executes; skipped if no test runs.
---Also callable as `lazy_setup(fn)` or curried: `lazy_setup "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function lazy_setup(name, fn) end

---Runs once after the block, only if its lazy_setup ran.
---Also callable as `lazy_teardown(fn)` or curried: `lazy_teardown "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function lazy_teardown(name, fn) end

---Runs once when the block starts, even if no test inside runs.
---Also callable as `strict_setup(fn)` or curried: `strict_setup "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function strict_setup(name, fn) end

---Runs once when the block ends, even if no test inside ran.
---Also callable as `strict_teardown(fn)` or curried: `strict_teardown "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function strict_teardown(name, fn) end

---Alias of `strict_setup` (of `lazy_setup` when busted runs with `--lazy`).
---Also callable as `setup(fn)` or curried: `setup "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function setup(name, fn) end

---Alias of `strict_teardown` (of `lazy_teardown` when busted runs with `--lazy`).
---Also callable as `teardown(fn)` or curried: `teardown "name" (function() ... end)`.
---@param name string
---@param fn fun()
---@overload fun(fn: fun())
---@overload fun(name: string): fun(fn: fun())
function teardown(name, fn) end

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
match = nil
