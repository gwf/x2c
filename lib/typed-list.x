/*  typed-list.x -- typed cons chains generated from typed methods

    Copyright (c) 2026 Gary William Flake

    A typed list is a `List` whose car always carries one known `Var` tag. It
    shares `List`'s canonical pool, so a typed chain and the plain literal that
    spells it are the same cells, and a typed `cons` finds a cell an untyped
    `cons` already built.

    A typed chain costs what an untyped one costs. `cons` searches the pool
    and, on a miss, allocates and inserts a cell. `ArrayInt.push` copies an
    element into contiguous storage. Use `typed-array.x` for indexing or bulk
    numeric storage, and typed lists for shared tails and canonical identity.

    There is no long family. `Var.box_long` allocates a `Scope`-owned box, so a
    cell outliving that scope would hold a dangling car, and `List.equal`
    compares car bits. Two boxes of one number differ, so every cons would
    miss and the interning table would grow without bound.
*/

#pragma once
#include "x2c.x"

/*  typed-list.x -- typed views over canonical List cells

    Copyright (c) 2026 Gary William Flake

    A typed list is a List. Its cells are interned cons cells whose car
    always carries one known Var tag, so the interning pool, hashing,
    equality, printing, and comparison are List's own and need no generated
    code. `List.hash` reads the raw car bits and the cdr pointer;
    `List.equal` compares them; neither consults the tag.

    Receiver-relative List methods retain the typed spelling for operations
    that never inspect an element. The typed family supplies the operations
    that do. It reads and writes the car through the cheap encoding for its
    tag instead of `Var.new` and `Var.integer`.

    The typed family does not adopt `protocol Var`. A typed list inherits
    `List.var`, so boxing and native Func checks already use `<list>`. An
    `as List` adoption would only declare Var participation; it would not add
    typed bracket indexing. Widen to List for operations whose Var callbacks
    can replace elements.
*/

static macro Unit $list.typed.family(Type $list, Type $element,
  Name $encode, Name $decode, Literal $tag, Name $lower,
  Expr $zero, Literal $owner
) {
  $element $list.car($list);
  $list $list.cons($element, $list);
  $element $list.last($list);
  int $list.index($list, $element);
  $list List.$lower(List);
  $list Var.$lower(Var);

  /* `car` and `last` of nil are void, whose bits are all ones, so the guard
     decides the answer instead of avoiding a null read. Reading a nil end as
     $zero follows the runtime's silent-reader convention: an empty list
     terminates a loop and is not a caller error. */
  /** Returns the first `$element` in `xs`, or `$zero` when `xs` is `nil`.
      A nonempty `xs` must retain the `$list` element-tag invariant.
  */
  inline $element $list.car($list xs) {
    return xs ? $decode(((List) xs).car) : $zero;
  }

  /** Returns the canonical `$list` formed by prepending `value` to `tail`.
      The immutable tail is shared. The result follows the lifetime of its
      owning canonical `List` pool, which may be an ancestor of the current
      pool when an existing cell is reused.

      Raises: `<alloc-fail>` or `<size-limit>` while installing a new
      canonical cell.
  */
  inline $list $list.cons($element value, $list tail) {
    return ($list) cons($encode(value), (List) tail);
  }

  /** Returns the final `$element` in `xs`, or `$zero` when `xs` is `nil`,
      after an O(n) walk.
      A nonempty `xs` must retain the `$list` element-tag invariant.
  */
  $element $list.last($list xs) {
    return xs ? $decode(List.last((List) xs)) : $zero;
  }
  /** Returns the first zero-based index of `value`, or -1 when absent. */
  int $list.index($list xs, $element value) {
    return List.index((List) xs, $encode(value));
  }

  /* Zero copy. Typed-ness here is a predicate over an immutable value, not
     a storage layout. Cells are interned and never mutated, so a chain that
     validates once cannot later hold another element. ArrayInt has to copy:
     its source Array has a different element width and is mutable. */
  /** Validates `xs` as `$list` and returns the identical canonical chain.
      Nil is valid. Every nonempty cell must hold a `$tag` element; a foreign
      tag raises `<no-convert>` with its zero-based index. Validation is O(n),
      does not copy or mutate cells, and preserves their existing `List`-pool
      lifetime.

      Raises: `<no-convert>` for the first foreign element. */
  $list List.$lower(List xs) {
    int index = 0;
    for (List cur = xs; cur; cur = cur.cdr()) {
      if (!_typed_list_holds(cur.car, $tag))
        _no_convert($owner, index, cur.car.tag());
      index++;
    }
    return ($list) xs;
  }

  /* Without this the compiler resolves the typedef to a pointer and emits a
     bare `Var_pointer`, so any Var would become a typed list. */
  /** Extracts and validates `value` as `$list` without copying its cells.
      A `Var` without the `<list>` tag becomes `nil`. A `List`
      payload follows the
      same element validation, identity, and lifetime rules as `List.$lower`.

      Raises: `<no-convert>` for the first foreign element. */
  $list Var.$lower(Var value) {
    List xs = value.list();
    return xs.$lower();
  }
}


