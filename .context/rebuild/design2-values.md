# Greenfield design: runtime value model and collections

Key: values. Area: map 2.8 plus the values rows of section 4; the 30
files in scope are the rows of the ledger table in section 3.

Current: 13,214 lines (7,894 code, 4,048 comment, 1,272 blank; awk over
the 30 files). Map 2.8's 11,454 is the 18-file subset. Comment lines count
in every estimate because `make doc-generate` builds the 20 module pages
(typed-array.md alone lists 259 callables) from the doc comments.

Greenfield estimate: about 10,000 lines. This area is close to its floor:
the current Var is already NaN-boxed with one ledger, the Map core is
already one generic family, and Block is already the one growth primitive.
The 3,200-line reduction comes from removing second public layers and
hand-expanded tables, not from a new representation.

## 1. Feature and contract inventory

Section 4 rows this area implements (checklist -> module):

- Var boxing, conversion, operators, dispatch; dynamic numeric conversion;
  dynamic truthiness and binary operators; protocol-backed direct updates and
  dynamic compound assignment; exact Var-tag tests; membership with `in`;
  indexing and slicing; list destructuring (List.unpack_n); string
  interpolation (String.new/add/str); symbol and atom literals; collection
  and string literals (Array.update_n, Map.update_n, List.list_n, cons);
  counted Array construction; Null/void as first-class values (coverage
  critique (b)).
- Runtime rows: array, atom, block, buffer, common, dispatch, list,
  list-selectors, map, string, string-classify, string-number, symbol,
  symbolset, typed Array/List/Map, var, varconvert, varops, native scalar
  types and integer ops.

Contracts the design must keep, with the source that states them:

1. Var is 8 bytes; Null all-zero, void all-ones (common.x:26-33, 208-209).
   Collections and iterators exclude void; equality, identity, rendering
   inspect it; everything else raises `<void-op>` (language.md:2405-2415).
2. Tag families: 15 numeric, p48, 26 pointer and 13 pointer-to-pointer,
   26 object and 26 reference, symbol, nan/+inf/-inf, void (var-tags.xmacro
   16-140; language.md:2380-2387). `Var.tag/kind/is/new` are public by tag.
3. Five wide families box in Scope-owned immutable boxes: equal, not
   identical; List keys of boxes differ (values.md:35-43; collections.md
   547-573; var.x:172-180).
4. One numeric conversion for 15 families: low bits kept, float-to-int
   truncates with `<conv-range>`, own-tag identity (varconvert.x:257-298).
5. C usual arithmetic conversions on tags; shifts keep the promoted left
   tag; floats reject `%`, shifts, bitwise (varops.x:140-249).
6. Failure-atomic updates for Var, native lvalues, Array and Map slots;
   Map numeric `+=` inserts a missing key with the rhs tag (varops.x:522-
   585; map.x:340-375; language.md:2656-2700; test-atomic-container.x).
7. Total order of groups and numeric classes with rank tie-break and exact
   integer-vs-float ordering (dispatch.x:800-846; var.x:1122-1172).
8. Descriptor dispatch: one 23-slot VarMethods row per object tag
   (common.x:177-196); registration freezes at the first worker start;
   custom classes use 30 direct rows then cell and record overflow with
   identical bits on re-box; folded-name collisions abort (var.x:182-232,
   384-430; dispatch.x:289-300, 441-455).
9. String and List are canonical through nested Pools; nil and the empty
   String are NULL; promote/try_own/is_permanent; transient String.malloc
   buffers (collections.md:392-426, 769-831; string.x:118-145, 254-336).
10. Array and Map are fresh objects, `==` structural, `===` identity, hash
    by identity; List hash/equal read car bits and cdr identity
    (collections.md:428-573; list.x:816-840).
11. Map: Robin Hood, 0.75 load, backshift deletion, staged growth, cursor
    invalidation, status-bearing try_* beside void-returning get/del
    (map-generics.xmacro:76-323; collections.md:1073-1132).
