---
status: accepted
---

# Each Lua state lives on one thread; mlua's `send` feature is not used

mlua's `Lua` is not `Send`, so futures that hold it cannot go to `tokio::spawn`. We
run every Lua state on a single thread (a tokio `LocalSet` or current-thread
runtime) and do blocking or parallel work off that thread, handing results back,
the same model Neovim and WezTerm use. We rejected mlua's `send` feature because
it forces every userdata and closure to be `Send`, and adds locking to every call,
for parallelism a scripting runtime does not need.

## Consequences

- The host must drive the runtime from a local executor; `tokio::spawn` of a Lua
  future does not compile.
- Userdata and closures use plain `Rc`/`RefCell`. A host that turns on mlua's
  `send` feature (directly or through feature unification) is unsupported.
