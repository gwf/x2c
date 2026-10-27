/*  var.x -- variant type for dynamic typing

    Copyright (c) 2025 Gary William Flake

    Var owns the one-word encoding of dynamic values. Doubles keep their IEEE
    754 bits, and the special-value ranges carry tagged payloads, native
    pointers, `Symbol`s, and boxes for wide scalars and custom classes. A
    `Var` preserves its runtime kind, and `void` is excluded from
    value-bearing protocols.
*/

#pragma once

#include "error-macros.x"
#include "common.x"

/** Describes one numeric `Var` family without holding a value.
    `tag` is canonical, `floating` and `unsigned_value` classify it, `bits` is
    its native payload width, and `rank` orders promotion. Callers normally
    obtain a valid record from `Var.numeric_info`.
*/
typedef struct X2CVarNumericInfo {
  Symbol tag, int floating, unsigned_value, bits, rank;
} X2CVarNumericInfo;

/** Holds a decoded numeric `Var` and its promotion metadata.
    Integer values use the low `bits` of `raw`, with signed values represented
    in two's-complement; floating values use `floating_value`. The record
    holds no storage and retains nothing from the source `Var`.
*/
typedef struct X2CVarNumeric {
  Symbol tag, int floating, unsigned_value, bits, rank;
  unsigned long long raw;
  long double floating_value;
} X2CVarNumeric;

float X2CVarNumeric.f32(X2CVarNumeric &value);
double X2CVarNumeric.f64(X2CVarNumeric &value);
long double X2CVarNumeric.ldouble(X2CVarNumeric &value);

#include "dispatch.x"

#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <assert.h>
#include <limits.h>

/** Names the built-in `Var` tags in `var-tags.x` ledger order, which
    is the order of `x2c_var_taginfo`; `lib/var-ledger.x` checks the two
    agree.
*/
typedef enum TagId {
  _invalid_ = -1,
  _u8_, _i8_, _u16_, _i16_, _u32_, _i32_, _f32_, _u48_, _i48_, _p48_, _f64_,
  _long_, _ulong_, _llong_, _ullong_, _ldouble_, _u8_p_, _i8_p_, _u16_p_,
  _i16_p_, _u32_p_, _i32_p_, _f32_p_, _ulong_p_, _long_p_, _f64_p_,
  _ullong_p_, _llong_p_, _ldouble_p_, _p48_p_, _u8_pp_, _i8_pp_, _u16_pp_,
  _i16_pp_, _u32_pp_, _i32_pp_, _f32_pp_, _ulong_pp_, _long_pp_, _f64_pp_,
  _ullong_pp_, _llong_pp_, _ldouble_pp_, _array_, _block_, _buffer_, _bytes_,
  _context_, _error_, _file_, _func_, _iter_, _lambda_, _list_, _logger_,
  _map_, _mutex_, _pipe_, _proc_, _regexp_, _rope_, _scope_, _slice_,
  _socket_, _stream_, _string_, _symbol_, _tensor_, _thread_, _token_, _var_,
  _array_p_, _block_p_, _buffer_p_, _bytes_p_, _context_p_, _error_p_,
  _file_p_, _func_p_, _iter_p_, _lambda_p_, _list_p_, _logger_p_, _map_p_,
  _mutex_p_, _pipe_p_, _proc_p_, _regexp_p_, _rope_p_, _scope_p_, _slice_p_,
  _socket_p_, _stream_p_, _string_p_, _symbol_p_, _tensor_p_, _thread_p_,
  _token_p_, _var_p_, _nan_, _neginf_, _posinf_, _void_,
  _tag_count_
} TagId;

/** Describes one built-in `Var` tag's kind and encoding fields. */
typedef struct VarTagInfo {
  Symbol tag, kind;
  unsigned long top, middle, bottom;
} VarTagInfo;

/** Resolves one encoding top: the selector is the middle field when
    `by_middle` is set and the bottom field under `mask` otherwise, and
    `ids` maps it to a `TagId`, or `_invalid_` where no tag has it.
*/
typedef struct VarDecodeGroup {
  unsigned char mask, by_middle;
  signed char ids[8];
} VarDecodeGroup;

