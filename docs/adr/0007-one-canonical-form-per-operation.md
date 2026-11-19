---
status: accepted
---

# One canonical form per operation; other forms must compose differently

Several luastd operations can be spelled more than one way: `d:await()` and
`async.await(d)`, `scope:launch(fn)` and `async.launch(fn)`, `ch:iter()` and
`ch:each(fn)`. Some of these are exact aliases, some differ in which scope they
bind to or how they end, and some only share a name. Without a record, readers
assume aliases are interchangeable and authors add more of them.

Each operation therefore has one canonical form, which the docs and examples
use. Another form exists only when it composes differently from the canonical
one. The inventory below lists every group of equivalent or near-equivalent
forms in the public Lua API as of this ADR, checked against the stubs, the
implementation (`async.lua`, `scheduler.rs`, `env.rs`) and a runtime probe,
together with the differences that make each form worth keeping.

## Rule

A non-canonical form is acceptable only when it does one of these:

- **Passes as a value.** A prefix function for a method, such as
  `async.await(d)` for `d:await()`, so it can be handed to `map`, `pcall` or a
  callback.
- **Binds differently.** An explicit-receiver form next to a current-context
  form, such as `scope:launch` next to `async.launch`.
- **Reads its blocking or failure mode in its name.** `*_sync` for a variant
  that never waits and `try_*` for one that returns `ok, value | err` (see the
  `AGENTS.md` constraints).
- **Trades setup for reuse.** A one-shot helper next to a reusable object,
  such as `formatx.format` next to `formatx.new(..):render`.
- **Is operator sugar for a method.** A metamethod such as `p / "x"` or `a < b`
  that mirrors a method or constructor.

Pure synonyms, two names for the same call with the same composition, are not
added. Stubs mark the canonical form and cross-link: the alternative's doc
starts by naming the form it stands for ("Prefix form of `job:join()`"), the
canonical doc mentions the alternative in one line, and any semantic difference
is stated on both. Two functions that share a name but not a meaning say so
explicitly ("not the same as ...").

## Inventory

| Group | Forms | Same behavior? | Canonical |
| --- | --- | --- | --- |
| Await a value | `d:await()`, `async.await(d)` | Yes | `d:await()` |
| Wait for a job | `job:join()`, `async.join(job)` | Yes | `job:join()` |
| Launch a child | `scope:launch(fn)`, `async.launch(fn)`, `async.current():launch(fn)` | Differ in parent scope | `scope:launch` with a scope at hand, else `async.launch` |
| Start a value-producing child | `scope:async(fn)`, `async.async(fn)` | Differ in parent scope | As for launch |
| Run work and wait | `async.scope(fn)`, `async.async(fn):await()` | No | `async.scope` |
| Await several | `async.await_all(a, b)`, awaiting each | No: first values only | `await_all` for single values |
| Consume a channel | `ch:each(fn)`, `for v in ch:iter()`, `ch:receive()` loop | No: early exit | `ch:each` |
| Producer channel | `async.produce(body)`, `channel` + `launch` + `close` | No: cancel link | `async.produce` |
| Debounce | `ch:debounce(ms)`, `async.debounce(ms, fn)` | No: different things | Each in its own domain |
| Cleanup | `async.finally(body, cleanup)`, `scope:on_cancel(fn)` | No: different triggers | `async.finally` |
| Time limit | `async.with_timeout(ms, fn)`, `delay` + `cancel` | No: error kind | `async.with_timeout` |
| Still running? | `async.is_active()`, `async.current():is_active()` | No: during cleanup | `async.is_active()` |
| Environment | `env.get(n)`, `env.get_sync(n)` (each op) | No: waiting | `env.get` |
| Variable set? | `env.has(n)`, `env.get(n) ~= nil` | Yes | `env.has` |
| Inspect an error | `err.kind` and fields, `tostring(err)` | No: text only | Fields |
| Format | `formatx.format(t, ...)`, `formatx.new(t):render(...)` | Yes (one parse vs reuse) | `format` one-shot, `new` to reuse |
| Format, lenient | `formatx.formatl(t, ...)`, `formatx.new(t):render_lenient(...)` | Yes | As above |
| Join paths | `p / "x"`, `p:join("x", ...)`, `path.new(p, "x")`, `path.join(p, "x")` | `path.join` returns a string | `path.new` to build, `/` or `join` to extend |
| Zero version | `semver.new()`, `semver.default()` | Yes | `semver.new()` |
| Compare versions | `a < b`, `a == b`, `a:cmp(b)` | Yes (boolean vs three-way) | Operators; `cmp` for three-way |
| Validate a version | `semver.valid(s)`, `pcall(semver.parse, s)` | Yes (no value vs value) | `valid` to check, `parse` to use |
| Reach a module | `require("luastd.path")` | Only form | `require("luastd.<name>")` |