12. One slice normalizer for Array, List, String (common.x:845-892).
13. Typed arrays: raw bracket, checked try_get, native update that traps
    before storing, Context export with String recanonicalization
    (collections.md:929-1021; array-generics.xmacro:21-152, 742-840).
14. Typed maps: `<+>` initializes, other updates raise `<bad-arg>` where
    Map returns void; String keys recanonicalize on export
    (collections.md:1157-1219; map-generics.xmacro:325-573, 709-860).
15. Typed lists are Lists: same cells, no protocol Var, car of nil is
    zero, no long family (collections.md:638-687).
16. Rendering: display and readable forms for every tag, width-suffixed
    numeric repr, byte repr as C char constants, List repr wrapped at 80
    columns, RenderPath for cycles (dispatch.x:594-663; list.x:846-930).
17. Symbol 10x5-bit or 7x7-bit encoding below 2^51; Atom compact-or-lsym;
    SymbolSet is compiler-emitted perfect-hash bytes (symbol.x:26-104;
    atom.x:1-13; symbolset.x:28-33).
18. String.format checked subset with `<format>` details; String.printf
    with a 256-byte stack path (string.x:1097-1459).
19. Buffer line state across writes, unwrite, self-aliased growth;
    push/pop/indent/pad/tabstop (buffer.x:16-27, 122-170).
20. Compiler-emitted entry points keep their names: Var_new, Var_is_row,
    Var_pointer, String_var, List_var, cons, Array_updateindex,
    Map_updateindex, Map_update_n, List_list_n, x2c_var_update_* (grep of
    src/ and etc/; bootstrap C has 8,554 List_var, 6,052 String_var, 1,188
    int_var, 431 Var_is_row sites).

Hot paths that bound the design: unittest/benchmarks/var-hot-paths.x (tag,
kind, integer, hash, equal-hit/miss, compare-numeric, map-get),
varops-hot-paths.x (i32/f32/f64 fast lanes vs baseline, updates by family,
array and map slot updates), string-hot-paths.x (hash-canonical,
intern-duplicate, concat, join, replace, filter/map, printf-small),
list-hot-paths.x (cons-unique, cons-repeated, cdr-traversal, hash,
map-list-key-get with PSL, head/tail/index/append/map/filter/slice),
block-buffer-hot-paths.x (append-one, write-one, indent-80, serialize), and
unittest/benchmarks/hash-table (direct runner against khashl, udb3, Jackson;
x2c-typed lane isolates the Var layer).

## 2. Design, component by component

Thesis for this area: keep the representation, delete the second public
layers. Array and Map each have a hand-written public API over a generated
core that the typed families re-implement as a generated public API with
different policies. One family with three policy hooks (missing-element
answer, element validity, slot update) produces both. The same holds for
the "publish" and "observe" halves of the two generics files, which differ
only in the receiver type. Everything else is a fold of aliases and private
helpers into their one owner.

C1. Var word (common.x, var.x, var-tags.xmacro, var-ledger.x,
var-unbox.xmacro, var-adapters.xmacro, native-scalar-types.xmacro,
integer-ops.xmacro).

- NaN-boxing question: already answered by the current code. The shifted-
  double layout (var.x:5-47) frees 32 tops of 2^48 values; ~100 documented
  families need the 3-bit bottom selector on 8-aligned payloads and the
  16-bit middle field on immediates. A single tag field cannot hold the
  documented pointer, pointer-to-pointer, and reference families. Keep the
  layout, ledger, decode groups, and the constant-row projection behind
  the compiler's `Var_is_row` (expressions.x:2014-2028; 431 emitted sites).
- Scalar boxers become the inline immediates. Today `int.var` is
  `Var.new(<i32>, x)` (common.x:583-608), a variadic call plus a SymbolSet
  perfect-hash lookup per boxing, reached from 1,188 `int_var(` and 88
  `double_var(` sites in the generated compiler. The `$scalar` macro emits
  the `$var.immediate` body directly; `_new_integer`'s range checks stay in
  `Var.new` for computed tags only. This is a speedup, not a trade.
