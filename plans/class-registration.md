# Class registration on first box, and unlimited classes

> Status: active - designed 2026-09-24 as step 1 of
> [meta sequencing](meta-sequencing.md). Implemented 2026-09-24 on branch
> `class-registration`; awaiting review and `agent-pr-check`.

## Result

- A class spends a Var row only when a value of it is first boxed. Linking
  a runtime object costs no row, so native meta modules (sequencing step 2)
  can link the whole runtime.
- The number of classes a process can box has no fixed limit. The first 30
  classes boxed get direct rows as today; later records carry their
  descriptor in front of the boxed copy, and later heap classes box
  through a cell.
- Boxing may happen after `Thread.start`. Declaring descriptors still ends
  at the first `Thread.start`, as the book documents.

## Current behavior

Facts from source on `dev` at `494196b5`:

- A custom row is `top = 0x800C + id/8`, `bits 0-2 = id % 8`, address in
  bits 3-47 (`_new_custom_pointer`, `lib/var.x:597`). Four tag values times
  the 3 bits that 8-byte alignment frees give 32 rows. No spare tag range
  exists: 0x0010-0x7FFF and 0x8010+ are doubles and 0x8004-0x800B are
  Symbols.
- Every record, heap class and tagged `protocol Var(T)` registers in a file
  constructor emitted by `Compiler._generate_descriptor_registration`
  (`src/protocol.x:2047`) through `x2c_register_(tagged_)descriptor`
  (`lib/dispatch.x:146-207`) to `Var.register_object_tag`
  (`lib/var.x:240`). Rows follow constructor order. Only tag Symbols are
  persisted (generated C, `.xi`); row numbers never leave the process.
- Readers take no lock: `_decode`, `Var.tag`, the linear scan in `Var.new`
  (`var.x:672`), and `custom_descriptors[id]` in dispatch. This is safe
  only because registration freezes at the first `Thread.start`
  (`dispatch.x:302`).
- The compiler uses 5 rows; linking the whole runtime would use 18.
  Workarounds the budget forced: `protocol Var(Compiler) as void *`
  (66e54256), linking only row-free objects whole
  (`etc/runtime-objects.sh`, 8e473ff5), declining `Regex.escape` in the REPL
  surface, and style guidance that treats `class` as a budgeted choice.

## Design

### Declaring and assigning are separate

A constructor's registration **declares** a descriptor: it allocates one
process-lifetime `VarDescriptor` (tag, methods, name) and adds it to a
declared-tag Map under the descriptor mutex. Declaring spends no row, has
no count limit, and freezes at the first `Thread.start` exactly as
registration does today. Tag collisions and the other declaration errors
stay where they are.

A row is **assigned** on the first `Var.new` of a declared tag whose row is
not yet assigned. The miss path takes the descriptor mutex, rechecks,
writes the descriptor pointer into the next direct slot, then publishes the
new count with a release store. Readers load the count with acquire. Slots
are append-only and never reused, so a reader that sees a count sees every
slot below it fully written. The direct tables become 32 descriptor
pointers; `custom_tags[]` goes away because the descriptor holds the tag.

`Var.known_tag`, `value is T` and unboxing answer from the declared Map
when a tag has no row yet: a value of an unassigned class cannot exist, so
`is` answers false without assigning.

### Overflow rows for classes past the direct rows

Rows 30 and 31 become overflow rows, leaving 30 direct rows. The overflow
row depends on who owns the object's storage.

- **Records, row 31: a descriptor prefix.** Boxing a record already copies
  it with `Scope_memdup` (`etc/builtin-macros.x:291`). For an overflow
  record the copy reserves one `max_align_t`-sized slot in front of the
  record, stores the descriptor pointer there, and boxes the record's own
  address. This is how Scope keeps its own metadata in front of each
  payload (`lib/scope.x:74-88`), so alignment and layout are unchanged.
  Decode reads the descriptor at a fixed negative offset. `Var.same`,
  equality and hashing need no change, because the Var holds the record's
  address.
- **Heap classes, row 30: a cell.** A heap class's pointer may point at
  static data (`_json_true`), native memory, or an element inside an array,
  so nothing may be read in front of it. `Var.new` boxes the address of a
  process-lifetime cell `{descriptor, pointer, next}`, one per class and
  address, interned under the descriptor mutex in a Map from address to a
  chain of cells. `Var.pointer` returns `cell->pointer`. Boxing the same
  object twice gives identical bits, so `Var.same`, equality and hashing
  need no change. A cell's contents are fixed by its key, so a reused
  address never sees a stale cell; memory grows only with distinct
  (class, address) pairs.

`Var.tag`, dispatch and `encoding_valid` read the descriptor the same way
for both rows. Direct rows are unchanged, so the hot path for the first 30
classes adds only one compare. An overflow record costs one slot per box
and one dependent load per dispatch; an overflow heap class costs a locked
Map lookup per box (one cell per distinct class and address) and one
dependent load per dispatch.

No descriptor table grows, so no reader ever sees a reallocation.

### Alternatives rejected

- 16-byte alignment for 64 rows: breaks heap classes on static or native
  memory (`_json_true`), and only doubles the limit.
- A hidden header word in every object: breaks native-layout
  `class X struct {...} *` and pointers that Scope does not own.
