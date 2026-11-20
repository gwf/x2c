# Writing a good x2c app

Write the shortest program that makes the work, the data, and its lifetime
clear. Start with a working example that does the same kind of work. Use the
[example manifest](../examples/manifest.txt) to find one and see how it is
checked. Use the [library module reference][library] to find the primary
operation before writing your own. The [idioms guide][idioms] explains the
language choices below. The [code standard][standard] gives the repository
rules and links to worked examples.

## Make the program read in the order it works

- Start with the app's main path. Show what it reads, what it does, and what
  it produces. Use guard clauses for exceptional branches and keep the
  ordinary path together. Keep each function at one level of detail. Use an
  expression body for a single expression and name a helper when its name
  tells the reader something the inline code does not.
- Put public functions first and introduce private helpers after their first
  users, grouped by responsibility. Use `static` for private definitions.
  Use `Type.method` for operations the type owns. Give one concept one name.
  Pass a context record when several operations share the same state and
  lifetime. Keep unrelated arguments independent.
- Match the surrounding source form. In this repository, use two-space
  indentation, the 79-column budget, and compact guards and dispatch arms.
  Comment a lifetime, invariant, or surprising contract beside its owner.
  Delete comments that translate the next line into English.
- Split modules where responsibilities divide. A local `.x` include exposes
  declarations and compile-time definitions. Link the implementation unit
  in the build. Use package imports for registered dependencies and pin
  project dependencies when the app needs a reproducible build.
- Avoid forwarding layers, parallel representations, and services that
  exist only to call the next service. Reuse the operation that already owns
  the behavior. Remove redundant work before extracting helpers. Preserve
  the behavior at every caller when removing a wrapper.

See [From C to x2c][from-c], the [package guide][packages], and the
[shape rules][standard].

## Let the type and the collection say what the data is

| Need | Use |
| --- | --- |
| Known number, enum, record, or native handle | The native type |
| Local state with value semantics | A value record, updated through `T &` |
| Shared or retained identity | A pointer or pointer-form class |
| Heterogeneous values or a dynamic boundary | `Var` |
| Immutable sequence or structural sharing | `List` |
| Mutable indexed sequence or lookup by key | `Array` or `Map`, respectively |
| Repeated text assembly | `Buffer`, then convert to `String` |
| Closed vocabulary or ordered dispatch table | `Symbol` or `SymbolSet` |
| Interned names from an open vocabulary | `Atom` |

Name the owner of retained storage. Check the tag before extracting a
value from mixed or external `Var` data. Use `class` when the generated
methods serve the type. An ordinary record
works for a context that only needs fields and a few helpers. Use a protocol
when each participating type can satisfy the same contract. A private
record can adopt `Var(T)` beside its conversions and stay private. Avoid
boxing known values early, publishing types to make an internal collection
work, and casting over a type mismatch. Let a typed destination request an
established conversion.

Use native literals. In `%(...)`, `%[...]`, and `%{...}`, unadorned names
are quoted data. Use evaluated Array and Map literals when elements come
from expressions. Use `match` for nested shapes and alternatives, flat
destructuring for a trusted small positional result, and a named record
when fields have their own meaning. Validate external shapes at entry and
pass the resulting typed value onward.

Use `foreach` for sequential work or early exit, a small collection
transform for a direct mapping or reduction, and `Iter` when a pipeline
must stream. Keep lambdas local and small. Captures are snapshots unless
the lambda shares a binding with `using &name`. Use a noncapturing lambda
or a named function at a native function-pointer boundary. Bind a reused
result once. Avoid long chains that hide mutation or repeated traversal.

See [values][values], [collections][collections], and
[patterns](../docs/src/guide/match.md).

## Put ownership, cleanup, and failures where they belong

- Choose the owner and lifetime before allocating. A reference borrows a
  live object for a call. Use `T &?` for an optional borrow or output and
  check presence. Copying a record copies its handles, so the copy can
  still share a container or native pointer. Keep one owner for an active
  transaction, builder, or native resource.
- Put cleanup beside acquisition. Use initializer `auto` for an owned
  resource with a `Cleanup` operation, an `auto` block for a region, and
  `defer` for native release or another explicit cleanup action. Initializer
  `auto` retains the acquired value for cleanup. Declaration `auto` reads
  the variable at exit. Use `with` for temporary replacement and `$lock`
  for a scoped Mutex hold.
- Keep a result in storage that survives its use. Move mutable containers
  with their `move_to` operation when the destination owns them. Moving
  the outer allocation alone can leave backing storage behind. Apply the
  pool rules to canonical values created inside a temporary pool. Fix
  ownership when a region warning finds an escape. A quiet compiler still
  leaves raw pointers and foreign allocations to the app.
- Use `try_get`, `try_next`, and other status-bearing operations when a
  value can also mean absence, exhaustion, or parse failure. Raise one
  structured Error for a failure that must travel to a handler. Catch it
  where the app can recover, translate, or report it. Install cleanup in
  every owning frame on that path. Catch within a native callback before
  returning through C.
- Check external input and documented failure cases at their boundary.
  Avoid downstream checks for facts a constructor or successful operation
  already established. Avoid a second error after a nonreturning raise.
  Keep the full Error context through the application reporting boundary.
- For concurrent work, choose the owner of each mutable object and choose
  whether a message copies, borrows, or hands off storage. Follow the
  Channel close and drain contract and account for worker failure. Avoid
  assuming a send extends a borrowed value's lifetime or makes shared
  mutation safe.

See [regions][regions], [storage ownership][ownership], [errors][errors],
and [channels][channels].

## Use compile-time features to remove repeated source

