# REPL fit, status, and runtime surface

> Status: done 2026-09-25. Deliveries 1-8 are on `dev`; pure module
> bindings landed in `39578b76` and the REPL later moved to `commands/repl`.
> Deliveries 1-7 were implemented and validated on 2026-09-21. Delivery 8,
> the pure-module step, was implemented on 2026-09-24 through `meta`
> prototypes in json.x, diff.x and path.x that `lib/lisp.x` includes.
> Gary accepted that Json, Diff and Path become visible to x2c code that
> includes `x2c.x`.

## Delivered

Deliveries 1-7 shipped on `dev` on 2026-09-21. The REPL and
meta-functions guides own their behavior.

1. Terminal fit: one command table drives dispatch, headed help, and
   contextual, grouped completion.
2. Live statistics: `:stats` and `--stats` report labelled session,
   evaluation, Scope, and Pool rows with since-open deltas.
3. Output: REPL-only `print(String)` and `println(String)`; a `void` final
   expression prints no result.
4. Grammar-aware completion from parser-owned context.
5. Verbose statistics: `:stats verbose` and `--verbose-stats`.
6. Exact live Scope bytes, with current and peak counts.
7. `String.format(String fmt, List values)` as a fixed-signature runtime
   and meta operation.
8. `Json.parse`, `Diff.lines`/`unified` and the Path text operations in
   `meta` code and the REPL, with the `meta-native-pure-modules` fixture.

## Standard-library and host candidates

Rechecked on 2026-09-24 against `origin/dev` 29326dbd with source and REPL
and `meta` probes. Effect on hand-authored `.x`: about 20 lines for the
recommended next step, with no new mechanism. Scalar math needs none.

### Current state

| Group | REPL | `meta` function | What is missing |
| --- | --- | --- | --- |
| Scalar math | Callable: `sin(1.0);`, `sqrt(2.0);`, `lround(2.5);` | Callable, including output pointers | Nothing. `lib/cmath.x` marks all of C99 `<math.h>` `meta`. |
| `Json.parse`, `Diff.lines`/`unified`, Path text | Not visible: `type () has no method parse` | `no binding for Json_parse` | A native target and, for the REPL, the declarations. |
| `Regex.escape` | Not visible | No binding | Not linked into the compiler (`Regex` is a registered class). |
| Read-only host queries | Not visible | No binding | Target, declarations, and a dependency rule. |
| Mutating host operations | Not visible | No binding | A capability policy. |
| Native resources | Not visible | `File.open` has no binding | A resource representation. |

The compiler binary already links `Json_parse`, `Diff_*`, `Path_*`, and
`Env_get`. Linking is not enough. A bodyless prototype binds only a name in
`lisp_native_targets`, which `lib/lisp.x` generates from the `meta`
prototypes visible to its own translation (`x2c.x` and `autodiff.x`).
`json.x`, `diff.x`, `path.x`, and `process.x` are outside that set, so a
user prototype such as `meta Var Json.parse(String source);` still reports
`no binding`. In the REPL, a method prototype cannot be written at all,
because `Json`, `Diff`, `Path`, and `Env` are not declared in the session.

### Safety constraints

- **`errno` and floating point:** moot for math. Meta code cannot read
  `errno` or the floating-point environment, and the compiler runs in the
  default rounding mode that compiled code also uses. No per-function
  allowlist is needed.
- **Filesystem dependencies:** still applies. Only `x2c_embed_text` records
  a translation dependency. Exposing `Path.read_text`, `exists`, `list_dir`,
  `glob`, or `Env.get` to compiler `meta` would make builds depend on
  untracked host state. REPL-only exposure has no build to invalidate.
- **Mutation capability:** still applies. Nothing exists.
- **Opaque resources:** partly handled. Native-module handles now follow the
  region and ownership rules in the meta-functions guide, but runtime
  resource classes such as `File`, `Regex`, and `Job` still have no binding
  or cleanup contract in the evaluator.

### Module loading

The decision is narrower, not moot. Bodyless prototypes solve binding for
functions already in the target table. The optional modules still need
their declarations in the REPL session and their functions in a target
table.

### Recommendation

1. Mark the pure value operations `meta` beside their definitions (D1
   style): `Json.parse`, `Diff.lines`, `Diff.unified`, and `Path.join`,
   `dirname`, `basename`, `extension`, `stem`. About 8 lines.
2. Give the compiler, not `lib/lisp.x`, the target rows for these optional
   modules, so ordinary programs that link the Lisp runtime do not also link
   Json, Diff, and Path. About 5 lines.
3. Add `json.x` and `diff.x` (which bring `path.x`) to the REPL session's
   fixed declarations in `Frontend.open_session`. About 3 lines.
4. Add one native/meta differential fixture for these operations.

Defer host queries, mutation, `Regex`, and resources.

### Decisions

Gary accepted all four recommendations below on 2026-09-24.

- **Compiler `meta` or REPL-only for the pure operations?** Recommend both.
  They are deterministic, and one `meta` mark serves both.
- **Where the optional target rows live?** Revised the same day: bodyless
  `meta` prototypes in `lib/json.x`, `lib/diff.x`, and `lib/path.x`,
  included from `lib/lisp.x`, as `lib/cmath.x`, autodiff, and process
  already are. The compiler's own target list holds only compiler
  operations, and a second kind of entry there would be new machinery.
  Ordinary programs link no `lisp.o`, so only the compiler and programs
  that embed the runtime Lisp carry Json and Diff. Path waits for the
  class-unit init-guard fix in the adoption campaign's delivery 4.
  This inclusion is a stand-in: if the compiler gains dynamic module
  loading for meta code, these includes are no longer needed.
- **Read-only host queries?** Recommend REPL-only exposure later, after the
  pure group. Compiler `meta` exposure should wait for a dependency rule.
- **`Regex.escape`?** Recommend leaving it out. It would require linking
  `Regex` into the compiler and spending a class row.

### Direction

The REPL is now its own program. It moved out of the compiler into
`commands/repl` in `3eff555c` and runs through `x2c repl`; see
[external commands](external-commands.md). The Json, Diff, and Path
bindings above landed before that move and are served through the
compiler objects the command links. Later REPL work belongs in
`commands/repl`.

## Validation

The recommended step needs one native/meta differential fixture and an
optional REPL check that `Json.parse`, `Diff.unified`, and `Path.basename`
evaluate. It adds no recurring gate. Update the meta-functions guide's
native-function list and the REPL guide.
