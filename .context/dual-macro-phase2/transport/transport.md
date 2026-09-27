# Phase 2: real program binding hydration through native meta

Baseline: `1b23aaa7e103461c3b219b9e10546aeb35384b60`.
Managed isolation:
`/Users/gary/.codex/worktrees/agent-dual-transport/x2c`.
`make build-safe` completed successfully; no production source was edited,
committed or pushed, and no gate was run. The worker read the orchestration
skill; the root's exact-baseline prototype authorization supersedes its
ordinary origin/dev/publication workflow.

## Executed result

A real compiler capture transports its current program binding to the native
helper. A native meta function constructs a transparent descriptor around that
reference, passes it through another meta function, matches actual captured
program code using its body, reconstructs using that same body and captured
rows, and returns the result for ordinary compiler binding. No stub binding
IDs, foreign pointers, compiler-query callbacks or compiler changes are used.

`domain-helpers.xmacro` and `domain-main.x` contain the working code. The
one-off `python3 /Users/gary/.codex/worktrees/09fa/x2c/.context/dual-macro-phase2/transport/run-transport.py --compiler ABSOLUTE_X2C` runner creates an isolated
cache and source directory, builds baseline, mutates the same source path to
shift bindings, and reruns against its warm helper. It asserts both program
executions, changed program IDs, and unchanged helper bytes AND mtime.

Most recent reproduction:

```
python3 /Users/gary/.codex/worktrees/09fa/x2c/.context/dual-macro-phase2/transport/run-transport.py --compiler /Users/gary/.codex/worktrees/dual-values-validation/x2c/builds/0/x2c
baseline: helper binding 54, price binding 106
shifted:  helper binding 56, price binding 111
helper_unchanged: true
both outputs:
  domain hydration: rigid free mismatch, composition, typed rebuild pass
```

The program changed by adding one unused global and three unused locals.
The unchanged cached native helper used fresh input relationships correctly.
Snapshot evidence is in `debug/domain-repro.log` and its reported scratch
`summary.json`; the runner uses a fresh cache, so independent reproduction does
not alter this evidence. Earlier individual runs also preserve
`helper-before.json`, `helper-after*.json` and `debug/domain-probe*.log`.

## What is actually passed and matched

Existing macros provide code capture arguments:

```x2c
macro Expression $domain(Expr $rigid, Expr $subject) =>
  $domain_pipeline($rigid, $subject);
macro Expression $bridge(Expr $subject) => $domain(helper, $subject);
```

`helper` in bridge is a real definition-site program reference. The helper's
incoming `rigid` is, for example:

```
(expr ((func ((int))) int) (ident (binding 54 "helper")))
```

`domain_hydrate(rigid)` makes this fixture-specific ordinary List descriptor.
Its `syntax-template` symbol is evidence from the fixture, not a proposed
public representation:

```
(syntax-template
  (body (expr ?result (call RIGID (args ?argument))))
  (rigid RIGID))
```

`domain_pipeline` obtains its body after `domain_relay`, runs
`subject.try_match(body, bindings)`, reconstructs with
`body.replace(bindings)`, and explicitly asserts structural equality with the
original subject. A mismatch returns an ordinary literal-zero AST. Existing
compiler binding consumes the returned expression AST.

The program asserts:

```x2c
int price = 20;
assert($bridge(helper(price)) == 21);
{
  int (*helper)(int) = other;
  assert($bridge(helper(price)) == 0);
}
```

Thus a same-name, compatible function-pointer callee cannot satisfy the
rigid definition-site reference. This is actual helper recognition against
issued program binding records, not a model of manually supplied identities.

## Anonymous data closure and composition

`domain_anonymous(bias)` constructs one body capturing an actual caller-side
Expr reference:

```
(expr ?argument_type (op + ?left BIAS))
```

The descriptor carries the same BIAS syntax as an inspectable capture field.
`domain_compose(outer, inner)` substitutes that child body into outer's
`?argument` slot with the existing `List.replace`. A subsequent native meta
function relay/match/reconstruction uses the resulting single body. Working
assertions:

