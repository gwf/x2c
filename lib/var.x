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
#include "dispatch.x"

#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <assert.h>
#include <limits.h>

/** Names the built-in `Var` tags in `var-tags.x` ledger order, which
    is the order of `x2c_var_taginfo`; `lib/var-ledger.x` checks the two
    agree. */
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
    `ids` maps it to a `TagId`, or `_invalid_` where no tag has it. */
typedef struct VarDecodeGroup {
  unsigned char mask, by_middle;
  signed char ids[8];
} VarDecodeGroup;

/** Reports whether `tag` has a built-in encoding or declared custom class. */
int Var.known_tag(Symbol tag) =>
  _tag2id(tag) != _invalid_ || _declared(tag) != NULL;

#include <string.h>
#include "symbol.x"
#include "map.x"
#include "scope.x"
#include "exception.x"
#include "string-number.x"
#include "symbolset.x"

extern const VarTagInfo x2c_var_taginfo[];
extern const SymbolSet x2c_var_tags;
extern const VarDecodeGroup x2c_var_decode_groups[];

module {
  "var/encoding.x",
  "var/classes.x",
  "var/construction.x",
  "var/numbers.x",
  "var/ordering.x",
}
