# Heap allocation and heap objects in meta functions

> Status: needs author scoping. Written 2026-09-23 against dev `0bdc8398`.
> Gary asked for this follow-up after `Scope.malloc` was found unbound at
> compile time. Three choices at the end need his decision before
> implementation.

## Result

A meta function can allocate, resize and free heap memory with the Scope
allocator, exactly as C code does:

- `Scope.malloc`, `Scope.calloc`, `Scope.memdup`, `Scope.realloc` and
  `Scope.free` are callable from meta bodies.
- A heap type's constructor that calls only these and other meta functions
  can itself be marked `meta`. Compile-time code can create such objects,
  read and write their fields, pass them between meta functions, keep them
  in `meta static` values, and free them.
- Misuse that the shared region pass can see (use after `free`, use of a
  pointer after `realloc` moved it, freeing a local's storage) is rejected
  in meta bodies and warned about in ordinary code.

## Current behavior

- A meta body that calls `Scope.malloc`, `Scope.calloc` or `malloc` fails
  with "this function cannot run at compile time: no binding for
  Scope_malloc" (probes on `0bdc8398`). None of these is marked `meta`, so
  no compile-time target is generated (`src/macros.x:556-577`). A `meta`
  prototype written in user code does not help: the target must be compiled
  into the compiler.
- `sizeof` does not lower in meta bodies ("unsupported expression"), although
  every size it needs is in `meta_type_layout` (`src/compiler.x:3965`).
- A `void *` result arrives as a `<p48>` pointer. Through a probe native
  module standing in for the missing bindings, `(struct Foo *) p` with
  `p->x`, `Foo p` with `p.x`, a meta constructor and a meta method on a heap
  typedef all work (track C made field access through real native pointers
  work).
- An ordinary call to a function with a pointer result is applied at
  compile time and then kept (`src/comptime.x:2903`), so a constructor with
  side effects would run during compilation for every ordinary call site.

### Where the memory goes

There is no per-application Scope that frees heap memory. Each evaluator call
creates a "Lisp frame" Scope (`lib/lisp.x:2165`), but it is never made the
current Scope. It owns only the bindings Map and, for lowered source
functions, the bytes of address-taken and struct locals (`:2176-2179`,
`:1113-1119`). The current Scope during a meta call is the unit's Lisp
session Scope, pushed at entry (`lib/lisp.x:684`) and destroyed with the
unit's compiler (`src/compiler.x:250-256`), or with the REPL session.

So `Scope.malloc` in a meta body allocates in the session Scope and lives
until the unit ends. That matches C: the outermost caller's active Scope owns
the allocation. A probe confirmed it: memory allocated in one `$f1()` call and
kept in a `meta static` was readable in a later `$f2()`, and its owner was
`*Scope.top()`.

This means `free` is not implied; it is optional, as in C. Making the frame
the current Scope would free every object a constructor returns. The rejected
recovery design hit this problem (`plans/archive/meta-recovery-design.md`,
lines 236-256).

`Scope.free` unlinks a block from whichever Scope owns it (`lib/scope.x:
886-891`). `Scope.realloc` keeps the block's owner and list position, and any
other pointer to the old block dangles (`:953-1000`). A double free, or a
pointer that did not come from a Scope allocator, is undefined, as in C.
Evaluator bytes (`lisp_bytes`, returned records, `meta static` values) are
ordinary Scope blocks, so `Scope.free(&local)` would also "succeed" and leave
the evaluator's slot pointing at freed memory.

## Constraints from earlier decisions

Gary rejected a meta-record wrapper with an allocation tracker, and a
hardcoded native bridge (`plans/archive/meta-values-types.md`,
`meta-recovery-review.md`). This design therefore keeps objects in native
bytes, adds no tracker or second registry in the evaluator, and adds no
blanket redirection of native allocation. Bindings come only from `meta`
declarations. Lifetime checks come only from the shared region pass in
`src/regions.x` (track F).

## Design

### 1. Bindings

Add bodyless `meta` prototypes for `Scope.malloc`, `Scope.calloc`,
`Scope.memdup`, `Scope.realloc` and `Scope.free` in `lib/scope.x`. The
existing native meta path generates their targets and binds them on first
use. Allocations land in the Scope current during the call, which is the
session Scope.

Left unbound, with the reason recorded in the book:

- `Scope.retain`, `release`, `push` and `pop`: `defer` is rejected in meta
  bodies, so a raise between a push and its pop would leave the session
  Scope's stack changed.
- The `*_in` variants and `malloc_finalized`: they need a named slot or a C
  function pointer that compile-time code cannot supply.
- Plain `malloc`, `calloc`, `realloc` and `free`: their memory has no owner
  and would leak for the life of a compiler worker. The Scope functions cover
  the same uses.

A new native target needs the two-round rule: the prototypes and a bootstrap
refresh land before any `lib/` code calls these functions at compile time.

### 2. `sizeof` in meta bodies

Lower `sizeof(type)` and `sizeof expr` to the constant size from
`meta_type_layout`, or from the scalar ledger for scalar types. A type with
no layout declines plainly, as field access already does. `_Alignof(type)`
does not parse at all yet; that parser gap is a separate follow-up.

### 3. Folding

Before applying an ordinary call at compile time, check its declared result
type. When the result is a pointer that cannot be materialized, keep the call
without running it. This stops constructors from running during compilation
for ordinary call sites, and removes wasted work for any other
pointer-returning function.

### 4. Lifetime checks in the shared region pass

Extend `src/regions.x`; add nothing to the evaluator.

- `Scope.realloc` gets its own row: the result is an allocation in the
  argument's owner region, and the argument ends. A later use of the old
  pointer is then a use after free.
- `Scope.free` of frame storage, meaning the address of a local or of a
  struct local, is an escape of the frame region that track F added.
- Use after `free` through an alias is not tracked, as in C; the book says
  so.

As with track F, a finding in a meta body is an error and the function is
not installed; ordinary code gets the same finding as a warning.

### 5. Heap classes

Heap-based x2c objects come in three tiers:

1. **Layout objects.** With parts 1-4, a heap class (`class X struct {...}
   *;` or `typedef struct X {...} *X`) works at compile time through its
   layout. Its constructor and methods can be `meta`, its fields can be read
   and written, and pointers can be compared and stored. No Var boxing is
   involved.
2. **Classes built into a native module.** These already work fully: loading
   the module runs its file initializer, which registers the class, so
   boxing, `str` and Arrays of the class work (probe: `4 vec Vec(4,0)`).
3. **Classes defined in the unit being translated, boxed as `Var` in meta
   code.** Today this fails with `(bad-target (owner "Var.new") (target
   vec))`, because the class is registered only when the compiled program
   starts. This tier needs Gary's decision (question 3).

### 6. Materialization

A heap pointer is not written into generated code. Explicit `$` insertion of
one is diagnosed, as today. An ordinary call is kept without running (part
3). Rebuilding a runtime constructor call from the arguments would repeat the
construction and could not reproduce object identity, so it is out of scope.

## Deliveries

1. **Capability.** The prototypes in `lib/scope.x`, `sizeof` lowering, the
   folding rule, the region rows, the book's Lifetime section and its `defer`
   row (both currently say freeing is unavailable), fixtures, and a bootstrap
   refresh. Fixtures cover a constructor-style meta function whose object its
   caller reads; `realloc` growth; `sizeof`; and rejections for use after
   `free`, use of the old pointer after `realloc`, and freeing a local.
2. **Adoption.** Mark `meta` the constructors that need nothing more than
   delivery 1: `Point.new` (`examples/love/methods.x`), `Index.new`
   (`examples/power/indexing.x`), `Greeting.new` (`examples/packages/greet`),
   `AdTape.new`, `MachineBuilder.new`, `DisjointSet.new`, and cstar's
   `Adapter.new`. `Buffer.new`, `Block.new` and constructors that open native
   resources (`Mutex.new`, `CurlEasy.new`, `UvLoop.new`) stay ordinary.
3. **Tier 3,** as Gary decides.

Each delivery ends with a review and repair of its authored diff, then
`tools/gate-state.py ensure agent-pr-check`.

## Decisions for Gary

1. **Ownership.** Allocations go to the session Scope, which is C's answer,
   and there is no per-application Scope for heap memory. Recommendation:
   yes. A per-application current Scope would free every constructor's
   result.
2. **`free` and `realloc`.** Bind both with C semantics, relying on the region
   pass extensions in part 4 and no evaluator tracker. Recommendation: yes.
3. **Tier 3 boxing.** Options:
   - (a) When meta code first boxes a unit-defined class, register a
     tag-only class in the compiler process. Identity, equality and hashing
     work, and `str` falls back to the pointer form. The rows are
     process-wide and persist across the units a worker translates; 27 are
     free today, and running out would need a clear diagnostic.
   - (b) Also lower the class's `meta` Var methods (`str`, `equal`, `hash`)
     and register a descriptor that calls them. More complete, but a larger
     change to class registration.
   - (c) Decline boxing with a plain diagnostic that points to native
     modules, until lazy class registration (track G's follow-up) makes rows
     reclaimable per unit.

   Recommendation: (c) in delivery 1, then (a) together with reclaimable rows.
   Tiers 1 and 2 already cover heap objects at compile time without boxing.

## Plan review

- **Facts established elsewhere.** The native meta path establishes each
  target and its signature. The Scope allocator establishes ownership; the
  session Scope is current because `lib/lisp.x:684` pushes it. Layouts from
  `meta_type_layout` establish sizes. The region pass establishes lifetimes.
  No consumer rechecks these facts, and the evaluator adds no validator.
- **Reuse and deletion.** Everything reuses existing machinery: `meta`
  prototypes, the native target generator, layouts, native pointer access
  from track C, and track F's region pass. New lasting pieces are the
  `sizeof` lowering, one folding condition, and two region-pass rows.
- **Idiomatic x2c.** Constructors stay ordinary x2c functions marked `meta`.
  Nothing wraps objects or tracks allocations.
- **Validators, diagnostics and negative fixtures.** The new rejections come
  from the shared region pass and protect the compiler from use-after-free
  crashes in meta bodies, which are unsafe native crossings. The tier 3
  diagnostic replaces a confusing `bad-target` failure.
