> Status: done
> All phases and the follow-up examples shipped through a50dfe7; public
> navigation shipped in 2f74dec. Archived 2026-09-10 with the follow-up
> repairs for forward loop clauses and inactive runtime-tape adjoints.

# Automatic differentiation for x2c

## Intended result and difficulty

Give an x2c programmer three ways to obtain derivatives of ordinary
`double` code, all built with the shipped macro system and no compiler
change to the language:

1. a dual-number family (`Dual`, `Dual2`, ...) whose values use ordinary
   operators, for forward mode and statically nested higher-order
   derivatives;
2. a `$ad.forward()` decorator that emits a tangent function `f_dot` next
   to a decorated function `f`, producing plain scalar C;
3. a `$ad.reverse()` decorator that emits a gradient function `f_grad`
   for functions built from declarations, assignments, `if`, counted
   loops, and calls to other decorated functions or known primitives;

plus a small runtime tape for code the transformations do not cover.

This follows Pearlmutter and Siskind's program where x2c can host it:
nested forward mode with distinct perturbation types, reverse mode as a
source transformation, and backpropagator closures. It deliberately omits
first-class derivative operators over runtime closures and the flow
analysis that makes them fast (VLAD/Stalingrad). x2c lambdas are opaque at
runtime and a macro sees only captured syntax; that part would be a
compiler project with unclear payoff for C-shaped numeric code.

Budget roughly **4-7 engineer-weeks** in total: forward mode is a week,
reverse mode with loops and calls is two to four weeks, the rest is
documentation, examples, and the diagnostic fix. This is judgment, not a
measurement.

## Evidence from the spike

Probes in `.context/ad-spike/probes/` (workspace brisbane, not tracked).
All ran with correct results at the point (1, 2); expected values were
computed by hand.

| Probe | What it showed |
| --- | --- |
| `a_dual.x` | `Dual` adopting `protocol Var` operator rows; one `Type`-hole Unit macro generates `Dual` and `Dual2 = Dual(Dual)`; df/dx = 19.956408 and cube''(2) = 12 |
| `a2_mixed.x` | converters apply to initializers and `*=`; `x * 2.0` with a `Dual` `x` is a C error |
| `b_fwd.x` | Unit decorator plus ~130 lines of Lisp emit `f_dot(x, x_dot, y, y_dot)` over declarations, assignment, `if`, `return`, `sin`/`cos`/`exp` |
| `c_rev.x` | same machinery emits `g_grad(x, y, double *x_grad, double *y_grad)` for straight-line code |
| `d_closure.x` | `Func` backpropagator closures plus a tape of nodes |
| `bench.x` | 20M calls at -O2: transformed 0.086s, dual struct 0.087s, primal 0.058s |

The typed AST is what makes the transformations short: every node is
`(expr (double) ...)`, so the rewrite selects differentiable arithmetic by
type and leaves `int` control flow alone. Constructed ASTs use spelled
names (`(bind ("t_dot") ())`, `(ident ("x"))`, `(expr () ...)`) and the
compiler rebinds and retypes them; no binding IDs are forged.

## Design decisions

### Placement and naming

- `lib/autodiff.xlisp` holds the transformation (derivative rules,
  statement rewriting, function construction). `lib/autodiff.xmacro`
  imports it and defines the macros. `lib/autodiff.x` holds the runtime
  tape. The macro namespace is `$ad.*`.
- No new compiler surface, no new protocol, no new Var tag beyond the
  dual family's own tags.
- Open decision for Gary: today `import` resolves only relative to the
  importing file, which is why every `lib/*.x` import of
  `error-macros.xmacro` works and why a user program outside `lib/`
  cannot name `autodiff.xmacro` without a path. Either (a) document an
  explicit relative or absolute path in the book, or (b) let `import`
  fall back to the toolchain `lib/` directory when the relative path is
  absent. (b) is a small change in `src/macros.x` and a public semantics
  change; (a) needs nothing. The plan assumes (a) until told otherwise.

### Dual-number family

```x2c
typedef struct Dual { double v; double d; } Dual;
typedef struct Dual2 { Dual v; Dual d; } Dual2;
$ad.dual(Dual, dual, <dual>, double, sin, cos, exp, log, sqrt);
$ad.dual(Dual2, dual2, <dual2>, Dual,
         Dual.sin, Dual.cos, Dual.exp, Dual.log, Dual.sqrt);
```

