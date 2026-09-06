# x2c source graph

This tool uses the current stage-0 x2c compiler as a library. Its local build
archives the compiler objects except `main.o` as `builds/libx2c-dev.a`; it does
not install or expose a supported compiler library.

From this directory, build the tool and inspect the compiler and runtime sources:

```sh
make
make run
```

The executable accepts explicit x2c source files and optional include paths:

```sh
builds/x2c-graph graph [-I DIR] FILE...
builds/x2c-graph digest [-I DIR] FILE...
builds/x2c-graph datasets OUTPUT [-I DIR] SRC_FILE... -- LIB_FILE...
builds/x2c-graph architecture [-I DIR] FILE...
builds/x2c-graph structure UNIT [-I DIR] FILE...
builds/x2c-graph between LEFT RIGHT [-I DIR] FILE...
builds/x2c-graph focus NAME [-I DIR] FILE...
builds/x2c-graph field TYPE FIELD [-I DIR] FILE...
builds/x2c-graph field-sites TYPE FIELD [-I DIR] FILE...
builds/x2c-graph sites NAME [-I DIR] FILE...
builds/x2c-graph walks [-I DIR] FILE...
builds/x2c-graph tail-calls [-I DIR] FILE...
builds/x2c-graph loop-allocations [--all] [-I DIR] FILE...
builds/x2c-graph lifetime-escapes [-I DIR] FILE...
builds/x2c-graph allocation-returns NAME [-I DIR] FILE...
builds/x2c-graph flows PRODUCER CONSUMER [-I DIR] FILE...
builds/x2c-graph compare LEFT RIGHT TARGET... -- [-I DIR] FILE...
```

`graph` emits a deterministic function call graph. Direct calls resolve first
within their source unit and then to one uniquely named public definition in
the supplied files. Function pointers and computed callees remain indirect;
missing or ambiguous definitions remain external.

`digest` condenses that graph into per-unit function counts, internal and
cross-unit call counts, unresolved and indirect calls, and cross-unit cycles.

`datasets` writes one node table and two directed edge tables under `OUTPUT`:

```text
functions.tsv
src-calls.tsv
lib-calls.tsv
```

The files are UTF-8 TSV with LF endings, one header, no comments, and rows
sorted by endpoint ID. The files named before `--` receive the `src` label;
those named after it receive the `lib` label. This explicit grouping makes the
label independent of checkout paths or symlinks. Both groups must contain at
least one source file. Inputs are canonicalized and deduplicated within each
group; one file cannot belong to both. All inputs are parsed and resolved
before the output directory is created, so a missing or malformed input does
not leave a partial dataset.

`functions.tsv` has these columns:

```text
function_id  kind  subtree  unit  unit_lines  source_order  source_name  emitted_name  visibility  external_calls  indirect_calls
```

The separators in the actual file are tabs. `function_id` is
`UNIT::EMITTED_NAME`, the canonical endpoint used in both edge files. A line
or column is not part of identity. `kind` is `function` or `top-level`, and
`subtree` is the explicit `src` or `lib` group. `unit_lines` is the physical
source-file line count. `source_order` is the one-based order of parsed
functions in the unit; the synthetic top-level caller uses zero.
`source_name` preserves an x2c method as `Owner.member`, while `emitted_name`
is its resolved C name. `visibility` is `static` or `public`.
`external_calls` and `indirect_calls` count parsed call expressions made by
that function whose target is respectively missing or ambiguous, or computed.
They are counts, not graph endpoints.

Both call files have the same columns:

```text
caller_id  callee_id  static_calls
```

Direction is caller to callee. `src-calls.tsv` contains only `src` to `src`
edges. `lib-calls.tsv` contains `lib` to `lib` edges and every edge crossing
between `src` and `lib`. Its name therefore means the graph containing the
library subtree and its compiler boundary, not merely calls made by `lib`.
Concatenating the data rows of both files reconstructs the complete resolved
direct-call graph without duplicate edges. `static_calls` is the number of
parsed call expressions aggregated for the endpoint pair after compile-time
macros run. It is useful as a syntactic coupling weight, but it is neither
runtime traffic nor a physical flow capacity.

The synthetic `<top-level>` node keeps calls made by static initializers and
other executable file-scope forms connected to their unit. It is
an ordinary graph node. Calls that do not resolve are retained only in the
two count columns on their caller; the exporter never invents a destination.

