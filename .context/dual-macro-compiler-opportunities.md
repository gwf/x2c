# Dual macros: where the compiler itself would get simpler

Research spike, 2026-09-27, on `meta-integration` at 553429f. Read-only.
Companion to the "Macros as construction templates and structural Match
patterns" proposal. Four surveys (transform/regions, expressions/statements/
protocol, macros/stage/helper, emit/parse/corpus) plus root-session checks.

## The one-sentence finding

The compiler already writes both directions of the duality by hand:
`%(...)` templates construct canonical AST and `case %(...)` recognizes it,
through one `%(` parser (`src/literals.x:22-56`, dispatched from
`src/expressions.x:2745`, `src/statements.x:448,497`). What it lacks is a
way to write either side in *x2c source* instead of in canonical AST. That is
the gap the proposal fills, and it is the gap that keeps `expr TYPE`, `stmnt`,
`at`, `bind`, `ident`, `(params (param (void) (bind () ())))` in front of
every reader of `src/transform.x`, `src/protocol.x`, and every meta author
(`lib/system-macros.xmacro:78-93` matches `%(at ? (return ? ?))` just to ask
"is this a return").

## Two kinds of template live in the compiler

1. **Open templates.** Fixed code whose free names resolve at the insertion
   site, in the program being compiled. `_try_block` (`src/transform.x:2354`)
   is the clearest: callees are Strings (`_catch_call(%(int), "sigsetjmp",
   ...)`), types are spelled by name, and the shape is fixed. It is a textual
   template wearing AST clothing. Same for `_defer_block` (2288),
   `_catch_arms` (2331), `_callback_function` (139), `_build_func_adapter`
   (444), `_cell_declaration` (1149), generate.x forward-tag and init-guard
   idioms (141-165, 249-263, 358-427), protocol update/discard/reverse/
   completion helper synthesis (`src/protocol.x:1740-2000`).
2. **Closed templates.** Ordinary user macros: free names are rigid to the
   definition site (`macro-template-lexical-shadow`), the proposal's model.

The proposal's binding-domain bridge (helper-build IDs vs program IDs) is the
same distinction seen from the helper side. A compiler-internal template is
compiled into the compiler binary but must bind `x2c_exception_push` and
`ExceptionFrame` in the *target* unit. Today that is `_adapter_helper` ->
`compiler.sym.resolve_global` (`src/transform.x:318`) and raw String callees.
So the design needs one explicit knob: does a free name in this template
resolve at definition (closed) or at insertion (open)? `x2c.ident` already
expresses "resolve this name later"; an open template is a body whose every
free name is implicitly `x2c.ident`. That is a small rule, not new machinery,
and it lets the compiler's lowering templates be written as x2c source.

## Ranked opportunities

Ranked by hand-written AST removed, with the caveat that most of the line
count around these sites is type dispatch and loops that stay as x2c.

| # | Site | Now | With a source template |
|---|---|---|---|
| 1 | `try`/`catch`/`defer` lowering, `src/transform.x:2288-2417` (~150 lines) | frame push, setjmp branch, landing, cleanup spelled as nested `%(block (if (expr (int) (op ! ...)) ...))` with String callees | `macro Statement $try_region(Name $frame, Statement $body, Statement $landing, Statement $cleanup...) { x2c_exception_push(&$frame); if (!sigsetjmp($frame.env, 0)) $body else { x2c_exception_landed(&$frame); $landing } $cleanup... }`. Per-arm arrays and `MatchCaptureSite` composites stay in x2c code that feeds the holes. |
| 2 | `Func` value call, `src/expressions.x:1580-1750` | `_resolve_func_call` builds `declare Func; per-arg if (addressable) FuncArg_reference else FuncArg_value; Func_apply(...)`; `_func_call_arguments` (1699) re-matches the identical shape 45 lines later to recover `(func-arg value address source)` | one `macro Statement $func_arg(...)` and `$func_apply(...)` used both to build and, as `case $func_apply(?callee, *args)`, to take apart. The only construct/recognize pair of the same shape in the same file; the proposal's exact use case. |
| 3 | Wrapper-function synthesis: `_callback_function` (139), `_build_func_adapter` (444), protocol helpers (`src/protocol.x:1740-2000`) (~200 lines) | four hand-built `(function (static R) (bind B ((fnmod P))) (block (stmnt (return (call ...)))))` skeletons | `macro Unit $forward(Type $result, Name $name, Params $params, Expr $target, Expr $args...) { static $result $name($params) { return $target($args...); } }`. Needs a Params hole kind or a sequence of Decl. |
| 4 | Scope cells, `src/transform.x:1140-1187` | `declare`/`sizeof`/`cast`/`composite` AST | `$T *$cell = Scope_malloc(sizeof($T)); *$cell = $init;` |
| 5 | Lambda shape, constructed `src/literals.x:1080-1179`, matched in ~9 arms across expressions.x:1015, regions.x:507/656, transform.x:873-1650 | two shapes (`lambda P B` / `lambda P (captures C) B`) each matched separately everywhere | one `$lambda` macro value as the pattern; the two shapes become one macro with an optional sequence hole. Recognizer proliferation is the cost being paid today. |
| 6 | Meta authors: `lib/system-macros.xmacro:78-93` (`$switch`), any `meta` that inspects captured syntax | `%(at ? (break))`, `%(at ? (return ? ?))` | `case $stmt.break():` or better a source pattern literal; the `at` wrapper and return arity stop leaking into user code. |

