> Status: reference; research paused at Gary's request on 2026-10-11.
> Branch: `codex/nested-modules-spike`. This is a saved experiment, not an
> integration-ready change. No adoption or merge is authorized.
> Branch point: `c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04`.
> Latest compiler implementation: `73c791df84483ca94a00c25870f728ecab3ba0d7`.

# Nested modules: implementation and integration handoff

The spike adds an implementation boundary between a source file and a package.
A module owns several files and gives them shared private declarations. A
package still owns discovery, installation and its existing public name prefix.
Nested modules inherit access to their ancestors without granting access upward
or sideways.

The real compiler uses this design for macro handling. The compiler and its
structured bootstrap have built successfully. The full language specification
remains unproven. Six native-meta controls fail, general SCC declaration
collection is incomplete, and final combined validation was interrupted.

The purpose of this document is to let another agent reconcile this design
with current `dev`. Preserve current `dev` behavior while transferring the
module capability. Do not treat either branch's implementation or tests as
authority over Gary's intended semantics.

## The developer's code

An entry lists its implementation files explicitly:

```c
#include "compiler.x"
#include "grammar.x"

module typedef struct Category { int kind; } Category;
module int shared(Category value);

module {
  "macros/categories.x",
  "macros/definitions.x",
  "macros/quotations.x",
  "macros/expansion.x",
}
```

The list uses commas, permits a trailing comma, and has no final semicolon.
It creates membership, not a lexical declaration scope. Includes and ordinary
definitions may appear on either side. The entry is itself a member.

`macros.x` owns files below its companion directory `macros/`. A nested entry
owns its own list:

```c
/* macros/quotations.x */
module {
  "quotations/parsing.x",
  "quotations/construction.x",
}
```

The actual compiler layout is:

```text
src/macros.x
src/macros/categories.x
src/macros/definitions.x
src/macros/expansion.x
src/macros/quotations.x
src/macros/quotations/parsing.x
src/macros/quotations/construction.x
```

Helpers used by one file stay `static`. Cross-file helpers use `module`.
Quotation members can use the outer category operations. Helpers owned by
quotation handling remain inaccessible to outer definition and expansion code.
Outer code calls public quotation operations, including
`Compiler.parse_macro_quotation`.

Members need no mutual includes for ordinary function or type declarations.
They still need explicit includes for another member's compile-time effects.
There is no `part`, `internal`, or required parent declaration. The
single-string `module "../parent.x"` form is not implemented.

## Three identities, one ownership tree

Keep these distinctions when integrating:

| Identity | Responsibility |
| --- | --- |
| Source unit | File-local declarations, macro environment, initialization, cleanup and separate generated implementation |
| Module | Explicit membership, ancestor access and shared private declarations |
| Package | Discovery, distribution and existing public runtime-name prefix |

[ModuleTree](../src/module-tree.x) owns entry discovery, membership,
ancestry and logical identity. Canonical paths establish physical ownership.
Direct-member invocation searches candidate enclosing companion entries and
verifies their lists. Location alone grants no access. Duplicate membership,
multiple owners, missing members and escaping paths reject.

Private emitted identities use the existing package or compiler-home namespace
when available. Project roots use their source-relative identity. Anonymous
trees use the outer entry filename and relative member paths. Colliding
identities reject; moving a tree must not rename its private C bindings.
Import aliases do not affect emitted identity.

The implementation stores ownership and emitted-name facts in the existing
symbol operations. It does not introduce a second declaration representation.
Important facts include `module-owner`, `module-private`, `declaration-file`,
`declaration-module` and emitted binding identity.

[module-access.x](../src/module-access.x) selects the current owner, qualifies
private names and checks access. [symbols.x](../src/symbols.x) resolves owned
declarations alongside existing local and public lookup. Functions, variables,
types and compile-time declarations carry their relevant ownership facts.
Access checks concern bindings, including constructed syntax; they do not
authenticate an AST's origin.

## Collection, effects and scheduling

[collect.x](../src/collect.x) remains the collection owner. Its module path
collects ordinary declarations before implementations bind. It reuses the
existing parser with signature modes, rather than implementing another grammar.
Signature discovery is an additional pass, not a promise of one source parse.

`SIGNATURE_DECLARATIONS` retains declarations and canonical macro recipes
without executing later bodies or declaration producers. `SIGNATURE_HASHES`
serves retained evidence. The real compiler needed recipe and alias handling
here because its loop aliases and macro templates occur in declaration slots.
Completed ancestor declarations also supply class constructor defaults. An
executable project-meta advertisement is excluded from that declaration import.

An entry prefix supplies accessible compile-time effects to members. Nested
entries receive the parent prefix and extend it with their own. Entry statics
do not become member declarations. Sibling effects are not installed merely
because a sibling appeared earlier in the member list. Public contributions
are processed in list order for external consumers. Later entry effects do not
execute speculatively to discover earlier signatures.

