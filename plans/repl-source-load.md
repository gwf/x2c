# Load compiled definitions into the REPL

> Status: implemented, with focused checks passed.

## Result

`:load "file.x"` compiles the file's public bodied meta functions and makes
them callable from the persistent prompt. Prompt submissions continue to
lower to Lisp. Compilation occurs only when loading source.

The first supported boundary exchanges data with a separate native helper
for each load. Numbers, Strings, Symbols, Lists, and independent Arrays and
Maps cross the existing datum protocol. Pointers, references, callbacks,
records, cycles, and shared mutable collection identity do not cross it.

## Decisions and implementation

1. Reuse the project meta builder's source, include, module, package, native
   object, and cache handling. `Frontend.build_meta` returns an independently
   owned `MetaHelper`; ordinary translation retains its existing primary
   helper through `prepare_meta`. Native compilation keeps its current owners.
2. Parse the source through `Frontend` in a nested source Context. Save and
   restore the enclosing unit's source-declared Var tags. Export declarations
   and signatures, then close that Context. Calls exchange values through
   the helper's existing protocol; the source Context owns no native result.
3. Expose the collector's selected public type families and callable rows.
   Install them with `Sym.define_global`; never copy source binding IDs or
   replace the prompt compiler. Reject conflicting names and type rows before
   publishing. Static functions and ordinary supporting bodies stay private.
   Global variables, enumerator constants, and source macros are not
   installed in the prompt.
4. Refresh collection indexes and source hashes before loading. Retain their
   backing rows because live session declarations can still refer to them.
   This allows a failed load to be fixed and retried within the session.
5. Keep each loaded helper's executable in a private temporary directory.
   Cache rebuilds, including those made by rejected reloads, cannot replace
   its code. The session closes helpers and removes those copies. A helper
   crash restarts that load's retained executable with fresh native state.
6. Preserve no-redefinition semantics. Loading another file leaves earlier
   helpers and prompt definitions usable. A failed load publishes no names.
7. Verify executable transcripts, edit/retry recovery, native literal and
   static lifetimes, independent loads, public typedefs, private helpers,
   included meta dependencies, collection copying, unsafe argument rejection,
   compile/link failures, duplicate names, helper restart, and cleanup.
   Run existing REPL and meta-helper checks, review the authored change, and
   complete ordinary direct delivery to dev after publication validation.

## Design evidence and review

A direct in-process native-module probe compiled a bodied meta function and
its ordinary private helper, then called it from the existing Lisp evaluator.
It established that ordinary compiled code can serve the prompt. It did not
establish safe lifetime ownership: native String and List literals interned
in the temporary source Context became invalid after that Context closed.
A second load demonstrably changed an earlier String result and exposed
corrupted List entries. This rejects that lifetime arrangement, not every
possible in-process loader.

The project helper already gives compiled code stable native storage and
serializes results before its call Scope closes. Reusing it also supplies
dependency handling without a second linker or runtime allocation policy.
The command owns selection, collision checks, publication, and lifetime;
the compiler owns parsing, typing, native adapters, and transport.

The existing Func value reader rejects reference carriers before reading
them as values. The datum result checker rejects pointers, cyclic inputs,
and shared mutable collections before serialization. These checks protect
the native crossing; they do not duplicate language parsing or type layout.

Source cache refresh addresses a reproduced failed-load/edit/retry defect.
It replaces indexes instead of deleting entries during iteration, because
Map deletion invalidates that iteration. Executable retention addresses a
mutable-cache hazard and is checked both before the first call and after
helper restart. These are
interactive-lifetime requirements; ordinary compiler invocations retain
their current cache and helper behavior.

## Focused validation

- `make commands` builds the compiler services and external REPL command.
- `sh commands/repl/tests/run.sh` passes existing submission, teardown,
  native-call, and terminal checks plus the new source-load scenarios.
- `sh unittest/probes/run-meta-helper.sh` passes ordinary compiler helper
  crash, exit, timeout, parallel-worker, and subprocess lifetime checks.

Source-load tests also check that an enum-typed global is not accidentally
imported as a type-family member. Public type rows are copied without
transplanting binding IDs or enumerator evaluation facts.
