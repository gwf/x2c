> Status: active
> The private-context batch merged into dev in PR #76.
> Public follow-ups are underway on `codex/value-reference-public`, based on
> dev `cbea8c089`. Delivery is another PR targeting `dev`; integration belongs
> to the integration agent.

# Value declarations and reference parameters

Prefer values for records whose identity and lifetime belong to one operation.
Pass a required caller object through `T &`, an optional object through
`T &?`, and a small read-only record by value when a copy is appropriate.
A pointer representation remains appropriate for retained identity, buffers,
arrays, nullable links, native interfaces, and callbacks.

## Implementation

The initial EditState change converts its 35 private receivers to references.
Its declaration and sole local were already values; buffers and terminal
behavior stay the same. Direct and real-terminal probes passed.

Apply the same convention throughout private synchronous compiler, runtime,
and command contexts, including pointer typedefs that only alias local record
storage. Collapse separate storage/address locals. Keep parent pointers in
nested contexts when both contexts must mutate the same record. Trace all
consumers of each owner rather than replacing pointer text indiscriminately.

The survey found 53 compiler value owners with 362 pointer receivers, plus
Emitter and region Walk's 122 receivers; 15 private runtime owners with 183
receivers; and command contexts Lowering, Lifetime, and CloneIndex. Further
private outputs and package/example contexts are included when their caller
contracts establish a single synchronous object.

Support `void T.init(T &, ...)` for value classes alongside the existing
`T *` spelling, using the same constructor generator. This permits the
preferred style through construction without breaking existing initializers.
Keep the heap class's handle receiver and failure behavior unchanged.

Update the coding style guide and book together: declaration representation
does not dictate storage location; value construction needs no allocation for
the record; reference methods borrow caller storage; copying a record does not
deep-copy owned fields. Omit redundant `struct` in class record declarations.

The follow-up batch traces and migrates SymTxn's nullable commit/rollback and
allocation, Job's embedded Launch, MachineBuilder and MatchMachine, and
raylib's foreign aliases. It preserves actual shared identity and documents
the source and generated-header migrations below.
Intentional pointer fixtures and native ABI declarations are not style targets.

## Private-context batch (merged in PR #76)

- Compiler: 55 private context owners, 488 receiver definitions, and 17
  single-record helper parameters. Emitter and region Walk now declare values;
  nested contexts retain their genuine parent borrows.
- Runtime: 17 private owners, including JSON, matching, regex, formatting,
  tokenizer, Lisp, diff, and argument parsing. Four hidden pointer typedefs
  become values. Split outputs use required references; decimal scan keeps its
  optional no-output path.
- Commands: Lowering, Lifetime, CloneIndex, REPL rendering, paste storage,
  byte outputs, and graph's optional call-argument output use value/reference
  declarations. Backing storage and nullable cleanup links remain pointers.
- Packages and examples: Cstar Adapter and Options lose their record
  allocations; libcurl frame helpers and termbox signal helpers borrow values;
  literate Lisp and the recursive matcher oracle use value contexts. Three
  numeric protocol example classes become values instead of allocating records.
- Class constructors accept required reference initializers and still accept
  legacy pointer initializers. The existing lifetime fixture now exercises
  zeroed reference initialization; layout fixtures retain pointer compatibility.
  The existing wrong-receiver diagnostic advertises the preferred reference.
- The style and organization guides and book describe the same preferred
  convention. Generated API pages and LLM text are regenerated from owners.

Independent source reviews checked the stored parent/capture borrows and
reference forwarding. A second pass removed remaining address-only scaffolding
and found the Cstar Options allocation. No additional private context migration
is known from the screened source; this is not a proof that every remaining
pointer in every fixture, callback, native library, or unseen client is needed.

The PR branch incorporates dev's newer Buffer-based REPL renderer, template,
header partitioning, and region changes. Its removed RenderBuffer stays removed;
four newly added private compiler receivers follow the same reference style.

## Focused evidence and remaining coverage

Fresh compiler builds and a warning-free self-host stage pass. Runtime checks
pass 343 tests and 5,517 assertions across 19 relevant suites; the matcher
oracle passes 59 tests and 889 assertions. Command checks, including the REPL's
PTY behavior, pass. Changed curated examples preserve their recorded output.
libcurl and termbox native tests and applications pass on this macOS host.
The class initializer probes cover zeroing, construction, boxing, arrays,
pointer compatibility, and unchanged heap refusal without leaked allocation.

Cstar's first batch built its archive and tool and compared old/new Adapter
rendering and rejection. Its `--emit` path failed before Adapter with unbound
`x2c.function.body`, including on the original tool. The follow-up found the
missing `Frontend.preload_macro_libraries` call used by the other compiler
clients. Restoring that call makes `--emit` and the absolute-value proof pass;
the package's full verification is being checked.

## Public follow-up batch

- SymTxn becomes a value returned by `begin_semantic_transaction`; its saved
  maps retain their Scope lifetime. Required references mutate that one
  transaction. Optional commit/rollback references preserve absent-input
  no-ops, and the zero value is inactive. REPL rollback, completion, map
  identity, and transient-Scope teardown pass the existing command API test.
- Job retains its shared pointer representation, boxing, and Scope finalizer.
  Launch becomes an embedded value, removing its separate allocation; launch
  helpers borrow it through references. Rebuild clients against the changed
  generated Job layout; direct pointer access to `job.launch` becomes value
  access.
- MachineBuilder becomes a plain value typedef with reference operations.
  Its new/free calls and lexical `$auto` remain. Generated class boxing,
  equality, and hashing are removed because no caller uses them. Copies share
  buffer ownership, so use references for an active builder. The Cleanup
  protocol requires a value receiver; its inline adapter releases only the
  two backing pointers and avoids copying the binder array.
- MatchMachine's existing stack state becomes a value typedef with reference
  receivers. MatchLower and MatchWalk retain real parent borrows, and native
  callbacks still receive addresses. MachineProgram keeps its immutable shared
  allocation and handle representation.
- All 23 raylib Image mutator aliases use required references. They remain
  direct aliases of the original Image-pointer C functions; pointer callers
  supply `*image`. Package tests cover every mutator and preserve PNG hashes.

These are source-facing x2c representation migrations. SymTxn's return ABI,
MachineBuilder's record construction, and Job's field layout change; compiled
clients must rebuild with their matching generated headers and runtime. The
pinned foreign C interfaces do not change.

## Verification and delivery

Workers use isolated worktrees rooted at the same checkpoint. Each builds a
fresh compiler and exercises its changed contexts with focused checks. The
orchestrator reviews and combines authored patches, compiles the new book
samples, runs command integration checks and the existing final
`tools/gate-state.py ensure agent-pr-check`, and reviews generated artifacts.
No recurring check or gate is added by this campaign.

Publish the validated branch and open a draft PR targeting `dev`, as Gary
authorized. Integration belongs to the integration agent, not this campaign
worker.

## Plan review

Declarations and traced call chains establish required objects and synchronous
lifetimes. References reuse ordinary typing and lowering; consumers add no
second validator. Value types delete address aliases and unnecessary record
allocation where present. Actual shared borrows remain explicit pointer fields.
The class initializer change reuses its existing signature check and constructor
owner. It adds no new diagnostic or validation mechanism. Focused positive and
compatibility probes cover its new accepted signature and existing behavior.