Not helped: `regions.x` (a lattice over matches, constructs nothing);
`_checked_func_argument` (`src/transform.x:342-405`) and `_define_pattern_
binders` (`src/statements.x:246-330`), which branch on resolved type facts and
cross-arm unification; `func_signature`/`_type_literal` (326-341), which
serialize a `Type` value into the AST and have no source spelling.

## What the macro machinery itself sheds

Verified in `src/macros.x`: `_capture_pattern` (2868) and `_capture_row`
(3001) build the same four projections (source/value/expression/splice) at
definition time and invocation time, with `_forwarded_capture` (2957) reached
only from the second. The proposal's single hole-role table (`slot-roles`)
replaces both with one projector read from both directions (~150 lines).
`tpl-call` (4202), `macro-invoke` (`_sdk_template_call`, 3049), and the
helper's `("x2c.template" ...)` marker (`etc/meta-helper.x:129`, unwrapped by
`_helper_result` at 2362) are three spellings of "invocation not yet
expanded"; the proposal's `invocation` stage is one value for all three.
`x2c_ident` is duplicated verbatim (`src/macros.x:468`,
`etc/meta-helper.x:90`); that is two binaries, not two designs, and stays.
`List.replace` and per-expansion `_introduced_binding` stay: they are the
substitution and freshening engines the value would drive.

## Interpreter status (asked)

The Lisp evaluator is out of ordinary project builds (native helper) but
still inside the compiler binary: `Compiler.macro_lisp`
(`src/compiler.x:260,444,460,1611`), `_meta_apply` (`src/macros.x:2340`),
`_meta_stub`'s `groups_meta()` branch (2372), and 166 lines across nine
`src/` files. The REPL depends on it directly (`commands/repl/repl-lower.x`,
`repl-runtime.x`). "Toy in the REPL" is the direction, not yet the state.

## Recommended first cut

Do not start with the general Match retry integration. Start where the
compiler pays today and the semantics are simplest:

1. **Open compiler templates.** Add the "free names resolve at insertion"
   rule for macros defined inside the compiler (or a `macro Statement`
   modifier), and rewrite `_try_block`/`_defer_block`/`_catch_arms` as source
   templates. Construction only; no recognition needed. This proves the
   binding-domain knob on the compiler's own code before the helper bridge.
2. **One recognizer pair.** Make `$func_apply` a macro value and use it as
   the pattern in `func_call_parts`. Fixed shape, no interior sequence, no
   alpha renaming of locals needed beyond the `FuncArg` temporaries, which
   are exactly the introduced-declaration case the proposal handles.
3. **Merge the capture projectors** behind the hole-role table, then
   collapse `tpl-call`/`macro-invoke`/`x2c.template` into one invocation
   value. This is deletion inside `src/macros.x` and pays regardless.
4. Only then the lambda pattern (needs the optional `captures` sequence and
   contextual equality) and user-facing source patterns.

Bootstrap sequencing as the proposal says: the checked-in compiler must
parse the new forms before `src/` uses them; step 1 needs an intermediate
build.