The experimental interface format is **15**. It records ownership queries,
membership-related dependencies, include roots, definitions and effects through
the existing interface machinery. Portable ownership queries are resolved
against the consuming home; stale original-home absence facts must not be
trusted after relocation. Source, compiler and dependency validation remain
part of replay.

[module-schedule.x](../src/module-schedule.x) implements directed Tarjan
components. **Its current use is narrower than the specification.**
[main.x](../src/main.x), `Translation.translate_modules`, collects the seed,
builds declaration/layout records, binds the seed first, and orders remaining
body work by components. It retains the seed Context and closes each other
implementation Context after exporting its outputs.

The scheduler does not govern general mutually dependent declaration collection.
Exported `binding-references` rows do not drive scheduling. Successful recursion
fixtures must not be described as proof that all declaration cycles become a
DAG. Layout, initialization and ordered-producer cycles remain distinct problems.

## Includes and native layouts

Quoted member includes search the file's directory, the immediate entry's
directory, ancestor entry directories, then existing configured roots. Duplicate
roots are removed while preserving precedence. Angle includes keep existing
behavior. Ownership and include-search attempts feed dependency evidence.

Native compilation must use the dependency selected during translation.
Rediscovering a same-named header through generated-directory precedence is not
equivalent. Package copy and bootstrap copy reconnect dependencies to copied
artifacts.

Complete types are the largest structural extension. A simple concatenation of
member headers failed on by-value layouts and grew badly on diamond graphs.
The revised implementation indexes bound type families and namespace demands
in [module-layout.x](../src/module-layout.x), with emission changes in
[generate.x](../src/generate.x), [emit.x](../src/emit.x) and
[format.x](../src/format.x).

Generated C/H retains separate files and support headers. Module blocks emit
no C. File-static type spellings remain distinct where native support needs
their complete layout. Public inline code can receive hidden native support
without granting x2c lookup access. Public opaque declarations can retain a
private aggregate body.

`.xnm` metadata identifies labelled native regions, type families, namespace
demands, provider paths and initializer relationships. The configured native
preprocessor selects active regions before
[native-layout-project.py](../tools/native-layout-project.py) projects the
needed support. This preserves tested native macro state and packing behavior
without recursively duplicating every aggregate body. It is not a general C
parser, and arbitrary conditional layouts or pragmas remain unproven.

[toolchain.x](../src/toolchain.x) invokes this helper.
[build.x](../src/build.x) retains output placement and native dependency evidence.
The helper adds a Python 3.10-or-later runtime dependency and preprocessing work.
The metadata footprint is substantial. Neither simplicity nor throughput has
been established merely because the layout fixtures pass.

## Initialization, native meta and packages

Runtime objects keep their defining file's initialization and cleanup owners.
Module-visible references add prerequisites through the existing initializer
queue and guards. Target-selected native receipts also check direct initializer
relationships. The member list is not initialization order.

The collector follows bound initializer syntax. It does not follow arbitrary
function calls into their bodies to discover every object read. The indirect
initializer-cycle control therefore incorrectly succeeds. Direct-object cycle
rejection is separate passing evidence.

Native-meta readiness is owned by [meta-project.x](../src/meta-project.x),
with prefix emission in [meta-group.x](../src/meta-group.x) and binding in
[meta-native.x](../src/meta-native.x). Readiness, declaration headers and loaded
implementations are distinct. Active providers can publish reached declarations
without loading unfinished bodies. Ordinary inactive included providers can
prepare headers through existing parsing. Inactive module providers must not
parse their later members merely to satisfy a header request; that path remains
incomplete.

Important repairs in the paused implementation are:

- Native emission clears the caller's function context, so ordinary cleanup
  lowering also runs for emitted meta functions.
- Already-bound object references receive native prefix spellings through
  binding ownership, rather than textual substitution.
- Meta-function stubs retain their borrowed signature Lists before the Func
  moves into the Lisp scope. Missing retention produced invocation-dependent
  size errors and a compiler crash. Both lifetime controls now pass.
- Module groups without layout metadata still obtain selected initializer
  receipts through the existing preprocessing helper.

Packages reuse their existing resolver and public prefix. A package entry with
a module block is the root module; child public declarations export transitively.
Private root declarations are available down its tree, while child private
declarations remain within that child's descendants. Tests are consumers unless
explicitly enrolled. Package build, archive, bundle, install and relocated native
consumer controls pass at an earlier pinned compiler revision. Protocol, native
module and foreign-name filtering combinations remain insufficiently exercised.

## Bootstrap and the paused checkpoint

The bootstrap preserves directories, including nested quotation output. It does
not flatten basenames. [copy-bootstrap.py](../tools/copy-bootstrap.py) recursively
copies C/H/XNM and reconnects literal quoted includes and native provider paths
to the same copied artifacts. Bootstrap Makefiles discover nested C files and
retain matching object paths. The projection helper is copied into bootstrap.

Checkout-native literal header closure is copied at its original structure.
Macro-spelled includes and configured-root-only closure are not fully proved.
An independently relocated final bootstrap build is still pending.