`require("luastd")` holds only `version`; there is no `require("luastd").path`,
in line with "`require`, not globals".

## Details

### Method and prefix forms

```lua
local v = d:await()          -- canonical
local v = async.await(d)     -- same call
local values = map(deferreds, async.await)
```

`async.await` and `async.join` call the same implementation as the methods, so
results, errors and `Deferred<T...>` typing are identical. Use the prefix form
where a function value is needed.

### Where a child is launched

```lua
async.scope(function (scope)
    scope:launch(worker)     -- child of `scope`
    async.launch(worker)     -- child of the current scope: also `scope` here
end)
```

`async.launch(fn)` is `async.current():launch(fn)`: it attaches to the scope of
the calling coroutine. `scope:launch(fn)` attaches to `scope` whichever
coroutine calls it. They agree directly inside a scope body and differ inside a
nested job: there `async.launch` makes a child of that job, which is cancelled
with it, while `scope:launch` makes a sibling that outlives it. Use the scope
parameter when one is at hand, because it says which scope owns the child; use
`async.launch` at the top level, where it reaches the root scope, and in
library code that should attach to its caller's scope. `scope:async` and
`async.async` follow the same rule.

### Running work and waiting for it

`async.scope(fn)` is not a launch: it runs `fn` in the caller, waits for its
children, returns `fn`'s values and raises a failure right there.
`async.async(fn):await()` gives the same values, but the job is a child of the
current scope, so in a non-supervisor scope its failure also cancels that scope
and its other children. Use `async.scope` to run and wait, and `async`/`launch`
only for concurrency.

### Awaiting several deferreds

```lua
local a, b = async.await_all(da, db)   -- first value of each
local a1, a2 = da:await()              -- every value
```

`await_all` keeps one result per argument by returning only the first value
of each body, and it is typed `any ...`, so the `Deferred<T...>` types are lost.
Both raise the first failure in argument order. Use `await_all` for
single-valued deferreds and `await` in a loop for several values or precise
types.

### Consuming a channel

```lua
ch:each(function (line) print(line) end)   -- cancels the channel however it ends
for line in ch:iter() do print(line) end    -- an early break leaves the producer waiting
```

`each` cancels the channel when it ends, including `return false`, an error or
cancellation, so a producer stops. Leaving an `iter` loop early does not: call
`ch:cancel()` after the loop. `receive` raises `ChannelClosed` at the end of the
stream where `iter` returns `nil`. Use `each`; use `iter` when the loop reads
better and always runs to the end.

### Producer channels

`async.produce(body)` is a `channel`, a `launch` and a `finally` that closes the
channel, plus one thing the manual version lacks: `ch:cancel()` also cancels
the producer job. Use `produce`.

### Debounce

`ch:debounce(ms)` turns a channel into a channel that emits a value after `ms`
of quiet and flushes the last value when the source closes.
`async.debounce(ms, fn)` wraps a function so only the last call in a burst runs,
cancels a pending call that has not started, returns a `Job` per call and
flushes nothing. They share a name, not a meaning.

### Cleanup

```lua
async.finally(function () use(res) end, function () res:close() end)
scope:on_cancel(function () res:close() end)
```

`finally` runs `cleanup` right after `body`, however it ended. `on_cancel`
runs only when the scope ends without completing normally (cancelled, timed out
or failed), after its children settle. Both run without being cancellable. Use
`finally` for cleanup; use `on_cancel` for work that only matters on abnormal
exit, such as rolling back.

### Time limits

