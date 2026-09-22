# Meta recovery

> Status: done
> Delivered to `dev` as `db86d4b7` on 2026-09-22 after the full gate and two
> independent reviews. Follow-up work is dispatched from
> [meta follow-ups](../meta-followups.md). Earlier designs and checkpoints
> are archived as [values and types](meta-values-types.md),
> [checkpoints](meta-recovery-checkpoints.md),
> [design](meta-recovery-design.md) and [review](meta-recovery-review.md).

## Required result

`meta` advertises a declaration to compile-time execution: functions with
bodies, bodyless native prototypes, and initialized file-static values.
Types need no marker (Gary, 2026-09-22): compile-time code can use any type
the compiler sees, so the earlier `meta struct`, `meta typedef`,
`meta class` and `meta Name;` adoption forms were removed.

Interpreted code must behave as C does wherever C has the same code: value
copies, aliasing, field addresses, native calls through pointers, and storage
lifetime. The compiler owns types and layout, Scope owns storage, and
lifetime rules come from the compiler's shared analysis. Nothing is
special-cased by type name, and a type's methods need their own `meta`.

The primary acceptance case is a struct declared by a system header, used as
a local, passed by address to a native API that fills it, read afterward,
and reclaimed when the function returns, including on an error.

## Design

A struct local, and any local whose address is taken, is a C object in
native bytes. `Compiler.meta_type_layout` produces its layout from the
compiler's own declarations, as `(KIND TYPE SIZE ALIGN ...)`. The local's
slot holds a pointer to the bytes, boxed with the tag native code gives that
pointer, so `&x` is the slot and a native callee receives real storage.

The lowering in `src/comptime.x` emits every size, offset and layout as a
constant. The runtime in `lib/lisp.x` only moves bytes: `lisp_bytes`,
`lisp_at`, `lisp_copy`, `lisp_peek`, `lisp_poke`, `lisp_record_result` and
`lisp_session_copy`. A record reads as its own address; assignment copies
into the destination's bytes, so earlier addresses stay valid. Exact C
scalars load and store through the one ledger in
`lib/native-scalar-types.xmacro`, which the compiler's Type lookup also
uses.

Automatic bytes belong to the Scope of the running source function's Lisp
frame, which already exists for its bindings, and end when the frame ends,
normally or by an error. Only functions that keep objects in bytes, or
return a record, are marked as source functions, so every other lowered
function keeps the optimized evaluator path. A returned record is copied
into the caller's storage before the callee's frame ends. Meta values and
REPL-persistent records live in session bytes. Native heap objects keep
their ordinary Scope ownership.

Lowered calls to `try_*` operations and `foreach` steps call the native
functions directly with these typed pointers. Plain Lisp keeps its cell
bindings under `*_cell` names. Iterator destinations that need no callback
bind their native operations directly.

A bodyless `meta` prototype binds to the compiler's own linked function of
the same name; its signature must match exactly. Included units record their
native declarations by name, and a function binds the first time
compile-time code calls it, so a unit with no compile-time code pays
nothing. The compiler links all of `lib/cmath.x` and `lib/clibc.x`, both in
the prelude.

`Func` adapters accept a pointer with no Var tag of its own, and a struct
passed or returned by value, as `<p48>` addresses. This works for ordinary
programs as well as compile-time code.

The semantic transaction stages `meta_layouts`, so a failed expansion or
REPL submission rolls back the layouts it computed.

## Decisions

- Semantics follow C wherever C has the same code (Gary, 2026-09-22).
- Persistent containers keep identity; struct values copy; a pointer to an
  expiring local is not made valid by storing it.
- System-header structs come through a separate `--system-headers` option
  (Gary, 2026-09-22). `--cpp-symbols` keeps its `dev` behavior, which
  `proof-raw-symbols` checks against ordinary collection; expanding system
  headers there broke that parity.
- A small libc set ships with the compiler; everything else waits for native
  extension loading, the last stage of the campaign.
- `Var.func` and `protocol Var(Func)` stay public.

## Campaign sequencing decision: native extensions last

Project-provided native extension building and loading is the final stage.
Until then, compile-time code calls only functions linked into the compiler,
and adding one means rebuilding the compiler. The final stage builds user
native code with generated typed adapters into a loadable module, then loads
it for translation, build, or REPL use through the same binding path. Its
command spelling and module lifetime are open questions for that stage.

## Known limits

- Unions, bitfields, arrays inside structs, anonymous members and structs
  with alignment attributes have no compile-time layout.
- Structs laid out under `#pragma pack` are not detected. They get natural
  alignment, so passing one to a native function from compile-time code is
  unsafe.
- A loop allocates storage once for each object declared in its body and
  initializes it in place on every iteration. A struct copied from another
  value there still takes fresh bytes, which the frame reclaims on return.
- `x2c_func_value_argument` prepares its five catch clauses on every call
  with a numeric argument, which made field access 7x slower until the byte
  operations took their offsets as `Var`. Other numeric native calls from
  compile-time code still pay it; it predates this work.
- The 32-row custom Var tag space is shared by every library and user class
  in a program. A growable slow path is a separate design.

## Validation

On the final tree: all 941 unit tests, all 791 compiler fixtures and the REPL
check pass, and `agent-pr-check` runs before delivery. Translating a trivial
program takes about the same time as a `dev` compiler from 2026-09-19;
`--system-headers` translation is about three times slower because it reads
the expanded headers. A 200,000-iteration compile-time loop over struct
fields takes 0.9 s, the same as the scalar loop, and one that declares a
struct in its body takes 2.0 s.

## Remaining stages

1. Native extension build and load (above).
2. Meta-capable protocol witnesses, recorded in
   [meta authoring and coverage](../meta-authoring-and-coverage.md).