- Scalar readers (common.x:665-797, 14 functions of 6-8 lines) are one
  macro over the numeric ledger rows: exact-tag fast path, else convert.
- `Var.parse` (var.x:1235-1281) is dropped (section 8). The wide readers
  (var.x:982-1020) are one macro. Custom-class rows, cells, records, the
  integer/floating comparison helpers, and `Var.pointer` survive verbatim.
- The TagId enum is hand-written and checked against the ledger
  (var.x:62-82; var-tags.xmacro:353-370) because the compiler's shallow
  symbol pass does not expand macros. The same limitation causes the
  duplicate declaration blocks at common.x:502-505, 570-581, varops.x:21-39,
  typed-array.x:171-190. A rebuilt compiler that collects macro-generated
  declarations removes ~100 lines here; counted as a cross-area claim, not
  in this area's total.

C2. Numeric policy (varconvert.x, varops.x, varops.xmacro).

- The fast lanes (`_fast_numeric_tag`, `_fast_numeric`, `_same_tag_update`,
  varops.x:106-120, 251-306) survive verbatim; they are what varops-hot-
  paths measures against the hand-written baseline.
- `$native.update` (varops.x:45-88) keeps its 14 instantiations but writes
  its body with ordinary crossings: `Var current = lhs[0];` boxes through
  the now-inline `$type.var`, and `$type value = converted;` reads through
  the scalar reader whose exact-tag branch is hit by construction. The
  79-line row table in varops.xmacro (boxer, decoder, zero, cast pair) is
  not needed; the macro takes the tag literal it already receives.
- X2CVarNumericInfo becomes the first member of X2CVarNumeric
  (map 2.8 note; varconvert.x:19-32) so `_numeric_decode` copies one struct.
- Descriptor-vs-varops "one table" question: dispatch already is the one
  table (VarMethods add/sub/mul/div/mod/matmul/neg/compare/getindex...,
  common.x:177-184), and varops is the numeric fallback for tags that have
  no descriptor row (var.x:293-302). Routing numbers through rows would put
  an indirect call on every i32/f64 operation and cost the fast lanes.
  Declined (section 4).

C3. Dispatch (dispatch.x).

- The five index entry points (dispatch.x:348-425) are one macro over
  (member, slot, arity). The six registration entry points (107-207) fold to
  three (section 8). `_primitive_str` and `_write_primitive_str`
  (488-538) are generated from one (tag, format) table by a macro that
  emits both the String and the Buffer form; C10's objection (an added
  allocation and changed NULL handling from routing str through Buffer,
  map section 6) does not apply because both bodies still exist as code.
- `Var.fallback_*` become private helpers (they have no consumer outside
  lib/dispatch.x and lib/varops.x; grep across src/, commands/, packages/,
  examples/, unittest/ found none for the rendering forms).
- `Var.equal`'s row shortcut, `Var.hash`'s List/String unbox, the
  RenderPath cycle guard, `_numeric_compare`, and the total-order groups
  survive verbatim.
- The recursive pthread_once mutex block (dispatch.x:254-283) is one of
  three copies (map section 3, 87 lines); a shared `$recursive.mutex` lives
  in the runtime-infrastructure area and this file uses it.

C4. Names (atom.x, symbol.x, symbolset.x).

- symbolset.x is a survivor: its byte layout is what the compiler emits
  (symbolset.x:28-33) and the lookup is already one candidate plus one
  compare.
