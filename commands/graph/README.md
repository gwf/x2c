# x2c source graph

This experimental command uses the current stage-0 x2c compiler as a
library. From the repository root, run `make commands` to build it at
`builds/0/libexec/x2c-graph`. The compiler archive is provisional and
stays in the checkout. Run `make commands-check` for its smoke tests.

## Investigate a change

From the repository root, after `make commands`:

```sh
# Find parsed callers and callees before changing syntax binding.
builds/0/libexec/x2c-graph focus Compiler_bind_syntax \
  $(tools/sources.sh --area src)
grep -rn 'bind_syntax' src

# Inspect returned allocation before removing an apparent copy.
builds/0/libexec/x2c-graph allocation-returns String_split_n lib/string/string.x

# Find repeated full walks that may merit source inspection.
builds/0/libexec/x2c-graph walks $(tools/sources.sh --area src)
```

`tools/sources.sh` lists the entry units of `src` or `lib`. Each module entry
splices its member files into one unit, so pass the entry, not the members.

Commands use emitted
names (`String_split_n` for `String.split_n`); supply the relevant source
files to resolve calls across units. Rerun commands for current counts;
archived reports describe older trees. Inspect reported sites before removing
walks or allocations; absent results do not establish safety.
Text-search hits can be definitions, declarations, or comments as well as
calls; a hit absent from graph edges does not establish an unresolved call.

To resolve allocation flows across all hand-authored compiler and runtime
units, this shell example excludes the generated `lib/x2c.x` prelude and keeps
one filename per argument (including in zsh):

```sh
set -- $(tools/sources.sh --area src)
for unit in $(tools/sources.sh --area lib); do
  [ "$unit" = lib/x2c.x ] || set -- "$@" "$unit"
done
builds/0/libexec/x2c-graph flows String_split_n List_iter "$@"
```

## Commands and results

The executable accepts explicit x2c source files and optional include paths:

```sh
builds/0/libexec/x2c-graph graph [-I DIR] FILE...
builds/0/libexec/x2c-graph digest [-I DIR] FILE...
builds/0/libexec/x2c-graph clones [--min-size N] [-I DIR] FILE...
builds/0/libexec/x2c-graph datasets OUTPUT [-I DIR] SRC_FILE... -- LIB_FILE... [-- COMMAND_FILE...]
builds/0/libexec/x2c-graph architecture [-I DIR] FILE...
builds/0/libexec/x2c-graph structure UNIT [-I DIR] FILE...
builds/0/libexec/x2c-graph between LEFT RIGHT [-I DIR] FILE...
builds/0/libexec/x2c-graph focus NAME [-I DIR] FILE...
builds/0/libexec/x2c-graph field TYPE FIELD [-I DIR] FILE...
builds/0/libexec/x2c-graph field-sites TYPE FIELD [-I DIR] FILE...
builds/0/libexec/x2c-graph sites NAME [-I DIR] FILE...
builds/0/libexec/x2c-graph walks [-I DIR] FILE...
builds/0/libexec/x2c-graph tail-calls [-I DIR] FILE...
builds/0/libexec/x2c-graph loop-allocations [--all] [-I DIR] FILE...
builds/0/libexec/x2c-graph lifetime-escapes [-I DIR] FILE...
builds/0/libexec/x2c-graph certify --root NAME [--root NAME ...] [--contracts FILE] [-I DIR] FILE...
builds/0/libexec/x2c-graph allocation-returns NAME [-I DIR] FILE...
builds/0/libexec/x2c-graph flows PRODUCER CONSUMER [-I DIR] FILE...
builds/0/libexec/x2c-graph compare LEFT RIGHT TARGET... -- [-I DIR] FILE...
```

`graph` emits a deterministic function call graph. Direct calls resolve first
within their source unit and then to one uniquely named public definition in
the supplied files. Function pointers and computed callees remain indirect;
missing or ambiguous definitions remain external.

`digest` condenses that graph into per-unit function counts by storage tier,
internal and cross-unit call counts, unresolved and indirect calls, and
cross-unit cycles.

