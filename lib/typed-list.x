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
$(import "list-generics.xmacro")

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
  raise %(no-convert (owner $owner) (index $index) (tag $tag));
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