```x2c
int price = 20, tax = 1, discount = 2;
assert($composed(helper, tax, helper(price + tax)) == 22);
assert($composed(helper, tax, helper(price + discount)) == 0);
```

`tax` and `discount` have the same int type and different issued bindings.
The second expression fails recognition despite equal grammar/type shape.
This proves data code closures with real binding-valued capture and pure
composition work in native meta today. It does not prove new anonymous macro
literal parsing or automatic template-body extraction: these descriptors use
hand-authored canonical AST patterns, clearly distinct from the parser agent's
separate first-class Macro prototype.

## Typed category transport and executable reconstruction

A Statement macro supplies a Type, Name and Statement capture to native meta:

```x2c
macro Statement $typed(Type $wanted, Name $name, Statement $statement) {
  $domain_types($wanted, $name, $statement)...
}
$typed(int, price, price += 1;);
assert(price == 21);
```

`domain_types(Type wanted, Var name, List statement)` sees:

- Type: `((name "int") (kind scalar) (type (int)) (fields ()) (methods ()))`;
- Name value projection: String `"price"`;
- Statement: `(stmnt (expr (int) (op += ... (binding CURRENT "price") ...)))`.

It asserts the Type and Name contents and returns `%($statement)`, a syntax
sequence inserted through existing `...`. The emitted program actually
increments the captured local. Main-issued Statement reference IDs change
from 106 to 111 under cache reuse and remain correct.

Important current limitation: a Name hole's ordinary value projection is a
String in this example. Passing it to `List name` fails the existing native
signature with actual string/want list. Recognition/construction must carry
Name source/expression/declaration relationships in its new capture interface
rather than assuming current projected Name values retain binding identity.
This is evidence for reusing capture projections coherently, not evidence for
changing all Name captures to compiler binding objects.

A returned single `stmnt` in an expression-helper position fails ordinary
placement; wrapping it as `%($statement)` and using `...` is the existing
correct Statement code insertion. This prototype follows ordinary position
ownership and does not add a validator.

## Domain mechanism and remaining integration

The transport mechanism is existing explicit code capture arguments, which
are equivalent to a supplied template environment at the semantic boundary:
compile the native meta function's executable machinery once; inject current
program references as immutable Lists each call; never bake helper-build
positive IDs into target code.

This proves the required data route without callbacks. A user-friendly named
Macro getter or anonymous literal still must populate that environment
implicitly. The smallest extension is definition skeletons with external slots
registered by normal unit parsing, hydrated through current-domain bindings
carried in the existing helper request. It can be represented as an implicit
ordinary List argument/environment; this probe does not implement request
protocol changes or stable lexical registration keys.

Existing source justifying separate domains:
`src/meta-project.x:120-132` parses units for helper building; `277` invokes
that pass and `291` can compile imports-only fallback source.
`src/stage.x:758-772` borrows bindings from that build Compiler. The later
program translation owns different IDs. `src/macros.x:4164-4166` transports
global deferred template names rather than those IDs, and `3013-3029`
resolves definitions against the active compiler before invocation rows.

A root/parser prototype that merely embeds helper-build macrodef snapshots
can establish arithmetic closed-body values but cannot establish rigid free
capture across cache reuse. Current explicit capture argument hydration is a
working reference approach for fixing that boundary. Anonymous literals inside
native meta functions must distinguish:

- main program code references transported by current compiler captures;
- meta runtime values evaluated into explicit data/hole captures;
- helper-native lexical variable IDs, which cannot identify program locals.

Local-macro lifetime, captured declaration relocation/fresh copies, imports
with aliases/redefinition, source provenance, automatic registration and
identity hydration for literal free references, and callback-free expansion
returning into helper code are not implemented by this probe. Match retry and
alpha normalization are covered by the other worker, not these fixed-shape
structural tests. The phase 2 parser prototype is separately responsible for
actual Macro/$sum/application surface syntax.

## Actual first-class source Macro prototype integration