### Repeated syntax experiment

`clones` constructs an analysis-only canonical cons graph from the parsed
inputs. Each cell holds a head, a tail, and an inline 64-bit occurrence
counter: three words instead of the runtime List's two. The runtime List
layout is unchanged. Hashing and equality use only the head and tail.
Every normalized occurrence is constructed, including children of previously
seen subtrees; the counter measures occurrences in this representation, not
runtime references or compiler allocation activity.

Source origins are kept out of structural identity. Automatic local bindings
are replaced by one placeholder for indexing; reported matches also preserve
the correspondence between repeated uses of those bindings. Operators,
types, literals, members, and global names remain significant. Static
functions remain qualified by their input unit.

The default minimum size is 24 expanded cons cells. Results rank by
`size * (verified occurrences - 1)`, with larger size breaking ties. The
report shows up to 25 groups and eight sites per group. A group is omitted
when every occurrence is contained in an already reported group; the reported
occurrence count still includes sites beyond the eight shown. `span` is a
half-open preorder interval within the named input `unit`, not a byte range.
Unlocated generated roots are excluded from the candidate listing and counted
in `unlocated-root-occurrences`; they remain in the structural counts.
Locations for otherwise unanchored bodies use their first anchored descendant.

`size-distribution` covers every canonical cons cell, including list tails.
Its buckets have inclusive lower bounds 1, 2, 4, and so on, and exclusive
upper bounds at the next power of two. Each reports distinct cells, cells
occurring more than once, and total occurrences. The candidate listing covers
selected syntax roots, so its totals differ from the all-cell distribution.

For example, run over the compiler and runtime, omitting the generated prelude:

```sh
set -- $(tools/sources.sh --area src)
for unit in $(tools/sources.sh --area lib); do
  [ "$unit" = lib/x2c.x ] || set -- "$@" "$unit"
done
builds/0/libexec/x2c-graph clones --min-size 100 "$@"
python3 commands/graph/tests/test-clones.py  # optional experiment checks
```

The [initial experiment results](clones-experiment.md) include measured
storage, timing, the size distribution, and source-checked examples.

This is an investigation aid for macro-expanded, typed syntax. Repetition
introduced by a shared macro can be intentional. Equal normalized fragments
do not prove that extracting a helper preserves lifetime, evaluation context,
or other surrounding obligations. It does not match reordered statements or
arbitrary consecutive statement sequences.
Public bindings are compared by emitted name, assuming consistent project
linkage; this command does not resolve ambiguous public definitions. Generated
names can also prevent a match. This is not a semantic-equivalence proof.

The basic interning pass takes expected linear time in the expanded input
representation. Binding correspondence and report construction are separate
work; their cost is not covered by that claim. Reported storage for the native
cell table is not total process memory: parsing, atom keys, and source records
also consume memory.

### Export datasets

`datasets` writes one node table and two directed edge tables under `OUTPUT`:

```text
functions.tsv
src-calls.tsv
lib-calls.tsv
```

The files are UTF-8 TSV with LF endings, one header, no comments, and rows
sorted by endpoint ID. The files named before `--` receive the `src` label;
those named after it receive the `lib` label. An optional third group after a
second `--` receives the `commands` label; list the source files of external
commands there so that their calls count as callers. This explicit grouping
makes the label independent of checkout paths or symlinks. The `src` and
`lib` groups must each contain at least one source file. Inputs are
canonicalized and deduplicated within each group; one file cannot belong to
two groups. All inputs are parsed and resolved
before the output directory is created, so a missing or malformed input does
not leave a partial dataset.

`functions.tsv` has these columns:

```text
function_id  kind  subtree  unit  file  unit_lines  source_order  source_name  emitted_name  visibility  needed  origin  external_calls  indirect_calls
```

