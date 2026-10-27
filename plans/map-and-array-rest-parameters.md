# Map and Array rest parameters

> Status: active
> Recorded 2026-10-27 after `List @name` replaced the four-dot spelling of
> List rest parameters. Gary settled the Map questions the same day, and Map
> rest was implemented on 2026-10-27 as described below. Array rest stays
> deferred until a caller needs indexed access to its tail. A Map produced by
> a meta call cannot yet reach any Map meta parameter, so it cannot be
> spliced into a meta call's Map rest either.

## Starting point

A final `List @name` parameter packs the trailing call arguments into one
ordinary List; see "List rest parameters" in
[the language reference](../docs/src/reference/language.md#list-rest-parameters).
The parser in `Compiler.parse_parameter` reads `@` after a `List` type and
produced `(param (....) (bind NAME ()))`, now `(.... "List")`. Every later
owner tests that semantic Type: call typing and lowering, `Compiler.pack_rest_arguments`,
callable conversion, Func adapters, meta-native calls, protocol forwarders,
the REPL, and the runtime `Func` constructor in `lib/func/func.x`. There are
about 20 such code sites in `src/` and `lib/`, plus seven in
`commands/repl/`.

The `T @name` spelling already matches macro rest captures (`Expr @values`,
`Entry @rows`) and call-site splices (`@xs`). Map and Array rest parameters
would extend the same spelling: `Map @options` and `Array @values`.

## Map rest parameters: keyword arguments

The result is a call such as `open_file(path, mode: <read>, retries: 3)`
whose `key: value` arguments are packed into a fresh Map. Keys and values
follow the bare Map literal rules: a bare identifier key is an Atom, other
keys and all values are ordinary expressions, and entries are evaluated once
in source order. An absent tail gives an empty Map.

Reused owners:

- Call arguments parse `key: value` with `Compiler.parse_map_entry`, which
  macro invocations already use for `Entry` captures. The entry rule in the
  reference (first `:` outside brackets and not part of `?:`) is unchanged.
- Packing builds the existing `$map_value(...)` syntax and lets
  `src/components/collection-literals.x` lower it, as a bare `{...}` does.
- The parameter Type names its container: `(.... "Map")` beside List's
  marker, which became `(.... "List")` on 2026-10-27. Each rest site reads
  the container through `Type.rest_container` instead of assuming List.

Decisions (Gary, 2026-10-27):

1. **One rest per function.** A signature ends in either `List @name` or
   `Map @name`, never both. At a direct, method, or typed-pointer call to a
   Map rest function, every argument after the fixed prefix is a
   `key: value` entry or a Map splice; a positional argument there is
   rejected.
2. **Map splices.** With one rest per function, `@` has one meaning at each
   call: `@m` and `@(expression)` at a Map rest call merge that Map's
   entries into the packed Map, in source order with the other entries.
   This follows from decision 1; no combined-tail rule is needed.
3. **Dynamic calls pack automatically.** A Func whose signature ends in a
   Map rest builds its Map in `Func.apply`, as `_apply_rest` builds a List
   today. A call site passes each entry as its key followed by its value,
   so a native or Lisp caller passes `k1, v1, k2, v2`. A Map splice travels
   as one marked argument whose entries are merged. An odd number of
   trailing values raises `<bad-arity>`.
4. **Duplicate keys.** Last write wins, as in a Map literal.

## Array rest parameters

The result is `int total(Array @values)`, which packs trailing arguments into
a fresh Array through the existing Array literal lowering. Its only gain over
List is indexed access inside the callee, because rest tails are short and
built once per call.

Bare Array literals have no `@` splice today, so an Array rest needs one of:

- adding `@xs` and `@(expression)` splices to bare Array literals generally,
  which also enables `[1, @xs, 4]`; or
- packing Array tails without splices, which makes `@` legal for List rest
  and illegal for Array rest.

Recommendation: do not implement Array rest until a caller needs indexed
access to its tail. If it is selected, add Array literal splices first as
their own change, so packing reuses them instead of a rest-only splice path.

## Implementation outline

Each selected change:

1. Generalize the parameter marker and accept `Map @name` (or
   `Array @name`) in `Compiler.parse_parameter`; refresh bootstrap before
   adopting the spelling.
2. Parse entry arguments in calls through `Compiler.parse_map_entry` (Map
   only). Reject an entry argument when the callee has no Map rest, and a
   positional tail argument when it has one.
3. Extend `Compiler.pack_rest_arguments` to build the container's literal
   syntax for its tail, and update the other marker sites, the REPL lowering,
   and `Func.new`/`Func.new_rest` signature checks.
4. Map only: make `_apply_rest` in `lib/func/func.x` pair the trailing
   values into a Map for a Map rest signature, and add a Map splice
   constructor beside `FuncArg.splice` and `x2c_func_splice_argument`.
   Existing runtime signatures stay unchanged; the additions are new public
   functions.
5. Document the form beside "List rest parameters" and add one executable
   example; render the parameter in `tools/definitions.x`.
6. Review and fix the completed authored diff, then run
   `tools/gate-state.py ensure agent-pr-check`.

Validation covers zero, one, and many entries; Atom and expression keys;
Map splices and duplicate keys; evaluation order across fixed arguments,
entries, and splices; methods, typed pointers, and Func calls, including
alternating keys and values from a native caller and an odd count; and the
rejection of an entry argument for a callee without a Map rest and of a
positional tail argument for a callee with one.

## Plan review

- The parser establishes the rest marker once; later owners read the marker
  and do not re-derive it. Map literal lowering already owns key spelling,
  evaluation order, and fresh identity, so packing builds that syntax instead
  of a second Map builder.
- The design reuses `Compiler.parse_map_entry`, `$map_value`, the Array
  literal lowering, the existing rest call path, and `_apply_rest`. The
  lasting changes are the marker's container field, which is necessary
  because C sees each rest parameter only as its container type, and one
  Map splice constructor, which is necessary because `FuncArg.splice` takes
  a List and its signature is public.
- The source stays direct: a rest parameter is a container literal written
  across the call's arguments, with the same `@` used by macros and splices.
- Two compile-time rejections protect deliberate public behavior: a
  `key: value` argument for a callee without a Map rest, which would
  otherwise pass an entry as a positional value, and a positional tail
  argument for a Map rest callee (decision 1). `Func.apply` raises
  `<bad-arity>` for an odd trailing count, because pairing would otherwise
  read past the last value. The existing final-parameter check covers
  misplaced rest parameters. No other validators are proposed.
