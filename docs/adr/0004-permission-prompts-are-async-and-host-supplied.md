---
status: accepted
---

# Permission prompts go through an async, host-supplied Prompter

deno_permissions' `PermissionPrompter::prompt` is synchronous, `Send + Sync`, and
installed process-wide with `set_prompter`. A prompt that blocks the Lua thread
freezes a TUI host, which then cannot draw the question it is asking. So luastd
installs deno's `DeniedPrompter`, and on every check first asks the
`PermissionsContainer` whether the descriptor is granted, denied, or still
`prompt`. Only when it is `prompt` does it await the host's async `Prompter`
trait, then records the answer back in the container.

## Consequences

- Only the coroutine that asked suspends; the host keeps drawing and other
  coroutines keep running.
- The `PermissionsContainer` stays the single source of truth for what has been
  granted; the `Prompter` never caches answers itself.
- A host without UI passes no `Prompter`, and `prompt` behaves as denied.
- luastd owns the global `set_prompter` slot; a host must not install its own
  deno prompter.

## Note: a staged DeniedPrompter

deno's `DeniedPrompter` answers every prompt with Deny, so `request_env` could
never record a grant. luastd installs `StagedPrompter` instead: it behaves like
`DeniedPrompter` unless luastd has staged the host's answer for the current
`request_*` call on this thread, and it never touches the TTY. A probe on a
`deep_clone` of the container tells luastd whether the container would prompt
at all (`--no-prompt` style containers deny without asking the host).