The separators in the actual file are tabs. `function_id` is
`UNIT::EMITTED_NAME`, the canonical endpoint used in both edge files. A line
or column is not part of identity. `kind` is `function` or `top-level`, and
`subtree` is the explicit `src` or `lib` group. `unit` is the input file.
`file` is the file that holds the definition: a member file of a module unit,
or `unit` itself. The exporter takes it from the first source location in the
definition that lies in one of the unit's files. A definition with none, such
as a macro-generated helper, takes `unit`. `unit_lines` is the physical line
count of the unit, including every member file of a module unit.
`source_order` is the one-based order of parsed functions in the unit; the
synthetic top-level caller uses zero.
`source_name` is the name as written in source: an x2c method stays
`Owner.member`, and a file-private static keeps no file prefix. `emitted_name`
is its resolved C name. `visibility` is the storage tier, described under
"Module blocks" in `docs/src/reference/language.md`:

- `static` is private to its file: a static in a single-file unit, or a
  static whose emitted name begins with its file's prefix in a module unit.
- `module` is a static that every file of a module unit sees. It emits with
  no file prefix.
- `public` is a nonstatic definition, which other units can link to.

`needed` is the narrowest of those tiers that reaches every resolved caller
of the definition. It is `static` when every caller is in the definition's
file, `module` when every caller is in its unit, and `public` otherwise. It is
`none` when no resolved call reaches the definition. A `needed` narrower than
`visibility` marks a candidate for narrower storage, not a proof: indirect
references, callbacks, implicit conversions such as `T.var`, calls from
inputs not supplied, and published API are not resolved calls.

`origin` is `source` for a definition written in source and `generated` for
one the compiler or a macro made, such as a class adapter.

`external_calls` and `indirect_calls` count parsed call expressions made by
that function whose target is respectively missing or ambiguous, or computed.
They are counts, not graph endpoints.

Both call files have the same columns:

```text
caller_id  callee_id  static_calls
```

Direction is caller to callee. `src-calls.tsv` contains only `src` to `src`
edges. `lib-calls.tsv` contains every other edge: `lib` to `lib`, those
crossing between `src` and `lib`, and those with a `commands` endpoint. Its
name therefore means the graph containing the library subtree and its
boundaries, not merely calls made by `lib`.
Concatenating the data rows of both files reconstructs the complete resolved
direct-call graph without duplicate edges. `static_calls` is the number of
parsed call expressions aggregated for the endpoint pair after compile-time
macros run. It is useful as a syntactic coupling weight, but it is neither
runtime traffic nor a physical flow capacity.

The synthetic `<top-level>` node keeps calls made by static initializers and
other executable file-scope forms connected to their unit. It is
an ordinary graph node. Calls that do not resolve are retained only in the
two count columns on their caller; the exporter never invents a destination.

To export the compiler and runtime units, this shell example names the
`src` files before `--` and the `lib` files after it, excluding the
generated `lib/x2c.x` prelude, and then the external commands:

```sh
set -- $(tools/sources.sh --area src) --
for unit in $(tools/sources.sh --area lib); do
  [ "$unit" = lib/x2c.x ] || set -- "$@" "$unit"
done
set -- "$@" --
for name in $(cut -d'|' -f1 commands/manifest.txt); do
  set -- "$@" commands/"$name"/*.x
done
builds/0/libexec/x2c-graph datasets /tmp/x2c-datasets -I . -I src -I lib "$@"
```

The compiler driver runs the same command as
`x2c graph datasets OUTPUT [-I DIR] SRC_FILE... -- LIB_FILE... [-- COMMAND_FILE...]`.

### Reading and analyzing the datasets

The direct function graph uses every `function_id` as a node and every row in
the two call files as a directed edge. Use `unit`, `file`, `subtree`,
`visibility`, and `source_order` as node attributes. Begin clustering with one
unit of weight per edge, then compare the result using `static_calls`;
agreement is more informative than treating the syntactic count as observed
execution.

A file graph is derived rather than separately exported. Join each endpoint
to `functions.tsv`, group edges by caller and callee `unit`, and retain both
the number of distinct function edges and the sum of `static_calls`. This
shows wide or reciprocal file dependencies without hiding which functions
participate.