/** Reports whether `tag` has a built-in encoding or declared custom class. */
int Var.known_tag(Symbol tag) =>
  _tag2id(tag) != _invalid_ || _declared(tag) != NULL;

#include <string.h>
#include "symbol.x"
#include "map/map.x"
#include "scope/scope.x"
#include "exception.x"
#include "string/string.x"
#include "symbolset.x"

extern const VarTagInfo x2c_var_taginfo[];
extern const SymbolSet x2c_var_tags;
extern const VarDecodeGroup x2c_var_decode_groups[];

#include "meta.x"

meta static Symbol _update_tag(List id)     => _update_row(id)[0];

meta static String _update_boxer(List id)   => _update_row(id)[1];

meta static String _update_decoder(List id) => _update_row(id)[2];

/* An empty cast entry means the source and destination types already agree. */
meta static List _update_cast_in(List id)  => _update_row(id)[3].car();

meta static List _update_cast_out(List id) => _update_row(id)[3].cdr().car();

/* The row the invocation's `<tag>` literal names. The capture is a literal,
   so its Symbol value is its last part. */
meta static List _update_row(List id) {
  match (id)
    case %(expr ? (literal ? ? ?key)): return _update_rows().assoc(key);
  return %();
}

/* One row per native integer and floating family. Each $native.update
   invocation reads its Var tag, boxing operations, and the casts for its
   two representation crossings. */

/* Keyed by the tag the invocation names. A row is the `Var` tag, the boxer,
   the decoder, and the cast pair: into the boxer's parameter type and back
   to the storage type, each empty where the two types already agree. */
meta static List _update_rows(void) => %(
  (char    (i8 "Var_box_i8" "Var_integer" (() (char))))
  (schar   (i8 "Var_box_i8" "Var_integer" ((char) (signed char))))
  (u8      (u8 "Var_box_u8" "Var_integer" (() ("uchar"))))
  (i16     (i16 "Var_box_i16" "Var_integer" (() (short))))
  (u16     (u16 "Var_box_u16" "Var_integer" (() ("ushort"))))
  (i32     (i32 "Var_box_i32_bits" "Var_integer" ((unsigned) (int))))
  (u32     (u32 "Var_box_u32" "Var_integer" (() ("uint"))))
  (long    (long "Var_box_long" "Var_long_value" (() ())))
  (ulong   (ulong "Var_box_ulong" "Var_ulong_value" (() ())))
  (llong   (llong "Var_box_long_long" "Var_long_long_value" (() ())))
  (ullong  (ullong "Var_box_ulong_long" "Var_ulong_long_value" (() ())))
  (f32     (f32 "Var_box_f32" "Var_decode_f32" (() ())))
  (f64     (f64 "Var_box_f64" "Var_decode_f64" (() ())))
  (ldouble (ldouble "Var_box_long_double" "Var_long_double_value" (() ())))
);

/* The destination's current value, boxed in the family the row names. */
meta static List _update_box(List id, List lhs) {
  List value = $!($lhs[0]);
  Type into = _update_cast_in(id);
  if (into) value = $!(($into)$value);
  return $!($(x2c_ident(_update_boxer(id)))($value));
}

/* The converted result read back as the storage type. */
meta static List _update_decode(List id, List value) {
  List decoded = $!($(x2c_ident(_update_decoder(id)))($value));
  Type back = _update_cast_out(id);
  if (back) return $!(($back)$decoded);
  return decoded;
}

/* The function's name for a raise payload. Built only when the raise runs,
   so the update path needs no cached String and no initialization check. */
meta static List _update_operation(Var function) {
  String spelling = Code.binding_spelling(function);
  return $!(String){ String.new($spelling) };
}

module {
  "encoding.x",
  "classes.x",
  "construction.x",
  "numbers.x",
  "ordering.x",
  "conversion.x",
  "operators.x",
}