- Reclaiming the 5 free built-in slots or address bit 47: about 5 rows, or
  not portable to arm64 Linux.
- Locking every decode: puts a mutex on the hottest Var path.

## Compatibility

- Public API: `x2c_register_*` keep their names and signatures; they
  declare instead of assign. `Var.register_object_tag` keeps its contract
  except that it no longer returns -1 for a full registry. The
  `<bad-state>` after freeze stays.
- Book: `docs/src/guide/system-macros.md` (rows "boxed or not",
  exhaustion at startup), `contexts-and-threads.md` (registration before
  `Thread.start`: declaration still, boxing no longer),
  `protocols.md`, and the dispatch and var module pages.
- Guidance: remove the row-budget advice in
  `agents/x2c-coding-style-guide.md` and the class-row caveats that cite
  it. Keep `as void *` where it is the right representation; revert
  66e54256 only if `Compiler` reads better as a class.
- `etc/runtime-objects.sh` no longer needs to exclude row-reserving
  objects. Whether to link the whole runtime into the compiler is
  sequencing step 2's decision; this step only removes the reason not to.
- Generated C keeps its registration calls. The record box copy changes
  inside the boxing macro; no bootstrap capability is needed first.

## Implementation

One coherent change:

1. `lib/dispatch.x`: declared-tag Map and descriptor allocation; the
   registration entry points declare; row assignment under the mutex with
   release publication.
2. `lib/var.x`: acquire loads in `_decode`; direct slots as descriptor
   pointers; the `Var.new` miss path; row 30 overflow cells with decode,
   unbox, `same`, fallback `equal` and `hash`; row 31 prefixed record
   copies; `known_tag` from the
   declared Map. Replace the linear scan in `Var.new` with the declared
   Map lookup if it measures no slower.
3. Fixtures and unit tests:
   - replace `var-custom-tag-registry-full` with a program that declares
     and boxes 40 records and 40 heap classes, checks `is`, unboxing,
     `same`, dispatch and
     `Var.tag` for direct and overflow values;
   - a class declared but never boxed spends no row (count before and
     after);
   - a thread test: two workers first-box different classes concurrently
     after `Thread.start`, then dispatch on each other's values.
4. Book and guidance edits listed above.
5. Measure `Var.new` and dispatch on a direct-row class before and after
   with `make performance-snapshot` lanes that box user classes; record the
   result here.
6. Review the completed authored diff and fix what it finds, then
   `tools/gate-state.py ensure agent-pr-check`.

## Implementation notes

- The registry lives in `lib/var.x`: `declared` (a Map in a `Var classes`
  Scope destroyed by a shutdown hook), `rows[30]` and `row_count`.
  `VarDescriptor` moved to `lib/common.x` and gained `tag` and `row`.
  `x2c_var_declare` and `x2c_var_custom_descriptor` connect it to dispatch.
- Record boxing calls the new `Var.box_record(tag, record, size)`, which
  copies with or without the prefix. The `.xlisp` refresh carries the
  macro change; code generated by the checked-in bootstrap still calls
  `Var_new` on a `Scope_memdup` copy, which stays correct because an
  overflow `Var.new` boxes through a cell.
- `Var.register_object_tag` now returns 0 for a declared tag.
- Overflow heap-class cells are interned process-lifetime cells, not
  Scope-owned ones: a Scope-owned cell tied the Var to the boxing Scope
  instead of to the object, and a boxed value read after its worker ended
  crashed.
- `Var.new` keeps a lock-free scan of `rows[i].tag` and uses the declared
  Map only on a miss. A Map lookup instead of the scan measured about 6x
  slower per box. A parallel `row_tags[]` measured no better, so it was
  dropped.
- `etc/runtime-objects.sh` keeps its exclusion; only its comment changed,
  because removing it would change what the compiler links (step 2).

## Measurements

`Var.new` of a direct-row heap class and a dispatched `Var.hash` on it,
50M iterations each, `-O2`, the same generated C linked against each
runtime, 11 interleaved runs per side, medians, two rounds:

| Operation | Before (`dev`) | After | Change |
|-----------|----------------|-------|--------|
| `Var.new` | 2.87 ns | 3.13 ns | +9% (+0.26 ns) |
| Dispatch (`Var.hash`) | 9.49 ns | 9.29 ns | -2% |

The boxing cost is the acquire load of `row_count` and the extra
descriptor load in the row scan. Repeatedly boxing one overflow heap
object (the 31st class boxed) costs about 46 ns per box: the descriptor
mutex and the cell Map lookup.

## Design review

- Reuse: the record prefix reuses Scope's metadata-before-payload
  layout, and the heap-class cell is interned in an ordinary Map; the
  mutex and freeze already exist. No new table type.
- Deleted: `custom_tags[]`, the exhaustion message and its fixture, the
  row-budget guidance and the row-reserving exclusion in
  `etc/runtime-objects.sh`.
- Checks: no new validator. The freeze check and collision errors stay
  where they are; `is` on an unassigned tag needs no check because the
  declared Map answers it.
- Risk: memory ordering. The release/acquire pair is the whole safety
  argument for boxing after `Thread.start`; the thread test exercises it
  but cannot prove it, so the review must read every reader of the count.