To examine a large source file, select its nodes and the edges whose two
endpoints are both in that unit. Cluster that induced graph without using the
current unit or file label. For a proposed split, report the number of
functions and internal edges in each part, directed edges and summed call
occurrences that cross the proposed cut, and cut edges by callee tier. A cut
edge to a `static` callee needs that callee to become `module` if the parts
become files of one module unit, or `public` if they become separate units. A
`module` callee needs `public` only for separate units. Also list public
functions and sum external and indirect calls in each part. Those facts
distinguish a low graph cut from a move that would require wider storage or
leave important unresolved dependencies unexplained.

For visualization, units and their files work well as nested containers,
discovered communities as colors, visibility as node shape, optional
`static_calls` as edge width, and the proposed cut as highlighted edges.
Network-flow and community algorithms should treat direction deliberately: a
symmetrized graph answers a different question from conductance, directed
modularity, or a caller-to-callee cut.

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
the groups separated by each qualifying bridge function. It then describes
the unit's files: a single-file unit has one, and a module unit has its
member files.

- `members` lists each file with its definitions counted by storage tier,
  its calls within the file, and its `interface`: the definitions that other
  files of the unit call.
- `member-calls` counts the call sites from one file to another.
- `wider` lists written definitions whose storage is wider than their
  `needed` tier, as defined for datasets. Generated definitions are omitted.

Relative unit paths are normalized the same way as graph output. Use this
with `focus NAME` to trace a finding before proposing a move, deletion, or
simplification.

`between` shows the exact resolved calls in both directions between two input
units. Each direction includes its total call count and the sorted caller,
visibility, callee, and aggregated count for every edge. It explains a
reciprocal dependency reported by `architecture`; it does not imply that the
dependency is unnecessary.

`focus` emits the resolved callers and callees for every definition with the
exact emitted `NAME`. Same-named `static` and `module` functions remain
separate and unit-qualified.

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
x2c lowers dot access on a pointer-like receiver to `->`. These restrictions
apply to argument expressions. Two full walkers called as
`first(value); value = replacement; second(value);` can still produce a
candidate. Inspect changes between calls and each walker's state before
deciding whether they can safely be combined.

`tail-calls` reports exact self-calls in return position, their source
locations, other non-tail self-calls in the same function, and explicit
`defer` or `try` cleanup. Either result arm of a returned `?:` expression
preserves tail position; its condition does not. Before rewriting a reported
function, inspect its generated C for argument evaluation, automatic storage,
and cleanup, and check the host compiler's optimization.

`loop-allocations` ranks source expressions that allocate List/String pool or
Scope-backed storage inside parsed loops. It groups macro-expanded allocation
nodes at one source location while preserving their counts. It also follows
project helpers whose every return path uses allocation operations of one
ownership kind; those rows count resolved calls, not allocations made
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
its internal allocation count. A value whose storage would be released with
the Context needs a copy or export to survive it; values already owned outside
that Context do not. Check the actual owner and lifetime in source.

`lifetime-escapes` reports returns that can dangle after an explicit
`Scope` or `Context` ends. It follows direct local aliases, accepts storage moved
with `Scope.move`, and accepts the value returned by `Context.export`. An
ignored export does not establish a safe result. It also follows project
helpers whose every return path uses allocation operations for the caller's
current Scope or canonical-value pool. Static helpers remain local
to their input; a public helper resolves across inputs only when its emitted
name has one definition.

This is deliberately local and conservative. It does not carry facts through
branches, loops, pointer casts, callbacks, field stores, parameter transfers,
or calls without an exact return summary. Mixed return paths, recursive calls
without an allocation base, and implicit conversions between runtime types
remain unresolved. Values passed to unknown or indirect calls also become
unresolved instead of producing a finding. A missing report does not establish
that the code is safe. A reported pooled return may reuse an ancestor's
canonical value, so even a `dangling-return` finding needs source verification.

### Conditional lifetime proof

`certify` audits code reachable from named, uniquely resolved functions and
includes executable file-scope initialization from the supplied units:

```sh
builds/0/libexec/x2c-graph certify --root certify_safe \
  commands/graph/tests/fixtures/certify.x
```