- Holes: `Type $D`, `Name $d` (converter spelling), `Literal $tag`,
  `Type $S`, then one `Expr` per scalar primitive. The primitive list is
  fixed by the macro; the caller passes the scalar spelling for each
  because methods cannot be declared on `double` and a `Type` hole cannot
  be an expression receiver.
- Generated members: `add sub mul div neg compare`, one method per
  primitive, `$D.var`/`Var.$d` converters, `$S.$d` converter so
  `Dual two = 2.0;` and `x *= 2.0` work, `protocol Var($D);`.
- Typedefs stay with the caller and precede the first invocation (the
  header orders macro-generated prototypes before a later typedef).
- Nesting is by type. Each depth is a distinct C type, so an inner
  derivative cannot capture an outer perturbation. Dynamic tagging is not
  provided; document that a derivative of a function that itself takes a
  derivative needs the next type in the family.
- Mixed operands (`x * 2.0`) remain a C error because converters do not
  apply to binary-operator operands. The book shows `Dual two = 2.0;` and
  the transformation route, which has no such limitation.

### Forward transformation `$ad.forward()`

Target: a file-scope function whose parameters and result are `double`
(other parameter types pass through unchanged and are treated as
constants). Emits the original unchanged plus `NAME_dot` with each
`double` parameter `p` followed by `p_dot`.

Supported statement forms, all on the typed AST:

| Source | Emitted |
| --- | --- |
| `double v = e;` | `double v = e; double v_dot = D[e];` |
| `v = e;` `v op= e;` | tangent assignment first, then the original |
| `if`, `else`, `while`, `for`, `do`, `break`, `continue`, `return` | control kept; `double` returns become tangent returns |
| nested blocks | rewritten recursively |
| `int` declarations and arithmetic | copied |

Expression rules: literals, identifiers, `+ - * /`, unary `-`, parentheses,
casts between `double` and integer types, calls to primitives from a
table (`sin cos tan exp log sqrt pow fabs tanh atan`), calls to other
functions decorated in the same unit (`g(a, b)` becomes
`g_dot(a, a_dot, b, b_dot)` by spelling, which is how the decorated
sibling is named), and `x2c.diagnostic.fail` with the offending source
text for anything else. Constructed binary nodes are wrapped in
`(parens ...)`; the emitter adds no precedence parentheses.

The result is plain scalar C. The spike shows clang optimizes it to the
same speed as inlined dual-number code, so the transformation exists for
composability and readability of generated code, not speed.

### Reverse transformation `$ad.reverse()`

Emits `NAME_grad(params..., double *p_grad...)` returning the primal value
and writing each parameter's adjoint through its pointer.

- Straight-line code is the spike: forward sweep keeps the declarations,
  then one `v_bar += w_bar * dw/dv` per use in reverse statement order,
  where `dw/dv` reuses the forward rule with a unit seed.
- Reassignment: each assignment to `v` after its declaration becomes a
  fresh SSA temporary in the forward sweep so adjoints attach to the right
  value. This is a rename pass over the block, done before the sweep.
- `if`: the branch condition is evaluated in the forward sweep into an
  `int` temporary; the adjoint sweep uses the same temporary to run the
  reverse of the taken branch. Conditions are `int` and never
  differentiated.
- Counted loops (`for (int i = a; i < b; i++)` and `while` with a body
  that assigns only through the rename pass): the forward sweep records
  each loop-carried `double` per iteration into a fixed-capacity array
  sized from a `$ad.reverse(steps)` argument, then the adjoint sweep runs
  the loop backwards. This is the classic tape-per-loop transformation
  without checkpointing; the argument makes the storage explicit and
  static. A loop that exceeds it is a runtime `Error`.
- Calls to decorated siblings: `g(a, b)` in the forward sweep, then
  `g_grad(a, b, &a_bar_tmp, &b_bar_tmp)` in the adjoint sweep with the
  temporaries scaled by the call's adjoint. The primal is recomputed;
  accept the redundant evaluation.
- Anything else fails with a diagnostic naming the statement.

