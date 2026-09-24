# Heap allocation and heap objects in meta functions

> Status: obsolete
> Superseded on September 24, 2026 by piece 4 of the
> [explicit meta campaign](explicit-meta-and-lifetime-campaign.md), which
> delivered meta heap allocation, `sizeof`, typed heap objects and heap region
> facts (`d0476fe1`, `a9e9ba5d`). The scoping choices below were not taken.

## Result

A meta function can allocate, resize and free heap memory with the Scope
allocator, as C code does:

- `Scope.malloc`, `Scope.calloc`, `Scope.memdup`, `Scope.realloc` and
  `Scope.free` are callable from meta bodies.
- A heap type's constructor that calls only these and other meta functions
  can itself be marked `meta`. Compile-time code can create such objects,
  read and write their fields, pass them between meta functions, keep them
  in `meta static` values, and free them.
- Misuse that the compiler can see is rejected in meta bodies and warned
  about in ordinary code. Misuse it cannot see behaves as in C, with one
  difference that matters: it happens inside the compiler (see "Misuse").
- Generated code stays deterministic: no heap address reaches it.

## Current behavior

- A meta body that calls `Scope.malloc`, `Scope.calloc` or `malloc` fails
  with "this function cannot run at compile time: no binding for
  Scope_malloc" (probes on `0bdc8398`). None of these is marked `meta`, so
  no compile-time target is generated (`src/macros.x:556-577`). A `meta`
  prototype written in user code does not help: the target must be compiled
  into the compiler.
- `sizeof` does not lower in meta bodies ("unsupported expression"), although
  every size it needs is in `meta_type_layout` (`src/compiler.x:3965`).
- A `void *` result arrives as a `<p48>` pointer. With a probe native module
  standing in for the missing bindings, `(struct Foo *) p` with `p->x`,
  `Foo p` with `p.x`, pointer indexing, a meta constructor and a meta method
  on a heap typedef all work. Array, Map, `const char *` and `int *` fields
  of a heap object work too.
- A `meta` function called with constant arguments is applied at compile time
  (`fold_meta_call`, `src/comptime.x:2903`). When its result is a pointer
  the call is kept, but only after the function has run: a constructor ran
  twice during compilation for two call sites.

### Where the memory goes

There is no per-application Scope that frees heap memory. Each evaluator call
creates a "Lisp frame" Scope (`lib/lisp.x:2165`). It is current only while
the call's bindings Map is created (`:2166`), never while the body runs. It
owns that Map and, for lowered source functions, the bytes of address-taken
and struct locals (`:2176-2179`, `:1113-1119`). The Scope current while a
meta body runs is the unit's Lisp session Scope, pushed at entry
(`lib/lisp.x:684`). Each unit has its own session, destroyed with the unit's
compiler (`src/compiler.x:250-256`); a REPL session lasts until it ends.

So `Scope.malloc` in a meta body allocates in the session Scope and lives
until the unit ends. That matches C: the outermost caller's active Scope owns
the allocation. A probe confirmed it: memory allocated in one `$f1()` call and
kept in a `meta static` was readable in a later `$f2()`, a nested call saw the
same current Scope, and the owner was `*Scope.top()`.

So `free` is not implied; it is optional, as in C. Making the frame the
current Scope would free every object a constructor returns. The rejected
recovery design hit this problem (`plans/archive/meta-recovery-design.md`,
lines 236-256).

`Scope.free` unlinks a block from whichever Scope owns it (`lib/scope.x:
886-891`). `Scope.realloc` keeps the block's owner and list position, and any
other pointer to the old block dangles (`:953-1000`). A double free, or a
pointer that did not come from a Scope allocator, is undefined, as in C.
Evaluator bytes (`lisp_bytes`, returned records, `meta static` values) are
ordinary Scope blocks.

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
use. Allocations land in the session Scope.

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

`fold_meta_call` applies a `meta` function whose arguments are all constants.
Before applying it, check the declared result type. When the result is a
pointer, or a class whose value is a pointer, keep the call without running
it. A result of type `Var`, `Array` or a record that happens to hold a heap
pointer still runs first and is then kept, because only its value shows the
pointer; the rule in part 6 keeps that pointer out of the generated code.

### 4. Lifetime checks

Extend the shared region pass in `src/regions.x`; add nothing to the
evaluator. Use after `Scope.free` of a named local in the same block already
warns (`Scope_free` is a `(free)` row, `:116`). The new rows:

- `Scope.realloc` stops being an `(alloc)` row (`:93`). Its result is an
  allocation in the argument's owner region, and the argument ends, so a
  later use of the old pointer is a use after free.
- `Scope.free` or `Scope.realloc` of storage no Scope allocator returned is
  an error: an `&` address (a local, a struct local, a static or a
  `meta static`), a string literal, or a `String`, `List` or `Symbol` value.
  These are the cases that reproduced compiler crashes and garbage
  constants.

As with track F, a finding in a meta body is an error and the function is
not installed; ordinary code gets the same finding as a warning.

### Misuse

Gary's condition is that `free` and `realloc` work "provided they are not
abused". The abuse this design does not defend against is misuse the region
pass cannot see: a double free, a free through an alias, a free in a nested
block followed by a use outside it, and a callee that frees its parameter.
In C these corrupt the program. In a meta body they corrupt the compiler: a
reviewer's probes crashed it (exit 139) and put wrong constants into the
generated program. The book must say this plainly. Adding summary rows for
callees that free their parameters is possible later in the same pass.

### 5. Heap classes

Heap-based x2c objects come in three tiers:

1. **Layout objects.** With parts 1-4, a heap class (`class X struct {...}
   *;` or `typedef struct X {...} *X`) works at compile time through its
   layout. Its constructor and methods can be `meta`, its fields can be read
   and written, and pointers can be compared for equality and stored. No
   Var boxing is involved.