The result is `proved`, `violation`, or `incomplete`. `proved` means the
region walk found no lifetime violation and every reachable operation stayed
within the audit's modeled subset or had a listed effect contract. It is a
conditional proof of scoped ownership, not a claim about arbitrary C memory
behavior. A `violation` includes its call path and source location. An
`incomplete` result lists proof obstacles such as an indirect call, an unknown
native effect, pointer arithmetic or casts, an aggregate copy, or a region
closure the audit cannot establish. Obstacles do not change compiler warnings
or errors. Each violation and obstacle path is a shortest call path from a
root or file scope. Among paths of equal length, the report picks the first
by comparing their targets in order, by path and then name. Returned or
transferred ownership appears under `obligations`.
Calls and allocations inside a branch or loop are checked by the region
walk. A conditional region opening or a close without an unconditional
lexical `defer` remains an obstacle.

The compiler's built-in region effect table supplies runtime operations.
For other native calls, `--contracts FILE` reads Lisp data rows using the
table's existing effect forms:

```text
(native "native_touch" (summary 0 ()))
```

The example assumes `native_touch` has no memory effects. Every used native
assumption is printed in the result. Duplicate rows, invalid effects, and
attempts to override a built-in or source-defined function are rejected.
The file affects this audit only. Exit status is 0 for `proved`, 1 for
`violation`, 3 for `incomplete`, and 2 for invalid input or failed parsing.

The audit recognizes literal `printf` and `File.printf` formats whose
conversions do not write through an argument. Their no-lifetime-effect
summary appears in `assumptions`. A dynamic format, `%n`, or a conversion
outside the supported format subset remains an obstacle unless the project
supplies an explicit contract.

`allocation-returns` reports return expressions in functions with the exact
emitted `NAME` that call allocation operations for the caller's current Scope or
canonical-value pool. Each row names the allocation operation, ownership
kind, and source location. This is the check to run before deleting an
apparently redundant copy: replacing a reported `cons`, `Array.list_free`, or
String constructor with an existing value can change which Context owns the
result even when the values are structurally equal. The command does not
infer indirect helper returns or say that the allocation is necessary; it
identifies operations whose removal may change ownership.
Pooled operations may reuse canonical values; the report does not
prove fresh cells or the actual owner of a particular returned value.

`flows` asks where the value returned by one exact function reaches an
argument of another exact function. It follows direct consumption, local
declarations and assignments, returns, uniquely resolved project helpers,
and the narrow value-preserving wrappers shown in the result. Every proved
path includes exact definitions, source sites, the consumer argument index,
and compact summaries of the other arguments, including position symbols
or constants. Field storage, mutation, branch alias merging, callbacks,
computed calls, and ambiguous calls remain unresolved.
An empty path list means the analysis found no path; a runtime flow may still
exist.

`compare` accepts two exact entry functions and one or more exact target
operations before `--`. For each operation it reports whether both entries,
only one entry, or neither entry has a resolved call path, together with the
shortest path from each side or an explicit unresolved result.

This is a parsed source graph for trusted x2c programs. Parsing executes their
meta functions and macros. Calls introduced only by later transforms,
generated protocol adapters, C-only code, and speculative callback targets
are outside this tool's analysis.

## Reusable project snapshots

`snapshot` retains a configured project's bound, macro-expanded syntax,
semantic relationships, and source text. Each query runs in a new process and
reads saved data. It does not parse live source, execute meta code, or rebuild
anything. `snapshot` itself performs normal compiler analysis, including
compile-time execution. The format remains experimental and requires the
compiler identity that produced it.

```sh
# An explicit set of units, with the ordinary build configuration options.
x2c graph snapshot /tmp/compiler-analysis -I . -I src \
  $(tools/sources.sh --area src)

# A manifest target and its dependency targets, using their own settings.
x2c graph snapshot /tmp/project-analysis \
  --manifest-path /path/to/x2c.toml --target app --profile release

x2c graph status /tmp/project-analysis
x2c graph query /tmp/project-analysis /tmp/query.json
x2c graph diff /tmp/project-analysis /tmp/project-analysis-after
```