Start with a function for runtime work. Use a macro when several sites need
the same source form and the invocation explains the result. Use a
decorator for a transformation of one declaration. Derive record mappings
when a single declared schema can own the field names and conversions.
Keep shared macros beside the types or operations they serve.

Give macro holes the narrowest applicable syntax kind. Read free names at
the expansion site. Use `using name` to keep an intended file-scope
binding and `using $name` for a fresh generated name. Check evaluation
count when a hole can contain a call or mutation.

When a compile-time algorithm builds code, write it in `meta` x2c and
show the resulting source with a named template or a `$!` quotation.
Use Lists for patterns, data rows, and forms without a source spelling.
Avoid building ordinary code from strings or raw node tags. Keep the
definition, imports, and resulting declarations in the cost of a macro.
An elaborate generator for a few tokens usually makes the app harder to
read.

See [macros][macros], [code generation][generation], and
[record mappings][derive].

## Build an interface with x2cui

- Start with [counter.x][counter]. Open the window with
  `App app = auto App.open(...)`, loop on `app.frame()`, and get the
  frame's `Ui` from the app. Use x2cui's component calls, named options,
  and container blocks. Let each block show the same hierarchy the user
  sees. Draw on one thread. Reach for raw CUI when the x2cui surface lacks
  the operation.
- Keep application state across frames and pass it to a draw function that
  takes a `Ui`. Apply button and selection results to that state. Keep
  domain operations in their owners, away from layout code. Follow
  [orders.x][orders] for table state and [todo.x][todo] for an editable
  list. Use stable record keys for repeated items that can move, filter,
  or sort. Avoid using the visible index as identity in those views. Keep
  persistent edits out of a frame-local `auto` region. Apply removals
  after the iteration that reads the collection.
- Give constant native record data to components as literal rows where
  their API accepts them. Use x2cui's typed collections for retained or
  writable CUI records. Grow or change them between frames or after the
  component call. Reacquire element pointers after growth. Use the
  package's text and input objects where components require writable
  storage. Use the data grid when a large table should draw only the
  visible range.
- Draw the same function through `Offscreen` for a repeatable screenshot.
  Let several frames settle before saving the PNG. Drive input between
  frames to check transitions where useful. Read the package's platform
  profile before choosing a native build and exercise real window behavior
  where the app depends on it. The package is experimental. Check its
  accessibility and text-input limits against the app's requirements.

See the [x2cui guide][ui] and [package reference][ui-package] for forms,
options, ownership, and build profiles.

## Verify the app through its entry point

- Use `x2c run main.x -- argument` for a small program and
  `x2c build -o app main.x helper.x` for an executable with local units.
  Use the project's manifest and target when it has one. Use `x2c test`
  for the project's tests. Check the actual result and the relevant
  absence, failure, or cleanup path through the same public operation.
- Check the [CLI reference][cli] for supported flags. If a conversion,
  protocol, or macro surprises you, reduce the case and inspect the
  translation. Use `--dump-conformance` to inspect protocol participants.
  Fix source or the build configuration where it owns the problem.
- In a checkout, [lint][lint] points out mechanical idiom violations and
  review candidates. [Graph][graph] can trace callers and dependencies
  before an owner changes. The [REPL][repl] can explore library values and
  methods. These commands are experimental checkout tools built by
  `make commands`. Read findings against source and verify any change
  through the app. Leave generated C to the compiler.

## Consider these optimizations only on a measured hot path

First remove unnecessary work with ordinary x2c. Profile a representative
workload and compare the same work before and after with the same build
options and verified results. Consider a small set of departures:

1. Use packed typed collections or native arrays for a dense measured
   kernel. Keep values unboxed and conversions outside the loop. Use raw
   indexing only under a bounds contract the kernel already establishes.
2. Reuse or preallocate scratch storage when profiling shows allocation,
   boxing, or copying dominates. Keep the scratch owner and its reset
   point visible. Preserve the lifetime and thread ownership contract.
3. Keep a native inner loop or adjust helper boundaries when generated C
   and measurements identify call, dispatch, cleanup, or stack costs. A
   cold error helper can let a tiny hot helper inline. Keep cleanup
   equivalent on every exit and check maximum depth if changing recursion.

Record the workload, baseline and candidate measurements, units, and the
reason for any unusual code beside it. Keep idiomatic code when the benefit
does not justify the added contract. See the [hot-path rules][hot-paths].

[library]: ../docs/src/library/modules/index.md
[idioms]: ../docs/src/guide/idioms.md
[standard]: x2c-code-standard.md
[from-c]: ../docs/src/guide/from-c.md
[packages]: ../docs/src/guide/packages.md
[values]: ../docs/src/guide/values.md
[collections]: ../docs/src/guide/collections.md
[regions]: ../docs/src/guide/regions.md
[ownership]: ../docs/src/guide/storage-ownership.md
[errors]: ../docs/src/guide/exceptions.md
[channels]: ../docs/src/guide/channels.md
[macros]: ../docs/src/guide/macros.md
[generation]: ../docs/src/guide/generating-code.md
[derive]: ../docs/src/guide/deriving-records.md
[counter]: ../packages/x2cui/examples/counter.x
[orders]: ../packages/x2cui/examples/orders.x
[todo]: ../packages/x2cui/examples/todo.x
[ui]: ../docs/src/guide/x2cui.md
[ui-package]: ../packages/x2cui/README.md
[cli]: ../docs/src/reference/cli.md
[lint]: ../commands/lint/README.md
[graph]: ../commands/graph/README.md
[repl]: ../commands/repl/README.md
[hot-paths]: x2c-code-standard.md#hot-paths