Divide-and-conquer checkpointing is out of scope; it is worth a separate
plan only if a real program hits the loop-storage limit.

### Runtime tape `lib/autodiff.x`

The spike's `Node` (`value`, `bar`, `back`) with `add sub mul div neg`,
the primitive table, and `protocol Var(Node)`; `Node.new` appends to a
`Scope`-owned tape and `AdTape.backward(root)` walks it in reverse. It
covers dynamic shapes (data-dependent loops, callbacks through `Func`)
that the transformation rejects. It boxes through `Var` and is the slow
path; the book says so.

## Implementation phases

Each phase is one PR to `main` and ends with the source review that
`plans/README.md` requires and `tools/gate-state.py ensure agent-pr-check`.

### Phase 0: Lisp failure detail in macro diagnostics

`src/macros.x` `_report_lisp_failure` appends `error: DETAIL` only when
`Error.since(mark)` is non-empty, and in the spike it was always empty
even though the same evaluator run in the shell printed
`(unbound (name caddr))`. Find where the evaluator's failure record goes
in the compiler session and route it into that note. Also decide whether
the compiler session should load `etc/lisp-extras.xlisp` as the shell
does; today `caddr` and friends are unbound inside macros. The
recommendation is to load it so both sessions match; the alternative is
one sentence in the book listing what the compiler session omits.

Validation: a compiler fixture with a deliberate unbound name whose
expected diagnostic includes the name.

### Phase 1: dual family

`$ad.dual` in `lib/autodiff.xmacro`, the primitive list, and a book
section under Compile-time macros or a new library module page. Unit test
`unittest/test-autodiff.x` covering each operator against finite
differences and `Dual2` second derivatives.

### Phase 2: forward transformation

`lib/autodiff.xlisp` with the expression rules, statement rewriting, the
primitive table, sibling calls, and diagnostics. Compiler fixture with the
transformed C as the checked expectation, plus unit tests comparing
`f_dot` to the dual family on the same functions.

### Phase 3: reverse transformation

Straight-line, then the rename pass, then `if`, then counted loops with
explicit storage, then sibling calls. Each step adds a fixture and a
gradient-check unit test against forward mode.

### Phase 4: runtime tape

`lib/autodiff.x`, registered in `lib/x2c.x` through the documented
regeneration target, with tests for data-dependent loops.

### Phase 5: examples and book

`examples/magic/autodiff.x` in the manifest showing the three routes on
one function; a guide page describing when to use which; the module page.

## Validation

- Per phase: `make x2c` plus the phase's own fixtures and suite, as
  `agents/quick-start.md` describes.
- Numerical: every generated derivative is checked against a central
  finite difference in the unit suite; forward and reverse are checked
  against each other.
- Publication: `tools/gate-state.py ensure agent-pr-check` per PR.
- No benchmark gate. The spike's timing is recorded above; a regression
  would show as generated-C text changes in the fixture.

## Implementation notes (2026-09-09)

- `import` already resolves a bare file name against `${root}/lib/` when
  the relative path is absent (`_canonical_path` in `src/macros.x`), so
  `$(import "autodiff.xmacro")` works from any unit and no compiler change
  was needed.
- Phase 0 landed as `afd5785`: the macro diagnostic now appends
  `error: (unbound (name caddr))` style detail from the caught `Error`.
  The compiler session still does not load `etc/lisp-extras.xlisp`; the
  book already lists that file as optional, and the transformation uses
  only `init.xlisp` names.
- The dual family's struct fields are `value` and `tangent`, and the
  primitive holes are `sin cos exp log sqrt tanh`.
- Reverse mode records its tape on an `ArrayDbl` from `typed-array.x`
  rather than a fixed-size local, so there is no storage argument and no
  overflow `Error`. Every assignment pushes the overwritten value, `if`
  pushes the taken branch after its body, and loops push their trip count
  after the loop; the reverse sweep pops in mirror order. Locals are
  hoisted and zero-initialized. There is no SSA rename pass; restoring
  overwritten values makes it unnecessary.
- `$ad.both()` emits both siblings because Unit decorators that produce
  several items cannot stack.
