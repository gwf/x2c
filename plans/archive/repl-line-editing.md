# REPL line editing

> Status: done - implemented September 21, 2026 by `a04cbb07`.
> Interactive line editing, history, terminal restoration, documentation,
> licensing, and native and APE installation coverage are complete.

## Result

Interactive `x2c repl` sessions gain inline editing, bounded in-memory
history, UTF-8-aware cursor movement, terminal-row wrapping, bracketed paste,
and Ctrl-C input cancellation. Piped input and compiler-session semantics stay
unchanged. Ctrl-C during evaluation keeps its process-termination behavior.

## Design

- A private `ReplInput` owner adapts Linenoise commit
  `a473823d74b93eab2ba83480df16ed37617493f2`. It returns distinct line, EOF,
  and cancelled results and restores terminal state before returning or
  transferring an error.
- The port keeps blocking editing, display, UTF-8 movement, 100-entry history,
  visual multiline wrapping, and bracketed paste. Completion, hints, masking,
  persistent history, key diagnostics, and the public asynchronous API stay
  out of scope.
- Completed commands and submissions enter history as whole entries, including
  rejected and failed submissions. Incomplete fragments and cancelled input do
  not. Enter retains the REPL's continuation-prompt model.
- The derived source retains the upstream BSD-2-Clause terms and provenance.
  Native installations, release archives, and source-bearing APE payloads
  carry the license.

## Validation and delivery

Extend the optional PTY checks for editing, history, Unicode, wrapping, paste,
input cancellation, EOF, terminal restoration, and evaluation SIGINT. Preserve
the direct API, native-parity, and piped-input checks. Verify a temporary native
installation and the APE build, then review the authored and generated diff and
run the final `agent-pr-check`. Delivery is directly to `dev`.

## Plan review

`isatty` already selects interactive input, and `ReplSession.submit` already
owns completeness and execution outcomes. The editor consumes those facts
without rechecking syntax or publication. It replaces only the interactive
prompt/read path and reuses the existing pending-source loop.

`ReplInputResult` is needed because a null `String` can mean an accepted empty
line and cannot also identify EOF and cancellation. `ReplInput` owns terminal
and history storage; no backend interface, cache, AST traversal, or second
session representation is added. No compiler validator, dedicated language
diagnostic, or negative compiler fixture is proposed.
