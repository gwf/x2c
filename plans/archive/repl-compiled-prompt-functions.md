# Compile prompt-defined functions

> Status: done
> Implemented 2026-10-15 in `d558503b7` and `0ac6242b`.
> Prompt functions compile once and share session-owned native variables.
> Top-level input remains interpreted; loaded adapters retain reload behavior.

## Result

Compile each complete prompt function definition before publishing it. Keep
top-level declarations, initializers, expressions, and statements interpreted.
No `meta` modifier or new command is required. A failed compilation publishes
nothing and leaves existing functions and variables usable.

Use this example to establish shared state and calls to earlier functions:

```x2c
int bias = 1;
int adjust(int n) { return n + bias; }
int twice(int n) { return adjust(adjust(n)); }
Func saved = twice;
bias = 10;
twice(2);  // 22
saved(2);  // 22
```

For reload, load a temporary copy of `packages/autodiff/src/autodiff-macros.x`
and define `String label(String s) { return ad_dot(s); }`. After editing
`ad_dot` and loading that file again, the already compiled `label` must use
the replacement. Repeat with an integer function saved in a `Func` variable.

## Implementation

1. **Share prompt variable storage.** Give each published variable one
   separately allocated, session-owned object with its declared native layout.
   Keep the existing binding-ID table as the sole index. Interpreted reads and
   writes use the existing layout and `lisp_peek`/`lisp_poke` operations;
   compiled functions capture the object's address. Assignment changes the
   object, never its address. Records and mutable handles keep their identity.
   This also removes the scalar-global address limitation: `&bias` in either
   path designates the same object. Preserve initializer rollback and effects
   on previously published variables when a submission fails.

2. **Compile one definition and instantiate its bindings.** Adapt the existing
   session native emitter to stage only the new typed function, its required
   type declarations, and a small factory. Reuse the normal transform, native
   toolchain, cache, loader, and signature adapters. The factory receives
   variable addresses and callable handles, then creates a session-owned
   `Func.new_context`. Shared module code must contain no mutable session
   bindings. Preserve the original function signature and typed return path;
   ordinary lambda lowering's `Var` return is not a substitute. Rewrite bound
   references with canonical AST operations, without replaying source or
   initializers. Publish only after compilation and binding succeed.

3. **Call existing functions through their handles.** Capture the existing
   signature-bearing `Func` for each referenced session function or native
   binding. Use ordinary compiler call adaptation, including argument
   evaluation order, references, and result conversion. Self-recursion calls
   the compiled body directly with its context. Later definitions do not
   rebuild earlier functions. Function values use the published session
   handle rather than creating an unbound copy of the native entry point.

4. **Keep loaded-file indirection.** A compiled caller captures the current
   loaded function's stable adapter, not its helper or executable address.
   That adapter already reads `ReplLoadedFile.helper` on every call. Successful
   reload therefore updates compiled callers and saved values automatically;
   rejected reload leaves them on the previous helper. Preserve signature and
   public-type checks, native state reset, independent loaded files, and all
   existing data-crossing limits. Do not compile loaded-file bodies into prompt
   modules or add a second reload mechanism.

## Boundaries and inspection

Keep current prompt redefinition, forward-declaration, and persistent-storage
restrictions (`static`, `extern`, and `threaded`). Native functions follow the
existing native-callback interruption rule; they do not acquire the Lisp call
budget or loop polling. Top-level interpreted input retains both protections.

Retain typed AST inspection. `:info` identifies native execution and prompt
origin; `:lowered` reports that the function is compiled and has no Lisp body.
Inspection and completion neither compile code nor disturb incomplete input.
Reuse the loader's current code lifetime: modules remain loaded, while each
session owns its captured bindings and function instances. No code-unloading
or prompt-function replacement feature is included.

## Verification and delivery

Extend existing REPL checks for bidirectional scalar/record mutation, mutable
handle identity, references, earlier calls, self-recursion, saved Func values,
and two sessions sharing cached code without sharing variables. Verify failed
definitions leave prior state usable. Exercise successful and rejected reloads
through compiled callers, including preserved counters after rejection and
reset counters after replacement. Run the autodiff walkthrough above.

Update the REPL guide. Compare definition cost and warm execution using the
existing xorshift workload, separately from correctness checks. Finish by
reviewing and correcting the authored diff, running the existing focused
checks and publication gate, and delivering under the repository workflow.

## Plan review

The parser establishes bindings and types; native layouts and Func adapters
establish storage and call representation. Trust those producers. Reuse
`ReplLoadedFile`, its adapter and replacement checks, and the existing native
staging isolation. Replace boxed global storage rather than maintaining a
second copy. The new factory and per-function context are needed to associate
shared code with one session; binding-aware AST adaptation supplies ordinary
native references and calls. No second compiler, dependency builder, general
validator, or recurring gate is proposed. Failure tests protect atomic
publication and the existing reload contract; existing adapter checks protect
native crossings. Implement these operations with normal x2c records, Funcs,
Match patterns, and compiler APIs.

## Implementation evidence

`sh commands/repl/tests/run.sh` passes the direct API, command, source-load,
reload, and real autodiff checks. Coverage includes shared scalar and record
addresses, mutable collections, references, saved functions, recursion,
nested lambdas, callable expressions, and independent sessions sharing code.
Compiled callers follow successful reloads and retain the old helper after
rejected replacements. Loaded aliases and anonymous public types work in
native prompt bodies, including `sizeof` and `offsetof`.

The implementation reuses native staging and Func adapters. Loaded type
declarations come from canonical compiler symbols. Review also corrected
transaction-owned bindings in the protocol member cache, anonymous typedef
forward emission, native module constant lifetime, and captured record
storage. Native prompt functions retain the existing native-callback
interruption boundary. Performance measurements remain separate from the
correctness publication gate.