- symbol.x: `Symbol.str`, `Symbol.repr`, `Symbol.write_str`,
  `Symbol.write_repr` share one writer (like Atom's). atom.x survives; its
  dual representation and reader-escape rules are pinned by
  atom_repr_round_trips_lisp_reader and atom_write_repr_escapes_leading_angle.

C5. String (string.x, string-classify.x, string-number.x).

- Interning (string.x:85-380) survives: the 256-byte stack probe before
  allocation is the intern-duplicate hot path; promote/try_own/
  is_permanent are the pool contract List relies on (list.x:85-149).
- `String.format` (1140-1459): `_format_integer`'s 5x2 switch becomes a
  table (length modifier -> signed tag, unsigned tag, C type); the
  specifier rebuild, star handling, and error nesting stay.
- Transforms already go through the `$string.remap` and `$string.select`
  templates (675-700, 799-825); strip/lstrip/rstrip and partition/
  rpartition each become one helper with a direction flag.
- Escape/unescape (1459-1600) survive; the tokenizer has its own reader
  (map 2.1) and a shared table is a cross-area note only.
- string-classify.x and string-number.x survive as written: 12 predicates
  from one 8-line macro, and two parsers.

C6. List (list.x, list-selectors.x).

- Cons/pool, hash/equal/compare, the 80-column pretty printer, iterative
  large-list operations, unpack_n, and the varargs constructors survive.
- `List.subseq` and `List.getslice` (724-760) are one implementation;
  `unpack_n`/`unpack_vars_n` share one walker.
- list-selectors.x's 48 four-line accessors (16-113) are generated by a
  macro over the 2- to 4-letter a/d words for both List and Var receivers.
  This depends on the shallow-collection note in C1; without it the file
  survives at 113.

C7. Growth (block.x, buffer.x).

- One growth primitive already exists: Block (block.x:24-36, 91-118).
  String is immutable and grows nothing; its builders are Buffer, a stack
  scratch, or a transient Pool allocation (string.x:189-217). Buffer is
  Block<char> plus an indent stack and line state. Nothing to merge.
- Block: the Bytes twin methods (Bytes.reserve/append/append_fill/try_pop/
  push, block.x:120-280) are generated by one macro from the Block set.
- Buffer: line state (pos, _indent) is maintained incrementally in
  write_len (buffer.x:122-170, 50 lines with the memchr scans) and rebuilt
  by `_recompute_line_state` after unwrite. The greenfield computes both
  lazily when indent/pad/tabstop/pos are read, scanning back to the last
  newline. This is rope trade 1.

C8. Collections (array.x, map.x, the three generics files, typed-*.x).

- One generics family for list/array/map: no. The algorithms share
  nothing (Robin Hood over parallel arrays; memmove over a Block; canonical
  cons cells in a Pool). They share the instantiation shape: core(policy)
  + typed public API + observe (compare, write, str, repr, to-boxed) +
  publish (var, unbox, Iter next, export_context, protocol adoptions).
  The observe and publish halves are the same text with the receiver type
  swapped (array-generics.xmacro:643-840 vs map-generics.xmacro:575-860);
  one `typed-generics.xmacro` holds `$typed.observe` and `$typed.publish`.
- Array becomes an instantiation. array.x:64-460 hand-writes new, resize,
  update_n, getindex/setindex/updateindex/postfixindex, push, take_last,
  shift, unshift, insert, remove, copy, slices, splice, find/contains/
  count/indexof, concat, reverse over the same `_core_*` methods that
  `$array.typed.family` wraps (array-generics.xmacro:345-641). The Var
  differences are three hooks: element validity (reject void, array.x:218-
  232), missing-element answer (normalized index -> void, array.x:133-151,
  vs raw bracket and try_get), and slot update (Var.update on the slot vs
  the native operator macros). `$array.family(Array, Var, policy)` with
  those hooks generates the Var layer; array.x keeps only what has no
  typed twin: sort/sort_with/sort_by, heap ops, map/map2/foldl, join,
  str/repr wrappers, try_next/iter, list conversions, cleanup.
- Map becomes an instantiation the same way. map.x:114-445 hand-writes
  22 methods over the `_core_*` set that `$map.typed.family`
  (map-generics.xmacro:325-573) also wraps. Hooks: missing-key answer
  (void vs `<bad-arg>`), value validity, the numeric-`+` initialization
  predicate, and the slot update (Var.update vs `$update`). map.x keeps
  `$map.var.family` (the List/String key fast paths, map-generics.xmacro
  11-39, "must preserve"), update_n, export_to, get_hashed,
  iter/keys/enumerate, and the str/repr wrappers.
- typed-map.x's per-family error and accessor boilerplate (80-155, 16
  functions) is generated inside the core family from `$owner`; its
  `_update_int/_update_double/_update_string` (235-330) are the array
  slot-update macros (array-generics.xmacro:27-152) generalized to a slot
  pointer, so one `$typed.update.integer/floating/string` serves arrays,
  typed maps, and (through the Var hook) nothing else.