The selected manifest target/profile and its dependencies form one snapshot.
Use separate snapshots for other configurations. Explicit inputs form one
analysis set. Module members belong to their entry unit. Native dependencies
and declarations without analyzed implementations remain recorded boundaries.
Snapshot construction does not install packages or build the application;
prepare missing dependencies through the project's ordinary workflow.

`status` checks saved dependency fingerprints and source membership. Its JSON
contains `fresh`, `changed`, `missing`, `added_inputs`, and `removed_inputs`.
It also reports the retained effective target `configurations`, including
include paths, compiler arguments, and native modules.
If an edited manifest cannot be planned, `membership_checked` is false and
`membership_error` explains why; recorded dependency changes are still shown.
Queries continue to read the named snapshot after source edits. Rebuild
explicitly when a current-tree answer is required. A failed rebuild preserves
the preceding snapshot. Inspection returns the saved source, not the current
file contents.

### Query vocabulary

Put one JSON object in the query file. Each result identifies its snapshot and
coverage and includes `results`, `total`, `offset`, `limit`, and `truncated`.
The default limit is 100. Continue with `offset` when results are truncated;
ranking or a first page is not an exhaustive reference inventory.

| `op` | Inputs | Result |
| --- | --- | --- |
| `find` | `where` | Matching entity summaries. |
| `inspect` | `select`, `view` | One entity's summary, declaration, source, or typed AST. |
| `traverse` | `select`, `relations`, `direction`, `depth`, `where` | Reachable entities with distance and the edge that reached each entity. |
| `path` | `select`, `target`, `relations`, `direction` | A shortest path with entities and occurrence evidence. |
| `match` | `pattern`, optional `select` and structural filters | AST matches, captures, enclosing entity IDs, and available locations. |

Selectors use entity attributes such as `id`, `name`, `kind`, `unit`, or
`domain`. An ambiguous `inspect` returns candidates with status `ambiguous`;
select one exact ID instead of guessing. Names of local functions and types
can repeat. A typedef and its aggregate tag are also distinct entities.

`where` supports exact entity attributes, `text` substring search, and
`all`, `any`, and `not` combinations. `reachable_from` takes a traversal
configuration containing `select`, `relations`, `direction`, and `depth`.
`direction` is `out` or `in`; omitted depth traverses the recorded closure.
Traversal includes selected roots at distance zero.

Relationship kinds include `calls`, `references`, `contains`, `aliases`,
`field-value`, `field-pointer`, `parameter`, `result`, `callback`, `body-type`,
`reads`, `writes`, `mutates`, `representation`, `conforms`, `implements`,
and `delegates`.
Fields have their own identities: field-to-type edges distinguish value
storage from pointers, and function-to-field edges record accesses. A pointer
edge does not establish ownership. A field write does not include arbitrary
writes through aliases or callees.

### Questions to ask

The function names below come from the acceptance fixture. To try these
queries against that fixture, build its snapshot first:

```sh
x2c graph snapshot /tmp/example-analysis \
  commands/graph/tests/fixtures/snapshot-a.x \
  commands/graph/tests/fixtures/snapshot-b.x
```

Use `/tmp/example-analysis` as the snapshot argument for the JSON examples.
Replace selectors with the names or IDs returned for your own project.

Find the entry point, then inspect its saved definition:

```json
{"op":"find","where":{"kind":"function","name":"snapshot_entry"}}
```

```json
{"op":"inspect","select":{"id":"ID_FROM_FIND"},"view":"source"}
```

`view` also accepts `summary`, `declaration`, and `typed_ast`. `declaration`
returns canonical declaration syntax, including its type and bindings.
`typed_ast` returns the full bound subtree in the `ast` result field, with
portable source-origin wrappers. Use `source` for the original source text.
File entities return their complete saved source. Unit entities retain the
complete bound AST, including top-level forms outside declaration subtrees.
Select a unit explicitly to match that entire AST. Without `select`, matching
searches declaration subtrees to avoid repeating their unit-level copies.

Find callers, transitive callees, and a source-evidenced path:

```json
{"op":"traverse","select":{"name":"snapshot_leaf"},"relations":["calls"],"direction":"in"}
```

```json
{"op":"traverse","select":{"name":"snapshot_entry"},"relations":["calls"]}
```

```json
{"op":"path","select":{"name":"snapshot_entry"},"target":{"name":"snapshot_leaf"},"relations":["calls"]}
```

Find public interfaces that use a type: select its exact type ID, traverse
`parameter`, `result`, and `callback` in reverse, and retain public functions.
Starting from a type, reverse `field-value` and `field-pointer` to distinguish
embedding from indirection.

```json
{"op":"traverse","select":{"id":"TYPE_ID"},"relations":["parameter","result","callback"],"direction":"in","where":{"all":[{"kind":"function"},{"visibility":"public"}]}}
```

Find reachable direct field writes by following calls and writes together:

```json
{"op":"traverse","select":{"name":"snapshot_entry"},"relations":["calls","writes"],"where":{"kind":"field"}}
```

To restrict that answer to one type, first find its fields through `contains`
and use their IDs in an `any` filter. To return the reachable functions that
directly write those fields, reverse the write edges and intersect callers:

```json
{"op":"traverse","select":{"any":[{"id":"FIELD_ID"}]},"relations":["writes","mutates"],"direction":"in","depth":1,"where":{"all":[{"kind":"function"},{"reachable_from":{"select":{"name":"snapshot_entry"},"relations":["calls"]}}]}}
```

To find functions requiring a type's
representation, traverse `representation` in reverse from the type. Inspect
the `via` evidence before concluding that making the type opaque is safe.

```json
{"op":"traverse","select":{"id":"TYPE_ID"},"relations":["representation"],"direction":"in","where":{"kind":"function"}}
```

Structural patterns use the existing Match grammar as datum text. Test a
pattern on one selected entity before omitting `select` to search all saved
ASTs. Provenance wrappers do not obstruct ordinary matching. `inside` accepts
`loop` or a canonical AST head. Binding filters refer to resolved names or IDs. `callee` restricts that
filter to a call target, while `binding` considers the matched subtree.
Type filters use canonical datum text.

`node_where` composes structural filters with `all`, `any`, and `not`.
For example, this selects loop calls to either named function while excluding
calls with a double argument:

```json
{"op":"match","pattern":"(expr ?type (call ?callee (args *args)))","node_where":{"all":[{"inside":"loop"},{"any":[{"callee":"snapshot_leaf"},{"callee":"snapshot_middle"}]},{"not":{"argument_type":"(double)"}}]}}
```

Top-level structural filters remain conjunctions. Entity `where` filters the
enclosing entity; `node_where` filters each matched AST node.

```json
{"op":"match","select":{"name":"snapshot_entry"},"pattern":"(expr ?type (call ?callee (args *args)))","inside":"loop","callee":"snapshot_leaf","argument_type":"(* struct \"SnapshotValue\")"}
```

Matches return captures rather than evaluating query code. Available filters
also include `declared_type`, `resolved_type`, and `where` with
`reachable_from`. Declarations and resolved types remain separate so an alias
or pointer wrapper does not disappear from the question being asked.

Build a second snapshot after editing, then use `diff` to inspect changed
signatures, field relationships, or calls. Diff reports `added`, `removed`,
`changed`, `added_relations`, and `removed_relations`. It matches qualified
identities rather than compiler binding numbers and does not guess renames.

### Coverage and interpretation

A path proves a relationship in the saved analysis. `no-recorded-path` does
not prove that no runtime path exists. Indirect calls, native bodies, alias
mutation, and later-transform behavior remain outside these direct facts.
Protocol and delegation relationships come from compiler records; they do not
justify speculative dispatch targets.

Source-written and generated entities are marked separately. Constructed ASTs
can lack exact source spans. Queries preserve that absence rather than invent
locations. A syntax or type match establishes the reported shape and compiler
facts, not execution feasibility, ownership, or safe deletion.

The focused acceptance command is:

```sh
python3 commands/graph/tests/snapshot.py
```
