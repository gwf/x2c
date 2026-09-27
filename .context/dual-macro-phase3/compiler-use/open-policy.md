# Genuine compiled-in open value prototype

Isolated parser has genuine `macro open Expression` definition modifier.
Producer stores `(free-policy target-global)` plus `(effects ...)` rows derived
from actual parsed identifier roles. Hole references are projection binders;
fixed locals are fresh-row binders; only retained identifier binding records
produce `(resolve-global OLD_REFERENCE NAME)` effect requests. Compiler applies
requests through Sym.reference_global and existing binding replacement. It
clears fixed expression Type shells, so ordinary target binder resolves target
callee signature and conversion. Borrowed bound argument slot is preserved.
No helper process queries Compiler. This minimal prototype handles free VALUE
references only, and uses private caller plumbing rather than frozen public
`m(args)` routing. It must not be reported as the final lowering API.

Source compiled into compiler binary:
```
static int _compiler_open_target(int value) => value;
macro open Expression $compiler_open_target(Expr $argument) =>
  _compiler_open_target($argument);
```

`_try_block` applies descriptor to existing typed sigsetjmp expression under
X2C_PROTOTYPE_OPEN=1. Target source defines double(double) function with same
name and observable calls++ side effect. Native build succeeded and executable
printed `compiled open target call and preserved caller local PASS`; calls==1.
Compiler stub has no calls++ and does not exist in target executable. Transformed
AST confirms `(expr (double) (call (expr ((func ((double))) double)
(ident (binding 7 "_compiler_open_target"))) ...))`, demonstrating target signature
ownership, not just a coincidentally matching callee C name.

Stable full control binary BEFORE this experiment: /tmp/x2c-dual-bound-control
(all62 raw-byte outcome parity). New candidate: isolated builds/0/x2c.
No production changes, bootstrap regeneration, commits, or publication.

Reproduction:
```
X2C_HOME=/Users/gary/.codex/worktrees/agent-dual-transport/x2c \
X2C_PROTOTYPE_OPEN=1 \
/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c/builds/0/x2c build \
--output /tmp/dual-compiled-open-ok --build-dir /tmp/dual-compiled-open-ok-build \
/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c/.context/compiler-boundary/open/probe.x
/tmp/dual-compiled-open-ok
```

## Counterexample: late insertion has lost lexical context

open-shadow-fails.x uses caller-local int _compiler_open_target=33 around try.
Compiler resolves the correct global binding, but native build fails:
`called object type int is not a function or function pointer`.
At `_try_block`, function parse scope has already been popped. Ordinary global
capture hygiene cannot see the local shadow to rename its emitted binding.
This is an INSERTION CONTEXT gap, not rejection of open templates. All typed
holes can preserve their binding records and still need caller lexical scope
for new fixed references. Source-position/return context alone is insufficient.

Viable alternative: capture the active ordinary semantic scope stack when
parsing/staging the insertion, carry borrowed scope-map interfaces for unit
lifetime, and let existing traversal driver re-enter it using Sym.push_scope
(compiler.x3964); Sym.pop_scope returns the scope value, map owners survive.
Existing binder/hygiene then owns renames. Another initial migration can use
already typed native-call Expr holes for runtime callees (current full-parity
control) while reserving open application for positions with active binder
context. Do not reconstruct a second name resolver by walking arbitrary ASTs.

## Thin/unproved

No global Type/tag projection yet; `_finish_type` still invokes local_type.
No anonymous/local open lookahead probe, arbitrary free lexically captured value,
missing runtime helper signature/header-only names, staged public m(args) routing,
open definition-site diagnostic positions, or full effects rollback extension.
Default closed parsing remains unchanged; prior phase closed hygiene examples
are evidence for existing user macros, not a newly repeated full compatibility
corpus in this open experiment. There is no production semantic validation pass.

## Prototype failure retained

Intermediate new parser initially added open consumption but missed global
macro lookahead; lookahead owner corrected. A producer effects Array wrapped
with $auto was consumed by list_free and then freed again. LLDB identified
Compiler_parse_macro_definition doublefree; plain Array corrected ownership.
These failures reject those adapters; the corrected value policy executes.
Bootstrap sequencing: build parser support with compiler source still closed,
then consume macro open in a second isolated build. No bootstrap C was edited.

## Bounded global Type cast result

Genuine open definition compiled into binary:
```
typedef int CompilerOpenType;
macro open Expression $compiler_open_type(Expr $argument) =>
  ((CompilerOpenType) $argument);
```
Producer derives `(resolve-global-type ORIGINAL_BASE NAME)` only from parsed
cast `decl` Type field. Compiler applies existing base-only Sym.resolve_key,
substitutes its canonical result into that field, clears derived fixed Expr
types, and ordinarily binds the cast. Target fixture defines global
`typedef long double CompilerOpenType` and caller-local typedef of same name to
int; caller value remains int. Native build/run PASS. Transformed code is
`(cast (decl (long double) ...) ...)` and generated C explicitly uses
`(long double) sigsetjmp(...)`, never local int or compiler definition int.
Global primitive normalization avoids subsequent local_type recapture.

Stable final binary `/tmp/x2c-dual-open-type`. Use same command as value test
with X2C_PROTOTYPE_OPEN_TYPE=1 and `.context/compiler-boundary/open/type.x`.
Result executable `/tmp/dual-compiled-open-type-final` printed
`compiled open global Type cast with caller typedef preserved PASS`.
Metadata producer must be in intermediate compiler before a compiled-in
descriptor can contain new Type effects; one intermediate build without it
had no effect records and retained bare alias cast. This was not counted as
global Type effect evidence. Final transformed AST above comes from updated
producer and compiler owner, and raw C confirms the normalized primitive.
An existing legacy macro-body parentheses ambiguity required an extra outer
parenthesis around the cast; no production parser repair was made for it.

This proves ONE cast Type role resolving a known global alias to primitive.
It does not prove Type/tag roles across all AST fields, unknown header-only
names, retention of original typedef C spelling, recursive aggregates,
anonymous open definitions, or active lexical restoration. The value-name
shadow failure remains unchanged and must stay in the plan.

Closed default regression with new parser: actual previous capture-adapter.x
native build/run PASS (renamed locals, nested shadow/free mismatch, preserved
raw binding captures, injectivity checkpoint). No full new user corpus run.