- The runtime module is `AdTape`/`AdNode` in `lib/autodiff.x`, an
  optional module registered in `lib/Makefile`, `docs/library-manifest.txt`,
  and the generator's evidence table.
- Compile-time Lisp lessons: `defun` takes one body form (use `begin`),
  `%(...)` list literals separate items with whitespace, and a bare `*`
  in a `match-case` pattern is a sequence wildcard.

## Second round (2026-09-09, same day)

Gary asked for the follow-ups to be finished as well:

- Reverse mode records exit codes: each loop iteration pushes 0 or the
  code of the `break`/`continue` that left it, and each `return` pushes
  its code before jumping to the reverse sweep, so `break`, `continue`,
  and `return` anywhere in the body replay exactly. The reverse of every
  region is generated per exit from the statically known prefix.
- `$ad.checkpoint(K)` runs loops without recording, snapshots the
  variables the loop assigns every K iterations, and replays each block
  from its snapshot during the reverse sweep; tape memory is one block
  plus one snapshot per block. This is two-level checkpointing; a
  checkpointed loop cannot contain `return`.
- The primitive table covers the C99 `<math.h>` real functions with
  closed-form derivatives, including `atan2`, `hypot`, `fabs`, `fmin`,
  `fmax`, and `pow`; the dual family gained `fabs` and `pow`.
- Compiler: a binary operator with one participant operand converts the
  other through its declared converter (`src/expressions.x`); a typedef
  after a function definition is promoted to the header when a later
  public prototype names it (`src/generate.x`). Both have fixtures.
- The sqlite sample in `docs/src/guide/packages.md` is tagged like its
  siblings, so `make doc-examples` is green again.

## Review round (2026-09-09, evening)

An adversarial review (`.context/ad-review/report.md` in brisbane) ran
every chapter sample, wrote fresh probes, and checked each citation. It
found two silent-wrong-gradient defects, both fixed with regression
tests: `continue` in a `for` loop with a step pushed the exit code before
the step's saved value (every prior test used `if (i == 1) continue`,
the one index at which the code and the value coincide), and a `double`
declared in a `for` initializer was treated as a constant. `do` loops now
go through checkpointing like the others, `const` locals are a reverse
mode diagnostic, the chapter's reverse-mode sample asserts the values it
actually produces, and three attributions in the Background section were
softened: Wengert did not use dual numbers, distinct types only separate
perturbation levels when the author instantiates them, and the runtime
tape is a Wengert tape with closures rather than the construction of
Pearlmutter and Siskind (2008). The chapter now carries a measured table
(`unittest/benchmarks/autodiff-checkpoint.x`) and a worked example
(`examples/magic/autodiff-fit.x`) fitting a logistic model through a
checkpointed Euler integrator.

## Plan review

- **Established facts and rechecks.** The parser and binder establish
  every node's type; the transformation reads `(expr (double) ...)` and
  never infers types. Constructed syntax is retyped and rebound by the
  ordinary operations after expansion; the plan adds no validator over
  constructed ASTs. The one dedicated diagnostic is
  `x2c.diagnostic.fail` for unsupported syntax, which protects against
  wrong output (a silently constant tangent).
- **Reuse and deletion.** The transformation reuses `match-case`,
  quasiquote, the `x2c.expr.*` constructors, and the existing decorator
  and Unit-splice machinery. The dual family reuses protocol operator
  rows and `Type`-hole generics exactly as `lib/list-generics.xmacro`
  does. The runtime tape reuses `Func`, `Scope`, and `protocol Var`.
  Nothing existing is deleted. New lasting mechanisms: one Lisp file, one
  xmacro, one runtime module, and the Phase 0 diagnostic route. Each is
  the smallest owner of its behavior.
- **Idiomatic x2c.** Users see one typedef and one macro call for dual
  numbers, and one decorator line for a transformation. Generated code is
  ordinary scalar C with spelled names. No framework, no runtime type
  parameter, no hidden dispatch.
- **Validators and fixtures.** `x2c.diagnostic.fail` on unsupported
  statements or expressions (wrong output); a runtime `Error` when a
  counted loop exceeds its declared storage (corrupted adjoints); the
  Phase 0 fixture (deliberate public behavior: diagnostics name the
  failing Lisp operation). No other checks.