`async.with_timeout(ms, fn)` raises `Timeout`, a catchable `luastd.Error`.
Cancelling a scope from a timer job instead raises the cancellation error,
which `pcall` rethrows (ADR 0005), so the rest of the enclosing body is skipped,
and the timer job has to be cancelled too. Use `with_timeout`.

### Is the coroutine still running?

`async.is_active()` asks whether the current coroutine can still be cancelled
at its next suspension. Inside a non-cancellable section, a `finally` cleanup
or an `on_cancel` handler, it returns `true` even though the scope was
cancelled, while `async.current():is_active()` returns `false`. Use
`async.is_active()` in loops that poll for cancellation, and `scope:is_active()`
to ask about a particular scope.

### Effect variants

`env.get` and the other plain functions are `---@async` and wait for the
host's prompt when a permission is undecided. `env.get_sync` and the other
`*_sync` functions never wait: an undecided permission raises
`PermissionDenied`. Use the async form (async is the blessed path) and `*_sync`
only where waiting is impossible, such as startup configuration. `env.has(n)`
and `env.get(n) ~= nil` check the same permission and agree; `has` states the
intent.

### Errors

Branch on `err.kind` and read context fields (`err.permission`, `err.path`).
`tostring(err)` gives `"<kind>: <message>"` for messages and logs, not for
matching. Use `async.is_cancellation(err)` for the cancellation error, which is
not a `luastd.Error`.

### Pure modules

- `formatx.format` and `formatl` parse on every call; `formatx.new` parses once
  for repeated `render` and `render_lenient` calls.
- `p / "x"`, `p:join("x")` and `path.new(p, "x")` give the same `Path`;
  `p:join` and `path.new` take several arguments and skip `nil`.
  `path.join(...)` returns a string and needs at least one argument, while
  `path.new()` is the empty path.
- `semver.new()` and `semver.default()` both return `0.0.0`.
- `a < b`, `a == b` and `a <= b` answer what `a:cmp(b)` does as `-1`, `0` or
  `1`; `table.sort` works on versions directly.
- `semver.valid(s)` checks without raising; `semver.parse(s)` raises and
  returns the `Version`.

## Considered Options

- **Exactly one form per operation:** removes every ambiguity, but drops the
  prefix forms that make `await` and `join` usable as values and the explicit
  `scope:launch`.
- **Free aliasing:** cheap to add, but readers cannot tell an alias from a
  near-twin with different cancellation behavior, which is where the bugs are.

## Consequences

- Stubs gain cross-links and canonical markers as they are touched; new API is
  reviewed against the rule.
- Near-twins with different semantics stay, documented on both sides.

## Follow-ups

Inconsistencies found while building the inventory. None changes the API here.

1. The `luastd.async` module doc and ADR 0005 present `async.finally` and
   `scope:on_cancel` as interchangeable cleanup. They have different triggers;
   the module doc should say which to use.
2. The runtime surface is wider than the stubs: Job, Deferred and Scope share
   one metatable, so a `launch` job also has `await` (returning the body's
   values), and a scope parameter or `async.current()` has `join` and `await`.
   Joining a scope from inside itself is untested. Either hide these or
   document them.
3. `async.is_active()` and `Scope:is_active()` differ inside non-cancellable
   sections, and neither doc says so. `async.is_active()` is described as
   "the current coroutine's scope has not been cancelled", which is not what
   it reports during cleanup.
4. `Channel:debounce` and `async.debounce` share a name but not semantics, and
   neither links to the other.
5. Missing cross-links: `async.launch` and `Scope:launch`, `async.async` and
   `Scope:async`, `Channel:each` to `Channel:iter` (only the reverse exists),
   `formatx.format` and `formatx.new`, `path.new` and `path.join` to
   `Path:join` and `/`, `semver.new()` and `semver.default()`, `Version:cmp`
   and the comparison operators.
6. `async.await_all` is typed `any ...` and so drops `Deferred<T...>` types.
7. `async.join` and `async.await` do not validate their argument the way
   `launch` and `scope` do, so a non-job raises an index error, not
   `InvalidArgument`.
8. `semver.default()` is a pure synonym of `semver.new()` under this rule:
   deprecate it, or keep it as the mirror of Rust's `Default` and say so.