The optional Make target exports all hand-authored compiler and runtime units
and excludes generated `lib/x2c.x`:

```sh
make datasets
make datasets DATASET_DIR=/tmp/x2c-datasets
```

The default directory is `builds/datasets` under this tool.

### Reading and analyzing the datasets

The direct function graph uses every `function_id` as a node and every row in
the two call files as a directed edge. Use `unit`, `subtree`, `visibility`,
and `source_order` as node attributes. Begin clustering with one unit of
weight per edge, then compare the result using `static_calls`; agreement is
more informative than treating the syntactic count as observed execution.

A file graph is derived rather than separately exported. Join each endpoint
to `functions.tsv`, group edges by caller and callee `unit`, and retain both
the number of distinct function edges and the sum of `static_calls`. This
shows wide or reciprocal file dependencies without hiding which functions
participate.

To examine a large source file, select its nodes and the edges whose two
endpoints are both in that unit. Cluster that induced graph without using the
current unit label. For a proposed split, report the number of functions and
internal edges in each part, directed edges and summed call occurrences that
cross the proposed cut, and cut edges whose callee is currently `static`.
Also list public functions and sum external and indirect calls in each part.
Those facts distinguish a low graph cut from a move that would require new
linkage or leave important unresolved dependencies unexplained.

For visualization, files work well as containers, discovered communities as
colors, visibility as node shape, optional `static_calls` as edge width, and
the proposed cut as highlighted edges. Network-flow and community algorithms
should treat direction deliberately: a symmetrized graph answers a different
question from conductance, directed modularity, or a caller-to-callee cut.

These datasets contain the parsed direct-call graph, not every dependency
needed to move code safely. Calls introduced only by later transforms,
generated protocol adapters, C-only code, speculative callback targets, and
direct function-value dependencies are omitted. Types, globals, macros, and
initialization ordering beyond calls retained on `<top-level>` are also
outside the graph. A candidate file split must trace those dependencies in
source after the graph identifies a promising boundary.

`architecture` summarizes the resolved graph to help you find related code.
It ranks functions by distinct cross-unit callers, reports unit pairs that
call each other, ranks dependencies by the number of functions participating
on both sides, summarizes disconnected groups of functions within larger
units, and identifies functions whose removal separates two substantial
local groups. The fixed limits and thresholds appear in the output. Use
these results to explore dependencies and assess the impact of a change.

`structure` reports on one exact input `UNIT`. It emits internal-call totals,
isolated functions, the member names in each local call-graph component, and
the groups separated by each qualifying bridge function. Relative unit paths
are normalized the same way as graph output. Use this with `focus NAME` to
trace a finding before proposing a move, deletion, or simplification.

`between` shows the exact resolved calls in both directions between two input
units. Each direction includes its total call count and the sorted caller,
visibility, callee, and aggregated count for every edge. It explains a
reciprocal dependency reported by `architecture`; it does not imply that the
dependency is unnecessary.

`focus` emits the resolved callers and callees for every definition with the
exact emitted `NAME`. Same-named static functions remain separate and
unit-qualified.

`field` emits the functions that access the exact `FIELD` on the exact parsed
receiver `TYPE`. It counts ordinary reads separately from occurrences in an
assignment, mutation, or indexed lvalue. The counts exclude mutation through
aliases or calls and do not establish ownership.

`field-sites` emits each exact occurrence with its source location and
classifies it as a read, a direct whole-field replacement, or a mutation
through or within the field. Replacements include a compact summary of the
right-hand value. These are syntactic facts, not runtime ordering or object
identity: aliases, mutations hidden inside calls, branches, callbacks, C-only
code, and transform-inserted accesses are not inferred.

`sites` emits every direct call to the exact emitted `NAME`, together with
the caller and a compact summary of each argument. Local arguments include
assignments and declaration initializers encountered before that call in
source order. These `prior-writes` may include writes in alternative earlier
branches; a listed write may never reach the call.

`walks` reports functions that pass the same directly named local value or
direct member path to two or more functions known to traverse that argument.
It recognizes recursive walkers, complete x2c `foreach` loops over `List`,
and `List.len`, then follows exact unchanged-parameter forwarding through
local functions and uniquely named public functions in the input set. A
complete inline `foreach` is displayed as `<inline>`. Loops with an explicit
`return`, `break`, or `goto` are not treated as complete traversals.