- The Map core (`$map.core.family`, map-generics.xmacro:40-323, 285 lines)
  is a survivor: u32-map.x, the runtime-free extraction of the same
  algorithm, is 354 lines with profiling counters, and khashl.h (the
  pinned reference in the hash-table lane) is about 300 lines for a
  comparable table.
- typed-list.x and list-generics.xmacro survive: a typed list is a
  predicate over immutable cells, already 225 lines for seven families.

## 3. Line ledger

Current by file (wc -l, 2026-09-26):

| file | lines | | file | lines |
|---|---|---|---|---|
| common.x | 904 | | list.x | 1,033 |
| var.x | 1,281 | | list-selectors.x | 113 |
| varops.x | 585 | | array.x | 831 |
| varops.xmacro | 79 | | map.x | 722 |
| varconvert.x | 298 | | typed-array.x | 191 |
| var-tags.xmacro | 415 | | typed-list.x | 123 |
| var-adapters.xmacro | 23 | | typed-map.x | 401 |
| var-unbox.xmacro | 31 | | array-generics.xmacro | 840 |
| var-ledger.x | 24 | | list-generics.xmacro | 102 |
| dispatch.x | 932 | | map-generics.xmacro | 860 |
| atom.x | 230 | | buffer.x | 359 |
| symbol.x | 281 | | block.x | 322 |
| symbolset.x | 130 | | integer-ops.xmacro | 45 |
| string.x | 1,771 | | native-scalar-types.xmacro | 92 |
| string-classify.x | 98 | | string-number.x | 98 |
| total | | | | 13,214 |

Greenfield by component, with anchors:

| component | current | greenfield | anchor and reasoning |
|---|---|---|---|
| C1 Var word | 2,815 | 2,150 | common.x 904->650 (inline scalar boxers -30, reader macro -60, keep the 140-line forward-declaration block and the 60-line slice normalizer); var.x 1,281->950 (drop Var.parse -48, wide-reader macro -30, TagId projection -25, rest verbatim); var-tags 415->330 (drop id checks -25, literal-bits special case -15, tighten comments); ledger/unbox/adapters/native-scalar/integer-ops 215 survive. Anchor: lib/regex.x (746) and lib/scan.x (749) are single-purpose modules of the same density; var.x carries 100 families, a class registry, and exact numeric ordering, so 950 is below 1.3x either. |
| C2 numeric policy | 962 | 770 | varconvert 298->270 (embedded info struct); varops 585->500 (native-update body through crossings -35, table -79 in varops.xmacro->0, fast lanes verbatim). Anchor: the 15x15 conversion and promotion rules are pinned by test-varops.x's four matrices; lib/json.x (570) is a comparable rules-plus-edges module. |
| C3 dispatch | 932 | 720 | index macro -45, registration 6->3 -50, primitive str/write_str from one table -25, fallback_* private -40, mutex block shared -25, remainder verbatim. Anchor: lib/match-recursive.x (445) is a pure-algorithm module; dispatch adds a registry and two renderers. |
| C4 names | 641 | 590 | symbol writer fold -30, atom -20, symbolset 130 survives. |
| C5 String | 1,967 | 1,460 | string.x 1,771->1,260: format table -110, strip/partition folds -30, doc comment compaction on the 63 callables -300 (current comment share 38%); classify and number survive at 196. Anchor: sds (antirez, ~1,300 lines of C for split/join/trim/printf/escape without interning); string.x also owns interning, a checked format subset, and Func map/filter. |
| C6 List | 1,146 | 880 | list.x 1,033->830 (subseq/getslice fold -15, unpack fold -15, comments -170); selectors 113->50 (generated). Anchor: examples/programs/literate-lisp.x implements a whole Lisp in 1,000; the List runtime with its printer is under that. |
| C7 growth | 681 | 590 | block.x 322->290 (Bytes twins generated); buffer.x 359->300 (lazy line state, trade 1). Anchor: stb_ds.h's arr* core is ~150 lines; Block's Scope ownership, header-before-bytes, and internal-source append add the rest. |
| C8 collections | 4,070 | 2,850 | array.x 831->380; map.x 722->330; array-generics 840->684 (publish/observe out, hooks in); map-generics 860->620 (same); typed-generics.xmacro new 240; typed-map 401->220; typed-array 191->150; typed-list 123 and list-generics 102 survive. Anchor: `$map.core.family` 285 vs u32-map.x 354 and khashl ~300; the typed public API text is fixed by 259+132+42 documented callables. |
| total | 13,214 | 10,010 | 24% smaller |

