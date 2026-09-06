/*  typed-array.x -- packed typed `Array`s generated from shared methods

    Copyright (c) 2026 Gary William Flake

    Typed `Array`s own contiguous native storage over `Block`. Static
    element operations use native pointers. `Var` descriptors and `Iter` box a
    value only when it crosses into `Var`.

    Bracket indexing is raw. `array[index]` is an inline indexed access on
    the concrete element pointer. There is no bounds test and no
    negative-index normalization, so an index outside the elements has the
    same undefined behavior as the equivalent C pointer. Bound loops with
    `len`, and use `try_get` for a checked read.

    Numeric `array[index] += rhs` applies the generated C operator to native
    values, not a `Var` round trip; `ArrayString` uses canonical String
    concatenation. Integer promotions and result conversions follow C. Integer
    division by zero, invalid shifts, and unsupported operators still raise
    before changing the element; the boxed path's `<conv-range>` is absent.
*/

#pragma once
#include "x2c.x"
$(import "array-generics.xmacro")

#include <limits.h>
#include <string.h>

/** A mutable, `Scope`-owned packed `Array` of native `char` elements.
    Assignment shares its storage; `ArrayChar.copy` makes an independent copy.
*/
typedef Block ArrayChar;
/** A mutable, `Scope`-owned packed `Array` of native `short` elements.
    Assignment shares its storage; `ArrayShort.copy` makes an independent copy.
*/
typedef Block ArrayShort;
/** A mutable, `Scope`-owned packed `Array` of native `int` elements.
    Assignment shares its storage; `ArrayInt.copy` makes an independent copy.
*/
typedef Block ArrayInt;
/** A mutable, `Scope`-owned packed `Array` of native `long` elements.
    Assignment shares its storage; `ArrayLong.copy` makes an independent copy.
*/
typedef Block ArrayLong;
/** A mutable, `Scope`-owned packed `Array` of native `float` elements.
    Assignment shares its storage; `ArrayFloat.copy` makes an independent copy.
*/
typedef Block ArrayFloat;
/** A mutable, `Scope`-owned packed `Array` of native `double` elements.
    Assignment shares its storage; `ArrayDbl.copy` makes an independent copy.
*/
typedef Block ArrayDbl;
/** A mutable, `Scope`-owned packed `Array` of canonical `String` pointers.
    Assignment shares its storage; `ArrayString.copy` makes an independent
    shallow copy. Exporting an owned array recanonicalizes its Strings before
    replacing the backing storage while preserving the array's identity.
    Borrowed or outer-owned Strings must outlive the array.
*/
typedef Block ArrayString;

static void _bad_index(String owner, int index, size_t size) {
  raise %(bad-arg (owner $owner) (index $index) (size $size));
}

static void _bad_operation(String owner, Symbol operation) {
  raise %(bad-arg (owner $owner) (operation $operation));
}

static void _size_limit(String owner, size_t size) {
  raise %(size-limit (owner $owner) (size $size));
}

static void _bad_step(String owner, int step) {
  raise %(bad-arg (owner $owner) (step $step));
}

static int _array_compare_char(char a, char b) => (a > b) - (a < b);
static int _array_compare_short(short a, short b) => (a > b) - (a < b);
static int _array_compare_int(int a, int b) => (a > b) - (a < b);
static int _array_compare_long(long a, long b) => (a > b) - (a < b);
static int _array_compare_float(float a, float b) => Var.compare(a, b);
static int _array_compare_double(double a, double b) => Var.compare(a, b);
static int _array_compare_string(String a, String b) => a.compare(b);
static Buffer _array_new_buffer(void) => Buffer.new(0);
static String _array_finish_buffer(Buffer out) => out.str_free();

static Block _prepare_array_export(Block array, Context source) {
  (void) array; (void) source;
  return NULL;
}

static ArrayString _prepare_string_array_export(
  ArrayString array, Context source) {
  ArrayString staged = ArrayString.new(), result = NULL;
  defer if ((void *) result == NULL) staged.free();
  Block_reserve((Block) staged, array.cap);
  String *data = array.bytes;
  for (size_t i = 0; i < array.length; i++) {
    String value = source.export_nested(data[i]);
    Block_append((Block) staged, &value, 1);
  }
  return result = staged;
}