Each candidate includes every traversal occurrence and its source location,
including repeated calls to the same walker. The separate sorted walker list
remains a compact summary.

Member paths must be rooted in one binding and contain only `.` or `->`;
calls, indexing, explicit dereference, casts, conditionals, and mutation
expressions are excluded. Paths are displayed compactly with dots even when
x2c lowers dot access on a pointer-like receiver to `->`. The result can
expose repeated full walks over one AST or collection, but it does not claim
that the value was unchanged between calls, that the walkers preserve the
same state, or that they can safely be combined.

`tail-calls` reports exact self-calls in return position, their source
locations, other non-tail self-calls in the same function, and explicit
`defer` or `try` cleanup. Before rewriting a reported function, inspect its
generated C for argument evaluation, automatic storage, and cleanup, and
check the host compiler's optimization.

`loop-allocations` ranks source expressions that allocate List/String pool or
Scope-backed storage inside parsed loops. It groups macro-expanded allocation
nodes at one source location while preserving their counts. It also follows
project helpers whose every return path definitely produces one fresh value
of one ownership kind; those rows count resolved calls, not allocations made
inside the helper. Static helpers remain local to their input and a public
helper must resolve uniquely across the supplied files.

The default output contains the 25 highest-ranked expressions. `--all` emits
the complete ranking without removing project inputs that may be needed for
cross-unit resolution. Each site reports direct allocation counts, resolved
helper calls, uses, operations, and maximum parsed loop depth. The ranking
puts Scope-backed work first, followed by discarded results, helper calls,
total work, and depth. It excludes cached percent literals and one-time
allocations outside loops.

These are syntactic facts for investigation, not proof that work is
unnecessary or that an isolated `Context` is safe. Assignment and argument
use do not establish escape behavior, and a helper summary does not reveal
its internal allocation count. Values that cross a Context still need an
explicit copy or export.

`lifetime-escapes` reports a definite dangling return from an explicit
`Scope` or `Context`. It follows direct local aliases, accepts storage moved
with `Scope.move`, and accepts the value returned by `Context.export`. An
ignored export does not establish a safe result. It also follows project
helpers whose every return path definitely produces fresh storage in the
caller's current Scope or canonical-value pool. Static helpers remain local
to their input; a public helper resolves across inputs only when its emitted
name has one definition.

This is deliberately local and conservative. It does not carry facts through
branches, loops, pointer casts, callbacks, field stores, parameter transfers,
or calls without an exact return summary. Mixed return paths, recursive calls
without an allocation base, and implicit conversions between runtime types
remain unresolved. Values passed to unknown or indirect calls also become
unresolved instead of producing a finding. A missing report does not establish
that the code is safe.

`allocation-returns` reports return expressions in functions with the exact
emitted `NAME` that directly allocate in the caller's current Scope or
canonical-value pool. Each row names the allocation operation, ownership
kind, and source location. This is the check to run before deleting an
apparently redundant copy: replacing a reported `cons`, `Array.list_free`, or
String constructor with an existing value can change which Context owns the
result even when the values are structurally equal. The command does not
infer indirect helper returns or say that the allocation is necessary; it
exposes the ownership change that a candidate rewrite must preserve or
disprove.

`flows` asks where the value returned by one exact function reaches an
argument of another exact function. It follows direct consumption, local
declarations and assignments, returns, uniquely resolved project helpers,
and the narrow value-preserving wrappers shown in the result. Every proved
path includes exact definitions, source sites, the consumer argument index,
and compact summaries of the other arguments, including `AstPos` parameters
or constants. Field storage, mutation, branch alias merging, callbacks,
computed calls, and ambiguous calls remain unresolved.
An empty path list means the analysis found no path; a runtime flow may still
exist.

`compare` accepts two exact entry functions and one or more exact target
operations before `--`. For each operation it reports whether both entries,
only one entry, or neither entry has a resolved call path, together with the
shortest path from each side or an explicit unresolved result.

This is a parsed source graph for trusted x2c programs. Parsing executes their
compile-time Lisp and macros. Calls introduced only by later transforms,
generated protocol adapters, C-only code, and speculative callback targets
are outside this tool's analysis.