At pause, the latest refreshed bootstrap built and linked. The subsequent clean
compiler recovery regenerated all 78 runtime and 65 compiler sources but was
interrupted during native compilation. A read-only comparison then confirmed
bootstrap and regenerated stage-zero C/H/XNM equality across **340 files**.
Latest strict self-host comparison and the final gate did not finish. Earlier
combined recovery and strict self-host equality passed before the last repairs.
No complete final gate certificate exists.

The current bootstrap sources and metadata are saved, including the new helper.
Temporary objects, dependency files and local logs are not shipped as source.
Do not hand-edit bootstrap. A resumed agent should use the documented safe build
and refresh targets before evaluating the saved compiler.

## Evidence and unresolved requirements

[Saved receipts](nested-modules-evidence/README.md) travel with this branch.
Temporary paths in them identify the original runs; they are not portable
artifact locations. Broader matrices were not rerun after every later repair.

| Evidence | Revision | Result |
| --- | --- | --- |
| Module visibility, ordering, nesting and initialization matrix | 01bd3982 | 113/113 |
| Layout matrix | 01bd3982 | 70/71; ordinary packed-provider syntax also fails on the baseline |
| Full compiler cold/retained replay, two homes | 01bd3982 | 249 artifacts match in each home |
| Package delivery, including relocation | 01bd3982 | All 24 actions pass |
| Native-meta matrix | 73c791df | 11/17; both lifetime controls pass |
| Complete book-output run | Before signature retention | 102/102 compile with matching output |
| Current bootstrap generated comparison | Paused final run | 340 C/H/XNM files match; final self-host/gate incomplete |

The six current native failures are `active_ordinary_prefix`,
`active_reached_ordinary_prefix`, `module_ordinary_shared_variable`,
`module_ordinary_cleanup`, `module_meta_shared_variable`, and
`module_initializer_cycle`. The last incorrectly accepts a cycle; the others
fail to build. Saved diagnostics are in
[native-meta-failures-73c791df.json](nested-modules-evidence/native-meta-failures-73c791df.json).

Other unproven requirements include general SCC declaration collection,
invalidated-versus-fresh binding/artifact equality, ownership-path mutation
combinations, complete visibility agreement combinations, and all-platform
native linkage. Existing mutation tests mostly check program outcomes, not
precise retained rebuild work.

The [iteration report](nested-modules-iteration-two-report.md) records exact
historical operation and layout-growth measurements. Hot-host elapsed timing is
not used as a performance conclusion. Matched final native artifact sizes,
quiet-host throughput, peak memory and complete flat-versus-nested cost remain
unmeasured.

## Reconciling with dev

The last fetched dev tip is `ae14e1c5`. At that comparison, dev had 116 commits
since the branch point and the spike had 234 private commits. Both changed 17
of the same source/build files. The saved divergence receipt pins both full
hashes. This is not a small textual rebase.

Dev has moved literal, operator, printf, raise, interpolation, destructuring and
match lowering into shipped components. It also changed the rule driver,
transform-time entry placement, meta query generation and native helper
translation. The spike was developed against the earlier owners.

Reconcile the designs by responsibility:

| Area | Transfer from the spike | Preserve or reconcile from dev |
| --- | --- | --- |
| Discovery and binding | ModuleTree, owner facts, ancestor access, logical identity | Current symbol/type contracts and diagnostics |
| Parsing and collection | Contextual module block/modifier, preambles, signature modes, interface evidence | Current grammar, macro rule driver and declaration producers |
| Compiler macro split | Shared helper ownership and nested quotations | Current macro behavior; do not restore superseded lowering owners |
| Transformation and emission | Hidden support placement, complete-layout prerequisites, initializer dependencies | Current component lowering and transform-time entry assembly |
| Native meta | Private filtering, header/readiness distinction, signature lifetime | Current query SDK, helper self-translation and provider binding |
| Build and packages | Nested output placement, copied dependencies and metadata | Current package and toolchain behavior |
| Bootstrap | Recursive structure and reconnecting copied dependencies | Regenerate from reconciled authoritative source; do not merge generated C by hand |

Useful bounded transfer units are discovery/access, collection/replay, layout
projection, native-meta readiness, then the real macro migration. They share
binding and lifetime contracts, so those contracts need one agreed owner.
The current Python projection is an evaluated implementation candidate, not
a mandatory architecture for adoption.

For inspection, compare the spike with the branch point rather than individual
checkpoint commits:

```sh
git diff c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04..codex/nested-modules-spike -- src lib tools
git diff c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04..origin/dev -- src lib tools
```

Use the existing focused runners in `unittest/probes/`: `run-modules.py`,
`run-module-layouts.py`, `run-module-native-meta.py`,
`run-module-collection-order.py` and `run-module-package-delivery.py`.
They are spike controls, not new recurring gates. Keep executions serial while
the machine is hot. Final integration requires the existing correctness gate
on the reconciled tree, not proof transferred from either parent branch.

No integration has been attempted. Gary paused the experiment to preserve its
design and let a later agent work out the reconciliation. Saving this branch
does not authorize that agent to merge, publish to dev/main or adopt the design.