$array.core.family(ArrayChar, char);
$array.typed.family(ArrayChar, char, 0, "ArrayChar");
$array.typed.observe(
  ArrayChar, char, "ArrayChar", _array_compare_char,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.integer(ArrayChar, char, uchar);
$array.typed.publish(
  ArrayChar, char, arraychar, <arraychar>, _prepare_array_export);

$array.core.family(ArrayShort, short);
$array.typed.family(ArrayShort, short, 0, "ArrayShort");
$array.typed.observe(
  ArrayShort, short, "ArrayShort", _array_compare_short,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.integer(ArrayShort, short, ushort);
$array.typed.publish(
  ArrayShort, short, arrayshort, <arrayshort>, _prepare_array_export);

$array.core.family(ArrayInt, int);
$array.typed.family(ArrayInt, int, 0, "ArrayInt");
$array.typed.observe(
  ArrayInt, int, "ArrayInt", _array_compare_int,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.integer(ArrayInt, int, uint);
$array.typed.publish(
  ArrayInt, int, arrayint, <arrayint>, _prepare_array_export);

$array.core.family(ArrayLong, long);
$array.typed.family(ArrayLong, long, 0L, "ArrayLong");
$array.typed.observe(
  ArrayLong, long, "ArrayLong", _array_compare_long,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.integer(ArrayLong, long, ulong);
$array.typed.publish(
  ArrayLong, long, arraylong, <arraylong>, _prepare_array_export);

$array.core.family(ArrayFloat, float);
$array.typed.family(ArrayFloat, float, 0.0f, "ArrayFloat");
$array.typed.observe(
  ArrayFloat, float, "ArrayFloat", _array_compare_float,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.floating(ArrayFloat, float);
$array.typed.publish(
  ArrayFloat, float, arrayfloat, <arrayfloat>, _prepare_array_export);

$array.core.family(ArrayDbl, double);
$array.typed.family(ArrayDbl, double, 0.0, "ArrayDbl");
$array.typed.observe(
  ArrayDbl, double, "ArrayDbl", _array_compare_double,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.floating(ArrayDbl, double);
$array.typed.publish(
  ArrayDbl, double, arraydbl, <arraydbl>, _prepare_array_export);

$array.core.family(ArrayString, String);
$array.typed.family(ArrayString, String, 0, "ArrayString");
$array.typed.observe(
  ArrayString, String, "ArrayString", _array_compare_string,
  _array_new_buffer, _array_finish_buffer);
$array.typed.update.string(ArrayString);
$array.typed.publish(
  ArrayString, String, arraystring, <arraystr>,
  _prepare_string_array_export);

/* These declarations stay literal because method metadata is collected
   before the family macros expand. Keeping them after the expansions also
   keeps generated diagnostic locations tied to the family invocations. */
Self ArrayChar.copy(Self);
Self ArrayChar.getslice(Self, int, int, int);
Self ArrayChar.setslice(Self, int, int, Self);
Self ArrayChar.remslice(Self, int, int);
Self ArrayChar.splice(Self, int, int, Self);
Self ArrayChar.concat(Self, Self);
Self ArrayChar.reverse(Self);

Self ArrayShort.copy(Self);
Self ArrayShort.getslice(Self, int, int, int);
Self ArrayShort.setslice(Self, int, int, Self);
Self ArrayShort.remslice(Self, int, int);
Self ArrayShort.splice(Self, int, int, Self);
Self ArrayShort.concat(Self, Self);
Self ArrayShort.reverse(Self);

Self ArrayInt.copy(Self);
Self ArrayInt.getslice(Self, int, int, int);
Self ArrayInt.setslice(Self, int, int, Self);
Self ArrayInt.remslice(Self, int, int);
Self ArrayInt.splice(Self, int, int, Self);
Self ArrayInt.concat(Self, Self);
Self ArrayInt.reverse(Self);

Self ArrayLong.copy(Self);
Self ArrayLong.getslice(Self, int, int, int);
Self ArrayLong.setslice(Self, int, int, Self);
Self ArrayLong.remslice(Self, int, int);
Self ArrayLong.splice(Self, int, int, Self);
Self ArrayLong.concat(Self, Self);
Self ArrayLong.reverse(Self);

Self ArrayFloat.copy(Self);
Self ArrayFloat.getslice(Self, int, int, int);
Self ArrayFloat.setslice(Self, int, int, Self);
Self ArrayFloat.remslice(Self, int, int);
Self ArrayFloat.splice(Self, int, int, Self);
Self ArrayFloat.concat(Self, Self);
Self ArrayFloat.reverse(Self);

Self ArrayDbl.copy(Self);
Self ArrayDbl.getslice(Self, int, int, int);
Self ArrayDbl.setslice(Self, int, int, Self);
Self ArrayDbl.remslice(Self, int, int);
Self ArrayDbl.splice(Self, int, int, Self);
Self ArrayDbl.concat(Self, Self);
Self ArrayDbl.reverse(Self);

Self ArrayString.copy(Self);
Self ArrayString.getslice(Self, int, int, int);
Self ArrayString.setslice(Self, int, int, Self);
Self ArrayString.remslice(Self, int, int);
Self ArrayString.splice(Self, int, int, Self);
Self ArrayString.concat(Self, Self);
Self ArrayString.reverse(Self);