#include <string.h>

/** Typed view of canonical `List` cells whose cars are `<i8>` char values. */
typedef List ListChar;
/** Typed view of canonical `List` cells whose cars are `<i16>` short values.
*/
typedef List ListShort;
/** Typed view of canonical `List` cells whose cars are `<i32>` int values. */
typedef List ListInt;
/** Typed view of canonical `List` cells whose cars are `<f32>` float values.
*/
typedef List ListFloat;
/** Typed view of canonical `List` cells whose cars are `<f64>` double values.
*/
typedef List ListDbl;
/** Typed view of canonical `List` cells whose cars are `<string>` `String`s.
*/
typedef List ListString;
/** Typed view of canonical `List` cells whose cars are `<symbol>` `Symbol`s.
*/
typedef List ListSymbol;

static void _no_convert(String owner, int index, Symbol tag) {
  raise %(no-convert (operation $owner) (index $index) (tag $tag));
}

/* Reports whether `value` decodes as the element type `tag` names.
   `Var.box_f64` gives the infinities and NaN their own tags, so a double
   element arrives under four tags and `Var.decode_f64` reads all four. Every
   other family stores exactly one tag. */
static int _typed_list_holds(Var value, Symbol tag) {
  Symbol found = value.tag();
  if (found == tag) return 1;
  return tag == <f64> &&
    (found == <+inf> || found == <-inf> || found == <nan>);
}

/* Encoders and decoders are inline because the generated `car` and `cons`
   are, and an inline body cannot call a function the header does not carry.
   Each pair is the Var layout for one tag with the dispatch removed: the
   32-bit families are a mask and an OR against a fixed prefix, and Symbol is
   an add and a subtract. */

inline Var _typed_list_encode_i8(char value) => Var.box_i8(value);
inline char _typed_list_decode_i8(Var value) => (char) (value.u64 & 0xFFul);
inline Var _typed_list_encode_i16(short value) => Var.box_i16(value);
inline short _typed_list_decode_i16(Var value) =>
  (short) (value.u64 & 0xFFFFul);
inline Var _typed_list_encode_i32(int value) =>
  Var.box_i32_bits((unsigned) value);
inline int _typed_list_decode_i32(Var value) =>
  (int) (value.u64 & 0xFFFFFFFFul);
inline Var _typed_list_encode_f32(float value) => Var.box_f32(value);
inline float _typed_list_decode_f32(Var value) {
  unsigned raw = (unsigned) (value.u64 & 0xFFFFFFFFul);
  float result;
  memcpy(&result, &raw, sizeof result);
  return result;
}
inline Var _typed_list_encode_f64(double value) => Var.box_f64(value);
inline double _typed_list_decode_f64(Var value) => value.decode_f64();
/* String keeps a checked read. Its payload is a pointer, so a masked read of
   the wrong tag is a wild pointer rather than a wrong scalar. */
inline Var _typed_list_encode_string(String value) {
  unsigned long raw = (unsigned long) (uintptr_t) value;
  return (Var) { .u64 = VAR_STRING_PREFIX | raw };
}
inline String _typed_list_decode_string(Var value) => value;
inline Var _typed_list_encode_symbol(Symbol value) =>
  (Var) { .u64 = value + VAR_SYMBOL_OFFSET };
inline Symbol _typed_list_decode_symbol(Var value) =>
  (Symbol) (value.u64 - VAR_SYMBOL_OFFSET);
$list.typed.family(
  ListChar, char, _typed_list_encode_i8, _typed_list_decode_i8,
  <i8>, listchar, 0, "ListChar");

$list.typed.family(
  ListShort, short, _typed_list_encode_i16, _typed_list_decode_i16,
  <i16>, listshort, 0, "ListShort");

$list.typed.family(
  ListInt, int, _typed_list_encode_i32, _typed_list_decode_i32,
  <i32>, listint, 0, "ListInt");

$list.typed.family(
  ListFloat, float, _typed_list_encode_f32, _typed_list_decode_f32,
  <f32>, listfloat, 0.0f, "ListFloat");

$list.typed.family(
  ListDbl, double, _typed_list_encode_f64, _typed_list_decode_f64,
  <f64>, listdbl, 0.0, "ListDbl");

$list.typed.family(
  ListString, String, _typed_list_encode_string, _typed_list_decode_string,
  <string>, liststring, NULL, "ListString");

$list.typed.family(
  ListSymbol, Symbol, _typed_list_encode_symbol, _typed_list_decode_symbol,
  <symbol>, listsymbol, 0, "ListSymbol");