The estimate is 10,010 hand-authored lines; rounding, 10,000. Components
that shrink below 80% do so by deleting a second public layer (C8) or by
rewriting a hand-expanded table as a macro (C3, C6, C7). Nothing here
claims a smaller algorithm.

## 4. Rope trades (the 2x allowance)

1. Buffer lazy line state. Saves ~60 lines (buffer.x:44-56, 122-170).
   Expected: buffer-indent-80 up to 2x slower (each indent scans back at
   most one line), buffer-write-one faster, serialize unchanged. Buys one
   representation of line state and no unwrite special case. Measure:
   `make bm-block-buffer` (Makefile:395), then the translation CSV
   (`unittest/benchmarks/run-compiler-translation.sh`) since the emitter
   is the real consumer, and the build-cost score.
2. Array and Map public layers as family instantiations with hooks. Saves
   ~840 lines (C8). Expected 1.0x: the hooks are static inline, exactly as
   `$key_equal` and `$value_valid` already are in the Map core. Measure:
   `make bm-var` map-get, `make bm-varops` array/map slot updates, and
   `unittest/benchmarks/hash-table/direct/compare.py` against a frozen
   baseline binary (README lines 22-36). Above 1.1x on map-get is a
   defect (a hook failed to inline), not a trade.
3. `$native.update` through ordinary crossings. Saves ~114 lines
   (varops.xmacro and the macro body). Expected 1.0x once `$type.var` is
   the inline immediate (C1); up to 1.5x if the boxers stayed variadic.
   Measure: add an `x2c_var_update_i32(&n, <+>, one)` loop to
   varops-hot-paths.x (its i32-update row is Var.update, not the adapter).
4. Declined: numeric operators through descriptor rows (costs i32-fast and
   f64-fast); dropping the 256-byte intern probe (string.x:154-166,
   338-362; intern-duplicate 1.5-2x for 25 lines); dropping `Var.equal`'s
   row shortcut and `Var.hash`'s List/String unbox (dispatch.x:720-765;
   equal-hit, hash, map-list-key-get); dropping `$map.var.family`'s key
   fast paths (map section 6 "must preserve").

Speedups that come free with the design and should be measured, not
assumed: inline scalar boxing (1,188 `int_var` sites in the compiler's own
C; measure with `make bm-var` after adding a box-int row, and with the
translation CSV), and the smaller `Var.new` for computed tags.

## 5. Survivors (already at the floor)

- `$map.core.family` (map-generics.xmacro:40-323, 285 lines): one Robin
  Hood table for five families; u32-map.x is 354 with profiling, khashl
  about 300.
- The Var encoding, decoder, ledger rows, and constant-row projection
  (var.x:5-47, 234-291; var-tags.xmacro:16-140): one source feeds the
  runtime decode table and the compiler's two-compare `Var_is_row`.
- The numeric fast lanes and promotion rules (varops.x:106-159, 251-306);
  exact numeric ordering (var.x:1086-1172; dispatch.x:784-826).
- String interning with the stack probe and pool promotion (string.x
  85-380); `String.printf`'s two-size path (1108-1140).