After the parser worker supplied its modified compiler at
`/Users/gary/.codex/worktrees/dual-parser/x2c/builds/0/x2c`, the additional
`macro-hydration.x` probe uses its actual proposed surface and transparent
macrodef representation:

```x2c
macro Expression $with_helper(Expr $argument) => helper($argument);
meta static Macro macro_relay(Macro t) => t;
meta static List macro_pipeline(List rigid, List subject) {
  Macro original = $with_helper;
  Macro hydrated = macro_hydrate(macro_relay(original), rigid);
  List rows;
  if (!subject.try_match(Macro_pattern(hydrated, %(?argument)), rows))
    return x2c_literal_int(0);
  List argument = rows.assoc(<?argument>);
  return hydrated(argument);
}
```

This is executed code: bare `$with_helper` obtains an unapplied source macro
value in native meta; the value passes through ordinary meta functions; one
body drives actual pattern preparation and dynamic application. `macro_hydrate`
reads the canonical macrodef's template, replaces its callee field with the
provided current-domain reference, and rebuilds ordinary macrodef rows. This
is an explicit user-level structural transformation of a template's callee,
not an implemented compiler registration/hydration protocol. It establishes
that transparent source macro values admit the domain bridge; it does not
claim automatic capture-role determination.

The probe contains the parser worker's isolated `Macro_apply`,
`Macro_pattern_view`, and `Macro_pattern` definitions physically in the source
so native meta grouping can reach their static definitions. These operations
are prototype machinery, not current repository APIs. Their limited Expr
projection/type handling is exactly the worker's implementation; the probe
does not establish complete grammar/hygiene/alpha semantics.

The main program tests a global callee, a local function-pointer callee and
wrong rigid-callee rejection. The local callee is a real program free reference
relative to the returned template body; it must be transported from main
compilation rather than inferred from the helper's original positive ID.

`python3 /Users/gary/.codex/worktrees/09fa/x2c/.context/dual-macro-phase2/transport/run-macro-transport.py --compiler MODIFIED_COMPILER` reproduces baseline and
shifted main compilation against one warm native helper. Observed records:

```
original source macro callee: binding 92 "helper"
selected main local callee:   binding 129 "helper"
after adding three locals:   binding 132 "helper"
wrong rigid external callee: binding 94 "other"
helper SHA256 and mtime unchanged: true
both executables print:
  actual Macro hydration: getter, relay, shared pattern/application pass
```

Log: `debug/macro-domain-repro.log`; the reported scratch directory retains
both builds' full logs and `summary.json`. Individual executions retain
`macro-helper-before.json`, `macro-helper-after.json`, and
`debug/macro-hydration*.log`. The automatic stable-key environment mechanism
and anonymous source macro literal are still outside this probe. It adds
actual Macro-value inspection/application evidence to the earlier transparent
data closure/composition and typed-category transport results.

## Anonymous literal cross-review

Reviewed the parser worker's
`/Users/gary/.codex/worktrees/dual-parser/x2c/.context/parser-spike/complete.x`.
Its `factory` creates an actual anonymous source Macro and `relay` passes that
ordinary value. Its `composed` function explicitly reads the child template
AST, applies a parent wrapper, and edits the returned descriptor's template
and parameter rows. This is real structural composition through transparent
values; it does not prove lexical capture of a Macro value used inside an
anonymous literal body.

For a literal whose code is conceptually `inner($left, $right)`, where `inner`
is a native-meta Macro parameter, the capture is the current VALUE of `inner`
(the whole transparent descriptor), not the helper compiler's binding ID for
that parameter. Ordinary typing can identify this role while parsing the
literal. Literal evaluation should evaluate this meta-value capture and place
it in an ordinary capture row. The body refers to that row's slot at the
existing nested macro invocation's stored-definition position. Shared
substitution installs the captured descriptor and forwards the parent holes
into the child's existing argument/capture projections.

