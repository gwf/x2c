# Map and Array rest parameters

> Status: needs author scoping
> Recorded 2026-10-27 after `List @name` replaced the four-dot spelling of
> List rest parameters. Nothing here is implemented. Gary decides the open
> questions below before work starts; Map and Array are separate changes.

## Starting point

A final `List @name` parameter packs the trailing call arguments into one
ordinary List; see "List rest parameters" in
[the language reference](../docs/src/reference/language.md#list-rest-parameters).
The parser in `Compiler.parse_parameter` reads `@` after a `List` type and
produces `(param (....) (bind NAME ()))`. Every later owner tests the
semantic Type `(....)`: call typing and lowering, `Compiler.pack_rest_arguments`,
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
- The parameter Type generalizes from `(....)` to a marker that names its
  container, for example `(.... "Map")`. Each existing `(....)` site then
  branches on the container instead of assuming List.

Questions for Gary:

1. **Combined tails.** May one function have both `List @args` and
   `Map @options`? Recommendation: yes, with positional arguments going to
   the List and entries to the Map, in any order, still evaluated in source
   order. Without the List, a positional argument after the fixed prefix is
   an arity error.
2. **Map splices.** Does `@m` at a call with a Map rest merge the entries of
   Map `m`? Recommendation: yes, but only when the callee has no List rest,
   so `@` keeps one meaning per call. With both rests, `@` splices a List
   and a Map is merged with an explicit `@(m)` entry-row form or is not
   supported in the first change.
3. **Dynamic calls.** `Func.apply` receives one positional argument array
   and has no channel for keys. Recommendation: a Func whose signature ends
   in a Map rest receives its Map as one final positional argument, and only
   direct, method, and typed-pointer calls pack `key: value` syntax. A
   keyword channel through `Func.apply` would change public runtime ABI.
4. **Duplicate keys.** Recommendation: follow Map literal behavior (last
   write wins) rather than adding a rejection.

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
   only) and reject an entry argument when the callee has no Map rest.
3. Extend `Compiler.pack_rest_arguments` to build the container's literal
   syntax for its tail, and update the other marker sites, the REPL lowering,
   and `Func.new`/`Func.new_rest` signature checks.
4. Document the form beside "List rest parameters" and add one executable
   example; render the parameter in `tools/definitions.x`.
5. Review and fix the completed authored diff, then run
   `tools/gate-state.py ensure agent-pr-check`.

Validation covers zero, one, and many entries; Atom and expression keys;
evaluation order across fixed arguments, positional rest, and entries;
methods, typed pointers, and Func conversion; and the rejection of an entry
argument for a callee without a Map rest.

## Plan review

- The parser establishes the rest marker once; later owners read the marker
  and do not re-derive it. Map literal lowering already owns key spelling,
  evaluation order, and fresh identity, so packing builds that syntax instead
  of a second Map builder.
- The design reuses `Compiler.parse_map_entry`, `$map_value`, the Array
  literal lowering, and the existing rest call path. The one lasting change
  is the marker's container field, which is necessary because C sees each
  rest parameter only as its container type.
- The source stays direct: a rest parameter is a container literal written
  across the call's arguments, with the same `@` used by macros and splices.
- One new diagnostic rejects a `key: value` argument for a callee without a
  Map rest; it protects against silently passing an entry as a positional
  value. The existing final-parameter check covers misplaced rest
  parameters. No other validators are proposed.