- List cons/pool integration, hash/equal, and the pretty printer
  (list.x:26-62, 85-170, 816-930).
- `x2c_normalize_index/slice` (common.x:831-892); Block (block.x:55-118,
  146-193) with internal-source append.
- The custom-class registry (var.x:182-232, 331-430).
- Whole files: symbolset.x, string-classify.x, string-number.x,
  integer-ops.xmacro, native-scalar-types.xmacro, var-ledger.x,
  var-unbox.xmacro, var-adapters.xmacro, typed-list.x, list-generics.xmacro.

Survivor total: about 5,200 of the 10,000 lines.

## 6. Hard cases and how the design handles each

Each names the handling and the test that pins it (unittest/test-*.x).

1. Null vs void: encoding untouched; one `$value_valid` hook rejects void
   in every family (array/map_void_writes_transfer_before_mutation).
2. Wide boxes: VarWideBox keeps the family tag inside the box; List keys of
   boxes stay identity keys (list_assoc_hash_equal, var_wide_value_semantics).
3. Numeric total order with NaN/inf classes: verbatim
   (var_compare_numeric_total_order, var_compare_strict_encodings).
4. Mixed-signedness result tags and shifts: verbatim
   (var_arithmetic_pair_matrix, var_all_family_integral_matrix).
5. Failure atomicity: compute, convert, then store everywhere; Map's
   numeric-`+` predicate is the one hook that differs between Map
   (`Var.numeric_info(rhs.tag())`, map.x:361-366) and typed maps (always,
   map-generics.xmacro:485) (test-atomic-container.x, all six cases).
6. Map staged growth and backshift deletion: core survivor
   (map_growth_preserves_entries, map_collision_backshift_and_reuse,
   map_growth_survives_a_nested_region).
7. Context export: `$prepare_export` and the shared publish macro move or
   swap storage (map-generics.xmacro:824-852;
   typed_map_string_growth_traversal_and_errors); Map.export_to stays.
8. Custom rows past 30: cells keyed by descriptor and address, records
   with a descriptor prefix (var_dense_dispatch_past_direct_rows).
9. Folded-name descriptor collisions abort with both spellings
   (dispatch.x:441-455; var_builtin_dispatch_tags_match_registration).
10. Recursive rendering restored by defer on error
    (var_recursive_rendering, var_rendering_restores_after_error).
11. Pool lifetime of String and List identity graphs: untouched
    (list_pool_lifetime_boundary, string_noop_construction_preserves_owner).
12. Atom dual form and reader escapes: verbatim
    (atom_repr_round_trips_lisp_reader, atom_list_and_lisp_readers_canonicalize).
13. Typed native update traps (INT_MIN/-1, shift width, float
    `<bad-types>`): one `$typed.update.*` macro now serves arrays and typed
    map values (typed_array_update_faults_transfer,
    typed_map_integer_edges_and_failure_atomicity).
14. Slice normalization: one call, unchanged (slice_stop_beyond_length_
    clamps, slice_negative_step_at_length, empty_stepped_slice_is_empty).
15. String.format: same checks, table-driven integer conversions
    (string_checked_format_integers/floating/strings_and_boundaries/failures).
16. Symbol truncation and folding: verbatim (symbol_truncates_5bit_
    preferred, symbol_truncates_mixed_to_7bit).
17. List repr padding and wrapping: verbatim; compiler fixtures read it
    (var_nested_list_keeps_display_padding).
18. Buffer line state across unwrite and aliased growth: lazy recompute
    reads the final line from content, so neither needs a special case
    (buffer_unwrite_crosses_lines, buffer_self_alias_growth_preserves_line_state).
19. Large-list operations stay iterative (list_large_operations_are_iterative).
20. Compiler-emitted ABI: generated Array and Map methods keep the
    `Type.method` spellings, so Array_updateindex, Map_updateindex,
    Map_update_n, and Var_is_row do not move (section 1, item 20).

## 7. Experiments (against builds/0)