Construction can retain that invocation until ordinary insertion. Recognition
can explicitly inline its structural child body with hygienic slot remapping,
or match the retained invocation when that stage is selected. Both operations
use the captured descriptor; neither resolves helper-native `inner` as a
program identifier, executes arbitrary meta computations backward, or requires
a compiler callback. This should reuse existing macro-invoke and capture-row
forms, not add an authored pattern language.

Two distinct domains remain explicit:

- Meta-value capture of `inner` snapshots a transportable Macro List while the
  helper runs. It must use existing List ownership/snapshot conventions when
  returning beyond a local scope, not capture a native stack pointer.
- Free program references inside that captured child descriptor retain its
  program binding domain and existing hydration requirements. Capturing the
  descriptor does not repair stale child free IDs or make them globally valid.

A source literal referring to a native-meta int local as code needs a separate
explicit value/hole capture operation, or a clear existing grammar rule for
lifting that value. It cannot silently reuse the helper's local binding ID as
a target-program free reference. The tested data-closure and actual Macro
hydration pipelines demonstrate the transport route; automatic lexical
meta-value capture and its returned-value lifetime remain unimplemented.

A convincing follow-up for the parser worker is a factory accepting `Macro
inner`, returning an anonymous Macro whose body directly invokes that lexical
value; return it through a second meta function; recognize and construct from
it; then pass another same-interface inner Macro and observe different bodies.
Add a child with a hydrated rigid program reference to distinguish genuine
value capture from baked helper-compiler IDs. No further prototype was run for
this cross-review, and no public helper API is claimed by these fixture names.

## Updated lexical Macro capture implementation review

The latest isolated parser changes now implement the direct callable capture
previously missing. `Compiler.capture_macro_value` emits an ordinary
`Macro_close(literal, rows)` expression. Each row pairs the literal's captured
binding record with the CURRENT Macro descriptor value read from the lexical
variable. `Macro_close` appends those immutable List rows as an environment.
No native Func closure or stack address is stored.

Inside the anonymous body, `_parse_postfix_apply` retains a Macro-typed callee
as `tpl-call` while `macro_holes` is active. `Macro_inline` handles that exact
role: it looks up the descriptor value under the captured binding record and
calls the shared structural `Macro_apply` on the child and supplied code
arguments. Both application and pattern preparation run that same inline
operation. The helper binding record is an ENVIRONMENT KEY, not a target
program reference. For the exercised `inner($left, $right)` role, inlining
removes the callee's helper-local identifier before constructed code reaches
ordinary binding.

The newest `complete.x` exercises an actual lexical literal:

```x2c
meta static Macro lexical_wrap(Macro inner) =>
  macro Expression(Expr $left, Expr $right) => (inner($left, $right));
```

This supersedes the prior statement that only explicit descriptor editing was
implemented. The earlier `composed` example still edits descriptors manually;
the distinct `lexical_wrap` now tests creation-time Macro-value capture.
Root/parser runtime results own the execution claim; this worker reviewed the
updated source without running another compiler build.

The lifetime path is ordinary List data: an immutable child descriptor is
stored as a List value, helper return serialization occurs before per-unit
reset, and compiler decoding produces compiler-owned data. This does not
extend the lifetime of free program binding domains. No native parameter-stack
address is transported. General in-process persistence past explicit Scope
teardown is not proven by this source review.

Two bounded limitations remain:

- Capture classification retrieves type using the captured spelling rather
  than querying its captured binding identity. The direct unshadowed parameter
  fixture is supported; broader shadowing/alias roles should use authoritative
  binding facts before making a general lexical capture claim.
- `Macro_inline` consumes captured Macro references only at callable tpl-call
  positions. Bare/noncallee occurrences of the helper-local Macro identifier
  are not transformed by this implementation. Claims that no helper identity
  can escape must therefore be limited to the exercised direct-call role;
  general meta-value capture must retain role metadata or define those uses
  separately. Ordinary child free references retain the previous hydration
  caveat.

This is adequate evidence for callable anonymous Macro composition in the
isolated prototype. It is not evidence for arbitrary lexical meta values,
complete copying/freshening, lifetime across binding resets, or automatic
program definition-site hydration.