2. **Classes built into a native module.** These already work fully: loading
   the module runs its file initializer, which registers the class, so
   boxing, `str` and Arrays of the class work (probe: `4 vec Vec(4,0)`).
   The rows they use are process-wide, since a module loads once per
   process.
3. **Classes defined in the unit being translated, boxed as `Var` in meta
   code.** Today this is silently wrong. The value boxes as a plain `<p48>`
   pointer, so `boxed is <vec>` answers 0 at compile time where the program
   answers 1, and `str()` writes a heap address into the generated C. The
   same holds for a hand-written typedef that adopts `protocol Var`. This
   tier needs Gary's decision (question 3).

### 6. Materialization and determinism

No native address reaches generated code, because addresses change from run
to run and the translation cache and self-host comparison depend on
identical output. This covers heap pointers and also the addresses of frame
bytes and `meta static` bytes. The declines live in the pointer's own Var
operations (write, `str`, `repr`, hash and ordering compare), not at
individual operators, so one rule covers every path that reaches them:
interpolation, `str` of a container holding pointers, `sort`, `min`, `max`,
`unique`, and Maps with a pointer key. At compile time:

- Converting an address to text or to a number (`str`, `repr`, hash, a cast
  to an integer type) declines with a plain diagnostic.
- Ordering comparisons of addresses decline. Equality comparisons are
  deterministic and stay allowed.
- An object cannot be a Map key, since hashing its address declines.
- Explicit `$` insertion of a pointer, or of a List that contains one, is
  diagnosed; the List case should get a plainer message than today's
  "syntax cannot be constructed at this position".

Rebuilding a runtime constructor call from the arguments would repeat the
construction and could not reproduce object identity, so it is out of scope.

## Deliveries

1. **Capability.** The prototypes in `lib/scope.x`, `sizeof` lowering, the
   folding rule, the region rows, the determinism rules in part 6, the
   tier 3 behavior Gary chooses, the book (the Lifetime section and its
   `defer` row, which currently say freeing is unavailable, and a new
   section on heap objects with the misuse warning), fixtures, and a
   bootstrap refresh. Fixtures cover:
   - a constructor-style meta function whose object its caller reads;
   - `realloc` growth with pointer indexing;
   - `sizeof`;
   - rejection of use after `free`, use of the old pointer after `realloc`,
     and freeing a string literal, a local's address and a `meta static`;
   - declining `str` of a heap pointer and a heap object as a Map key.
2. **Example.** One book example: a heap class whose `meta` constructor and
   methods are used by a meta function that computes a constant. Library
   constructors are marked `meta` only when a compile-time caller needs
   them; none does today. When one is added, check its translation cost.
   Constructors that assign enum constants (`MachineBuilder.new`) need
   compile-time enum constants first, and a constructor whose public
   prototype sits above `#pragma private` (`Greeting.new`) cannot be called
   at compile time by importers.

Each delivery ends with a review and repair of its authored diff, then
`tools/gate-state.py ensure agent-pr-check`.

## Decisions for Gary

1. **Ownership.** Allocations go to the session Scope, which is C's answer,
   and there is no per-application Scope for heap memory. Recommendation:
   yes. A per-application current Scope would free every constructor's
   result.
2. **`free` and `realloc`.** Bind both with C semantics. The compiler
   rejects the misuse it can see (part 4). Misuse it cannot see can crash
   the compiler or corrupt the program's constants, and the book says so.
   Recommendation: yes, as Gary asked.
3. **Tier 3 boxing.** Options:
   - (a) When meta code first boxes a unit-defined class, register a
     tag-only class in the compiler process. Identity, equality and `is`
     work; `str` of the object declines under part 6. Rows are process-wide
     and persist across the units a worker translates; 27 are free today,
     and running out needs a clear diagnostic. Tier 2 already spends rows
     this way.
   - (b) Also lower the class's `meta` Var methods (`str`, `equal`, `hash`)
     and register a descriptor that calls them. More complete, but a larger
     change to class registration.
   - (c) Decline boxing a unit-defined class, or a typedef that adopts
     `protocol Var`, with a plain diagnostic that points to native modules.
     This replaces today's silent wrong answers.

   Recommendation: (c) in delivery 1, and (a) as a later change together
   with a way to release a unit's rows when it finishes; lazy class
   registration alone does not release rows.
4. **Determinism rules (part 6).** Decline address-to-text and
   address-to-number conversions, ordering comparisons and hashing of any
   native address at compile time, in the pointer's own Var operations.
   Recommendation: yes. The alternative is to allow them and accept
   generated code that differs between runs.

## Plan review

- **Facts established elsewhere.** The native meta path establishes each
  target and its signature. The Scope allocator establishes ownership; the
  session Scope is current because `lib/lisp.x:684` pushes it. Layouts from
  `meta_type_layout` establish sizes. The region pass establishes lifetimes.
  No consumer rechecks these facts, and the evaluator adds no validator.
- **Reuse and deletion.** Everything reuses existing machinery: `meta`
  prototypes, the native target generator, layouts, native pointer access
  from track C, and track F's region pass. New lasting pieces are the
  `sizeof` lowering, one folding condition, the region rows, and the
  address rules in part 6.
- **Idiomatic x2c.** Constructors stay ordinary x2c functions marked `meta`.
  Nothing wraps objects or tracks allocations.
- **Validators, diagnostics and negative fixtures.** The region rows reject
  frees of storage no allocator returned, which reproduced compiler crashes
  and wrong constants. The part 6 declines keep generated output identical
  between runs. The tier 3 diagnostic replaces silently wrong answers. The
  pass does not claim to catch all misuse; the book states what it misses.