1. Baselines: `make bm-var bm-varops bm-string bm-list bm-block-buffer`
   (Makefile:357-436); keep the CSV rows. `make map-benchmark` and the
   direct runner for a frozen baseline binary.
2. Hook-inlining proof for C8: in a scratch lib/array.x, replace the
   hand-written index, push, insert, and remove methods with
   `$array.typed.family(Array, Var, void, "Array")` plus three hooks,
   build with `builds/0/bin/x2c`, run test-array, test-atomic-container,
   and test-index-slice through unittest/Makefile, then `make bm-varops`.
   Expected: all cases pass, array-existing-update within noise.
3. Same for Map: instantiate `$map.typed.family(Map, Var, Var, ...)` with
   the void-answer hook, run test-map and test-atomic-container, then
   compare.py with `--baseline-binary` the frozen production binary.
   Expected: checksums equal, deltas within the runner's stated
   several-percent noise for typed lanes.
4. Inline scalar boxing: change `$scalar` in common.x to emit the
   `$var.immediate` body, rebuild, run test-var and test-varops, then
   `make bm-var` with an added `box-int` row and
   `unittest/benchmarks/run-compiler-translation.sh`. Expected: box-int
   drops from a call to a few instructions; translation CSV moves only if
   boxing was measurable there.
5. Buffer lazy line state: implement in a scratch buffer.x, run
   test-buffer, then `make bm-block-buffer` and the translation CSV.
   Accept if indent-80 <= 2x and the translation CSV is flat.
6. Line count check: `wc -l` on the scratch files from 2-5 against the
   per-file numbers in section 3.

## 8. Drops (each with justification and lines saved)

- `Var.parse` (var.x:1235-1281, 48 lines): consumers are lib/var.x itself
  and three test files; the tokenizer and scan.x have their own readers.
- `x2c_register_descriptor`, `x2c_try_register_descriptor` collapsed into
  one, and `x2c_register_tagged_descriptor` into its try form
  (dispatch.x:136-207, ~50 lines): the no-result forms discard a status
  the caller can ignore; ten test files call the try forms and would keep
  compiling.
- Public `Var.fallback_str/repr/write_str/write_repr` (dispatch.x:506-
  515, 540-554, 575-584, 665-676; ~40 lines of doc surface): no consumer
  outside dispatch.x and varops.x.
- Public `Var.wide_hash/wide_equal/wide_compare` (var.x:1028-1084 docs,
  ~30 lines): private helpers of dispatch.x.
- `$var.tag.id.checks` and the hand-written TagId enum (var-tags.xmacro
  353-370, var.x:62-82; ~45 lines) once the compiler collects macro-
  generated declarations; otherwise kept.
- `List.subseq` alias of `List.getslice` and `Array.indexof` alias of
  `Array.find` (~25 lines): two names for one operation; the book changes.

Drops total about 240 lines; they are inside the 10,000 estimate.

## 9. Risks

- Comment density: the module pages are generated from doc comments, so
  the estimate keeps today's 30% density and takes credit for shorter
  comments only in string.x and list.x, where they repeat the guide.
- Policy hooks must inline; experiment 2 decides before any layer is
  deleted. A map-get regression above 1.1x is a defect, not a trade.
- The generated typed public API text is fixed by 433 documented
  callables; the shared publish/observe macros must reproduce every
  signature or the module pages and typed suites change.
- The shallow-collection duplicates (~100 lines, C1 and C6) go away only
  if the front-end design changes the compiler; counted as a cross-area
  claim, not in this area's total.
- lib/pool.x, scope.x, iter.x, and func.x were read only at their API;
  they bound canonicalization, wide-box ownership, Iter publication, and
  Func callbacks. A pool redesign moves the interning regions with it.
- Map section 6's declined ledger port (3.4x slower translation) is not
  re-proposed; the ledger stays a compile-time meta function.
- The reduction here is macro-generated public layers and tables, the
  direction the files already take; nothing refutes Gary's macro
  hypothesis for this area, and nothing confirms a large reduction from it.
