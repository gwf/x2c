/*  common.x -- the shared `Var` union and operations used by every module

    Copyright (c) 2025 Gary William Flake

    Every runtime module includes this one. It defines the eight-byte `Var`
    union itself, the compile-time assertions that pin the native type
    sizes the encoding depends on, the `Symbol` outcome names that
    status returning APIs share, and the declarations that let modules
    name each other without an include cycle. It also defines immediate
    scalar boxing, runtime startup, and shared index normalization.
    Pointer-shaped `Var` extractors are ABI crossings whose callers establish
    the advertised source kind; scalar readers instead convert nonmatching
    numeric tags through `Var.convert`.  */

#pragma once

$(import "error-macros.xmacro")

#include <float.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

/** Eight-byte tagged runtime value for immediate scalars and encoded handles.
    Pointer-bearing values follow the ownership rules of their concrete type;
    raw `Null` is all zero bits and `void` is all one bits.
*/
typedef union Var {
  unsigned long u64;
  double f64, void *p64;
} Var;

typedef char x2c_var_abi_byte[(CHAR_BIT == 8) ? 1 : -1];
typedef char x2c_var_abi_signed_char[
  (CHAR_MIN == -128 && CHAR_MAX == 127) ? 1 : -1];
typedef char x2c_var_abi_short[(sizeof(short) == 2) ? 1 : -1];
typedef char x2c_var_abi_ushort[(sizeof(unsigned short) == 2) ? 1 : -1];
typedef char x2c_var_abi_int[(sizeof(int) == 4) ? 1 : -1];
typedef char x2c_var_abi_uint[(sizeof(unsigned) == 4) ? 1 : -1];
typedef char x2c_var_abi_short_range[
  (SHRT_MAX == 0x7fff && SHRT_MIN == -0x7fff - 1 &&
   USHRT_MAX == 0xffffU) ? 1 : -1];
typedef char x2c_var_abi_int_range[
  (INT_MAX == 0x7fffffff && INT_MIN == -0x7fffffff - 1 &&
   UINT_MAX == 0xffffffffU) ? 1 : -1];
typedef char x2c_var_abi_float[(sizeof(float) == 4) ? 1 : -1];
typedef char x2c_var_abi_double[(sizeof(double) == 8) ? 1 : -1];
typedef char x2c_var_abi_ulong[(sizeof(unsigned long) == 8) ? 1 : -1];
typedef char x2c_var_abi_long_long[(sizeof(long long) == 8) ? 1 : -1];
typedef char x2c_var_abi_long_range[
  (LONG_MAX == 0x7fffffffffffffffL &&
   LONG_MIN == -0x7fffffffffffffffL - 1L &&
   ULONG_MAX == 0xffffffffffffffffUL) ? 1 : -1];
typedef char x2c_var_abi_long_long_range[
  (LLONG_MAX == 0x7fffffffffffffffLL &&
   LLONG_MIN == -0x7fffffffffffffffLL - 1LL &&
   ULLONG_MAX == 0xffffffffffffffffULL) ? 1 : -1];
typedef char x2c_var_abi_pointer[(sizeof(void *) == 8) ? 1 : -1];
typedef char x2c_var_abi_storage[(sizeof(Var) == 8) ? 1 : -1];
typedef char x2c_var_abi_float_ieee[
  (FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MAX_EXP == 128) ? 1 : -1];
typedef char x2c_var_abi_double_ieee[
  (DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024) ? 1 : -1];

/** Data pointer into `Block`-owned raw element storage. */
typedef void *Bytes;
/** Opaque handle to `Scope`-owned mutable fixed-width storage. */
typedef struct Block *Block;
/** Opaque handle to a `Scope`-owned mutable text builder. */
typedef struct Buffer *Buffer;
/** Immediate compact name encoding with no allocation ownership. */
typedef unsigned long Symbol;
/** Borrowed immutable compiler-generated set of compact `Symbol`s. */
typedef unsigned char *SymbolSet;
/** Exact-name `Var` using a `Symbol` or a pooled canonical long spelling. */
typedef Var Atom;
/** `Scope`-owned mutable `Block` view whose elements are `Var`s. */
typedef Block Array;
/** Immutable canonical cons chain; NULL is `nil`.
    Its lifetime follows its owning `List` pool, which may be an ancestor.
*/
typedef struct List *List;
/** Region owner for individually tracked runtime allocations. */
typedef struct Scope *Scope;
/** `Scope`-owned mutable table mapping `Var` keys to `Var` values. */
typedef struct Map *Map;
/** Nested canonicalization table with `Scope`-backed object storage. */
typedef struct Pool *Pool;
/** Bounded `Scope`, `Error`, `Match`, and optional canonical-pool state. */
typedef struct Context *Context;
/** `Scope`-owned opaque mutex that must outlive every accessing thread. */
typedef struct Mutex *Mutex;
/** Caller-owned handle to a `Context`-backed worker.
    Join the worker before freeing the handle.
*/
typedef struct Thread *Thread;
/** `Scope`-owned generic native-call adapter and optional bound context. */
typedef struct Func *Func;
/** Immutable canonical NUL-terminated bytes; NULL is the empty `String`.
    Its lifetime follows its owning `String` pool, which may be an ancestor.
*/
typedef char *String;
/** Native stdio stream handle whose opener determines close ownership. */
typedef FILE *File;
/** Mutable traversal state whose sources must outlive its iteration. */
typedef struct Iter *Iter;
// native aliases
/** Unsigned native character type. */
typedef unsigned char uchar;
/** Unsigned native short type. */
typedef unsigned short ushort;
/** Unsigned native int type. */
typedef unsigned int uint;
/** Unsigned native long type. */
typedef unsigned long ulong;

/** Renders one `Var` as a display or readable `String`. */
typedef String (*VarStrFn)(Var);
/** Appends one `Var` rendering to a caller-owned `Buffer` and returns it. */
typedef Buffer (*VarWriteFn)(Var, Buffer);
/** Computes one `Var` hash; `Var.hash` normalizes a zero result. */
typedef unsigned (*VarHashFn)(Var);
/** Reports value equality for two `Var`s with the same descriptor. */
typedef int (*VarEqualFn)(Var, Var);
/** Initializes traversal in caller-provided `Iter` storage and returns it.
    The storage and any retained receiver state must outlive traversal.
*/
typedef Iter (*VarIterIntoFn)(Var, Iter);
/** Returns negative, zero, or positive for two `Var`s of one descriptor. */
typedef int (*VarCompareFn)(Var, Var);
/** Reports whether a `Var` is true. */
typedef int (*VarTruthFn)(Var);
/** Reports whether `receiver` contains `needle`. */
typedef int (*VarContainsFn)(Var receiver, Var needle);
/** Applies one descriptor-owned binary operation and returns its result. */
typedef Var (*VarBinaryFn)(Var lhs, Var rhs);
/** Applies one descriptor-owned unary operation and returns its result. */
typedef Var (*VarUnaryFn)(Var value);
/** Reads one dynamically indexed value. */
typedef Var (*VarGetIndexFn)(Var receiver, Var key);
/** Stores an indexed value and returns the assignment result. */
typedef Var (*VarSetIndexFn)(Var receiver, Var key, Var value);
/** Applies an indexed compound operation and returns the stored result. */
typedef Var (*VarUpdateIndexFn)(Var receiver, Var key, Symbol op, Var rhs);
/** Applies an indexed postfix operation and returns the prior value. */
typedef Var (*VarPostfixIndexFn)(Var receiver, Var key, Symbol op);
/** Exports a custom value from `source` into its destination `Context`.
    Implementations move owned storage and recursively export nested values.
*/
typedef Var (*VarExportContextFn)(Var value, Context source);

/* Compiler-generated TYPE.shutdown registration crosses every runtime unit.
   Declare the C ABI here instead of adding a second x2c method for it. */
void Scope_shutdown_hook(void (*hook)(void));

/** Sparse process-global callback row for one `Var` descriptor.
    Registration stores each non-NULL function pointer without ownership and
    leaves existing slots unchanged for NULL fields. Callback code must remain
    loaded until its pointer is replaced or the process ends. Callbacks run
    synchronously when their operation dispatches; registration invokes none
    and retains no callback context.
*/
typedef struct VarMethods {
  VarStrFn str, repr, VarHashFn hash, VarEqualFn equal, VarCompareFn compare;
  VarTruthFn truth, VarIterIntoFn iter, VarWriteFn write_str, write_repr;
  VarContainsFn contains, VarBinaryFn add, sub, mul, div, mod, VarUnaryFn neg;
  VarGetIndexFn getindex, VarSetIndexFn setindex, VarUpdateIndexFn updateindex;
  VarPostfixIndexFn postfixindex, VarExportContextFn export_context;
} VarMethods;

#include "protocols.x"

/* Compiler-emitted raises cross every runtime unit through this ABI. */
/** Borrowed source location supplied during one compiler-generated raise.
    The pointed-to file and function spellings must outlive that call.
*/
typedef struct X2CErrorSite {
  const char *file, *function, int line;
} X2CErrorSite;

#define X2C_CLEANUP_EXIT_NORMAL   0
#define X2C_CLEANUP_EXIT_RETURN   1
#define X2C_CLEANUP_EXIT_BREAK    2
#define X2C_CLEANUP_EXIT_CONTINUE 3
#define X2C_CLEANUP_EXIT_GOTO     4

#define VAR_NULL_BITS 0ul
#define VAR_VOID_BITS 0xFFFFFFFFFFFFFFFFul
#define VAR_I8_PREFIX  0x8002000200000000ul
#define VAR_U8_PREFIX  0x8002000100000000ul
#define VAR_I16_PREFIX 0x8002000400000000ul
#define VAR_U16_PREFIX 0x8002000300000000ul
#define VAR_I32_PREFIX 0x8002000600000000ul
#define VAR_U32_PREFIX 0x8002000500000000ul
#define VAR_F32_PREFIX 0x8002000700000000ul
#define VAR_LIST_PREFIX 0x0009000000000004ul
#define VAR_STRING_PREFIX 0x000B000000000001ul
#define VAR_SYMBOL_OFFSET 0x8004000000000000ul
#define VAR_NAN_BITS   0x8003000100000000ul
#define VAR_NEGINF_BITS 0x8003000200000000ul
#define VAR_POSINF_BITS 0x8003000300000000ul
#define VAR_F64_SHIFT          (1ul << 52)
#define VAR_F64_NEG_MAX_RAW    0xFFEFFFFFFFFFFFFFul
#define VAR_F64_NEG_MAX_ESCAPE 0x8003000400000000ul

void x2c_scope_thread_release(void);
void x2c_match_thread_release(void);
void x2c_thread_state_release(void);
Pool x2c_pool_values_current(void);
void x2c_pool_values_initialize(void);
void x2c_pool_values_thread_initialize(void);
void x2c_pool_values_shutdown(void);
Pool x2c_pool_values_retain_named(const char *name);
Pool x2c_pool_values_retain(void);
void x2c_pool_values_release(void);
Pool x2c_pool_values_detach(void);
int x2c_pool_values_is_permanent(Var value);
void x2c_pool_thread_start(void);
void x2c_descriptor_thread_start_begin(void);
void x2c_descriptor_thread_start_end(int success);
int x2c_descriptor_registration_frozen(void);

/* Read on every cleanup and error path, including generated defer regions,
   so they are the storage rather than an accessor over it. */
extern threaded int x2c_cleanup_exit_kind, x2c_error_runtime_ready;

extern File Stdin, Stdout, Stderr;
extern Var Void;
extern List nil;

int Var.is(Var v, Symbol tag);
Symbol Var.kind(Var v);

// Var conversions

void *Var.pointer(Var var);
long Var.integer(Var v);
double Var.floating(Var v);
int Var.integer_compare(Var a, Var b);
int Var.integer_floating_compare(Var integer, Var floating);
unsigned Var.wide_hash(Var v);
int Var.wide_equal(Var a, Var b);
int Var.wide_compare(Var a, Var b);
long Var.long_value(Var v);
unsigned long Var.ulong_value(Var v);
long long Var.long_long_value(Var v);
unsigned long long Var.ulong_long_value(Var v);
long double Var.long_double_value(Var v);
Var Var.box_long(long value);
Var Var.box_ulong(unsigned long value);
Var Var.box_long_long(long long value);
Var Var.box_ulong_long(unsigned long long value);
Var Var.box_long_double(long double value);

String Var.str(Var v);
String Var.repr(Var v);
String Var.fallback_str(Var v);
String Var.fallback_repr(Var v);
Buffer Var.fallback_write_str(Var v, Buffer out);
Buffer Var.write_str(Var v, Buffer out);
Buffer Var.fallback_write_repr(Var v, Buffer out);
Var Var.new(Symbol tag, ...);
Symbol Symbol.new(const char *);
String String.new(const char *);
String String.join(String, List);
List Var.cons(Var, List);
List List.cons(Var, List);
List cons(Var, List);

String Array.str(Array);
String Array.repr(Array);
Buffer Array.write_str(Array, Buffer);
Buffer Array.write_repr(Array, Buffer);
int Array.equal(Array, Array);
int Array.compare(Array, Array);
Iter Array.iter(Array, Iter);
int Array.contains(Array, Var);
Var Array.getindex(Array, int);
Var Array.setindex(Array, int, Var);
Var Array.updateindex(Array, int, Symbol, Var);
Var Array.postfixindex(Array, int, Symbol);

String Buffer.str(Buffer);
String Buffer.repr(Buffer);
int Buffer.truth(Buffer);

int Block.truth(Block);
void Block.free(Block);

String File.str(File);
String File.repr(File);
Buffer File.write_repr(File, Buffer);
unsigned File.hash(File f);
int File.equal(File, File);
Iter File.iter(File, Iter);

Iter Iter.iter(Iter, Iter);

String List.str(List);
String List.repr(List);
Buffer List.write_str(List, Buffer);
Buffer List.write_repr(List, Buffer);
unsigned List.hash(List l);
int List.equal(List, List);
int List.compare(List, List);
Iter List.iter(List, Iter);
int List.contains(List, Var);
Var List.getindex(List, int);

String Map.str(Map);
String Map.repr(Map);
Buffer Map.write_str(Map, Buffer);
Buffer Map.write_repr(Map, Buffer);
int Map.equal(Map, Map);
int Map.compare(Map, Map);
int Map.truth(Map);
Iter Map.iter(Map, Iter);
Iter Map.keys(Map, Iter);
Iter Map.enumerate(Map, Iter);
int Map.contains(Map, Var);
Var Map.getindex(Map, Var);
Var Map.setindex(Map, Var, Var);
Var Map.updateindex(Map, Var, Symbol, Var);
Var Map.postfixindex(Map, Var, Symbol);

String String.str(String);
String String.repr(String);
Buffer String.write_str(String, Buffer);
Buffer String.write_repr(String, Buffer);
unsigned String.hash(String s);
int String.equal(String, String);
int String.compare(String, String);
Iter String.iter(String, Iter);
int String.contains(String, String);
int String.getindex(String, int);

String Symbol.str(Symbol);
String Symbol.repr(Symbol);
Buffer Symbol.write_str(Symbol, Buffer);
Buffer Atom.write_str(Atom, Buffer);
Buffer Symbol.write_repr(Symbol, Buffer);
int Symbol.compare(Symbol, Symbol);

unsigned Var.hash(Var v);
unsigned Var.fallback_hash(Var v);
int Var.equal(Var a, Var b);
int Var.fallback_equal(Var a, Var b);
int Var.same(Var a, Var b);
int Var.compare(Var a, Var b);
int Var.fallback_compare(Var a, Var b);

Var Var.convert(Var value, Symbol target);
int Var.truth(Var value);
int Var.truthy(Var value);
int Var.fallback_truth(Var value);
Iter Var.fallback_iter(Var value, Iter dest);
int Var.contains(Var value, Var needle);
Var Var.add(Var lhs, Var rhs);
Var Var.sub(Var lhs, Var rhs);
Var Var.mul(Var lhs, Var rhs);
Var Var.div(Var lhs, Var rhs);
Var Var.mod(Var lhs, Var rhs);
Var Var.neg(Var value);
Var Var.getindex(Var value, Var key);
Var Var.setindex(Var value, Var key, Var replacement);
Var Var.updateindex(Var value, Var key, Symbol op, Var rhs);
Var Var.postfixindex(Var value, Var key, Symbol op);
Var Var.binary(Var lhs, Symbol op, Var rhs);
Var Var.update(Var *lhs, Symbol op, Var rhs);
Var Var.postfix(Var *lhs, Symbol op);

/** Returns nonzero when `iter` is not null. */
inline int Iter.truth(Iter iter) => iter != NULL;

/** Returns nonzero when `list` is not `nil`. */
inline int List.truth(List list) => list != NULL;

/** Returns nonzero when `string` contains at least one byte. */
inline int String.truth(String string) => string != NULL && *string != '\0';

/** Avalanches one 64-bit word.
    This is MurmurHash3's fmix64 finalizer, the shared mixer behind every
    fixed-width hash in the runtime. It is six instructions, and its low bits
    are as well distributed as its high ones, which is what `Map` masks. Use
    `x2c_hash_bytes` for a block that spans several words.
*/
inline unsigned long x2c_mix64(unsigned long word) {
  word ^= word >> 33;
  word *= 0xff51afd7ed558ccdul;
  word ^= word >> 33;
  word *= 0xc4ceb9fe1a85ec53ul;
  word ^= word >> 33;
  return word;
}

/** Narrows a mixed word to the nonzero 32-bit hash the tables expect.
    Zero is reserved to mark an empty bucket, so it maps to all ones.
*/
inline unsigned x2c_hash_word(unsigned long word) {
  unsigned hash = (unsigned) x2c_mix64(word);
  return hash ? hash : -1;
}

/** Hashes an arbitrary byte block through the shared 64-bit mixer.
    `seed` distinguishes callers that hash the same bytes under different
    types; the byte width distinguishes a final partial word from zero
    padding.
*/
inline unsigned x2c_hash_bytes(
  unsigned long seed, const void *data, size_t width) {
  const unsigned char *bytes = data;
  unsigned long mixed = x2c_mix64(seed ^ (unsigned long) width);
  for (size_t offset = 0; offset < width; offset += sizeof(unsigned long)) {
    unsigned long word = 0;
    size_t remaining = width - offset;
    memcpy(
      &word, bytes + offset,
      remaining < sizeof word ? remaining : sizeof word);
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    word = __builtin_bswap64(word);
#endif
    mixed = x2c_mix64(mixed ^ word);
  }
  return x2c_hash_word(mixed);
}

// builtins to Var

/** Reports whether `v` uses a scope-owned wide numeric box. */
inline int Var.is_wide(Var v) {
  unsigned top = v.u64 >> 48, bottom = v.u64 & 0x7;
  return (top == 0x0005 && bottom >= 0x5) || (top == 0x0007 && bottom >= 0x6);
}

/** Returns the low 32 payload bits of an immediate `Var`. */
inline unsigned Var.payload32(Var value) => (unsigned) value.u64;

/** Decodes an immediate `<f32>` `Var`. */
inline float Var.decode_f32(Var value) {
  unsigned raw = Var.payload32(value);
  float result;
  memcpy(&result, &raw, sizeof result);
  return result;
}

/** Decodes an immediate `<f64>` `Var`. */
inline double Var.decode_f64(Var value) {
  switch (value.u64) {
    case VAR_NAN_BITS:    return 0.0 / 0.0;
    case VAR_NEGINF_BITS: return -1.0 / 0.0;
    case VAR_POSINF_BITS: return 1.0 / 0.0;
  }
  unsigned long raw = value.u64 == VAR_F64_NEG_MAX_ESCAPE
                    ? VAR_F64_NEG_MAX_RAW : value.u64 - VAR_F64_SHIFT;
  double result;
  memcpy(&result, &raw, sizeof result);
  return result;
}

// snapshot-visible declarations; shallow collection does not expand macros
Var Var.box_i8(char); Var Var.box_u8(uchar);
Var Var.box_i16(short); Var Var.box_u16(ushort);
Var Var.box_i32_bits(unsigned); Var Var.box_u32(unsigned);

macro Unit $var.immediate(
  Type $type, Name $method, Expr $prefix, Type $payload, Name $value) => {
  inline Var Var.$method($type $value) {
    return (Var) { .u64 = $prefix | ($payload) $value };
  }
}
/** Boxes a native `char` as an immediate `<i8>` `Var`. */
$var.immediate(char, box_i8, VAR_I8_PREFIX, unsigned char, value);
/** Boxes a native `uchar` as an immediate `<u8>` `Var`. */
$var.immediate(uchar, box_u8, VAR_U8_PREFIX, uchar, value);
/** Boxes a native `short` as an immediate `<i16>` `Var`. */
$var.immediate(short, box_i16, VAR_I16_PREFIX, unsigned short, value);
/** Boxes a native `ushort` as an immediate `<u16>` `Var`. */
$var.immediate(ushort, box_u16, VAR_U16_PREFIX, ushort, value);
/** Boxes an unsigned 32-bit pattern as an immediate `<i32>` `Var`. */
$var.immediate(unsigned, box_i32_bits, VAR_I32_PREFIX, unsigned, value);
/** Boxes a native `uint` as an immediate `<u32>` `Var`. */
$var.immediate(unsigned, box_u32, VAR_U32_PREFIX, unsigned, value);

/** Boxes a native `float` as an immediate `<f32>` `Var`. */
inline Var Var.box_f32(float value) {
  unsigned raw;
  memcpy(&raw, &value, sizeof raw);
  return (Var) { .u64 = VAR_F32_PREFIX | raw };
}

/** Boxes a native `double` as an immediate `<f64>` `Var`. */
inline Var Var.box_f64(double value) {
  unsigned long raw;
  memcpy(&raw, &value, sizeof raw);
  if (value != value)                 return (Var) { .u64 = VAR_NAN_BITS };
  if (value > 0 && value == 1.0/0.0)  return (Var) { .u64 = VAR_POSINF_BITS };
  if (value < 0 && value == -1.0/0.0) return (Var) { .u64 = VAR_NEGINF_BITS };
  return (Var) { .u64 = raw == VAR_F64_NEG_MAX_RAW
                       ? VAR_F64_NEG_MAX_ESCAPE : raw + VAR_F64_SHIFT };
}

/** Boxes an `Array` value as `Var`. */
inline Var    Array.var(Array x)         => Var.new(<array>, x);
/** Boxes a `Block` value as `Var`. */
inline Var    Block.var(Block x)         => Var.new(<block>, x);
/** Boxes a `Buffer` value as `Var`. */
inline Var    Buffer.var(Buffer x)       => Var.new(<buffer>, x);
/** Boxes a `Bytes` value as `Var`. */
inline Var    Bytes.var(Bytes x)         => Var.new(<bytes>, x);
/** Boxes a `List` value as `Var`. */
inline Var    List.var(List x)           =>
  (Var) { .u64 = (unsigned long) x | VAR_LIST_PREFIX };
/** Boxes a `File` value as `Var`. */
inline Var    File.var(File x)           => Var.new(<file>, x);
/** Boxes a `Map` value as `Var`. */
inline Var    Map.var(Map x)             => Var.new(<map>, x);
/** Boxes a `String` value as `Var`. */
inline Var    String.var(String x)       =>
  (Var) { .u64 = (unsigned long) x | VAR_STRING_PREFIX };
/** Boxes a `Symbol` value as `Var`. */
inline Var    Symbol.var(Symbol x)       => x < (1ul << 51)
  ? (Var) { .u64 = x + VAR_SYMBOL_OFFSET } : Var.new(<symbol>, x);
/** Boxes an `Iter` value as `Var`. */
inline Var    Iter.var(Iter x)           => Var.new(<iter>, x);

// primitive conversions

// snapshot-visible declarations; shallow collection does not expand macros
Var char.var(char); String char.str(char); String char.repr(char);
Var uchar.var(uchar); String uchar.str(uchar); String uchar.repr(uchar);
Var short.var(short); String short.str(short); String short.repr(short);
Var ushort.var(ushort); String ushort.str(ushort); String ushort.repr(ushort);
Var int.var(int); String int.str(int); String int.repr(int);
Var uint.var(uint); String uint.str(uint); String uint.repr(uint);
Var unsigned.var(unsigned);
String unsigned.str(unsigned);
String unsigned.repr(unsigned);
Var float.var(float); String float.str(float); String float.repr(float);
Var double.var(double); String double.str(double); String double.repr(double);

macro Unit $scalar(Type $type, Literal $tag, Param $parameter) => {
  /** Boxes a native `$type` value as `Var`. */
  inline Var $type.var($parameter) {
    return Var.new($tag, $(x2c.parameters.arguments (list $parameter))...);
  }
  /** Returns the display `String` of `$type`. */
  inline String $type.str($parameter) {
    return Var.new(
      $tag, $(x2c.parameters.arguments (list $parameter))...).str();
  }
  /** Returns the readable representation of `$type`. */
  inline String $type.repr($parameter) {
    return Var.new(
      $tag, $(x2c.parameters.arguments (list $parameter))...).repr();
  }
}

$scalar(char, <i8>, char x);
$scalar(uchar, <u8>, uchar x);
$scalar(short, <i16>, short x);
$scalar(ushort, <u16>, ushort x);
$scalar(int, <i32>, int x);
$scalar(uint, <u32>, uint x);
$scalar(unsigned, <u32>, unsigned x);
$scalar(float, <f32>, float x);
$scalar(double, <f64>, double x);

// indirect primitives to Var

/** Boxes a long value as `Var`. */
inline Var    long.var(long x)           => Var.box_long(x);
/** Boxes a `ulong` value as `Var`. */
inline Var    ulong.var(ulong x)         => Var.box_ulong(x);
/** Returns the display `String` of `long`. */
inline String long.str(long l)           => l.var().str();
/** Returns the readable representation of `long`. */
inline String long.repr(long l)          => l.var().repr();

// Var to builtins

/** Extracts the `Array` pointer from `x`, or NULL for another tag. */
inline Array Var.array(Var x) {
  if (x.u64 >> 48 != 0x0008 || (x.u64 & 0x7) != 0x0) return NULL;
  return (Array) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `Block` pointer from `x`, or NULL for another tag. */
inline Block Var.block(Var x) {
  if (x.u64 >> 48 != 0x0008 || (x.u64 & 0x7) != 0x1) return NULL;
  return (Block) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `Buffer` pointer from `x`, or NULL for another tag. */
inline Buffer Var.buffer(Var x) {
  if (x.u64 >> 48 != 0x0008 || (x.u64 & 0x7) != 0x2) return NULL;
  return (Buffer) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `Bytes` pointer from `x`, or NULL for another tag. */
inline Bytes Var.bytes(Var x) {
  if (x.u64 >> 48 != 0x0008 || (x.u64 & 0x7) != 0x3) return NULL;
  return (Bytes) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `file` payload after the caller establishes the matching
    `Var` kind.
*/
inline File Var.file(Var x) {
  if (x.u64 >> 48 != 0x0009 || (x.u64 & 0x7) != 0x0) return NULL;
  return (File) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `List` pointer from `x`, or `nil` for another tag. */
inline List Var.list(Var x) {
  if (x.u64 >> 48 != 0x0009 || (x.u64 & 0x7) != 0x4) return NULL;
  return (List) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `Iter` pointer from `x`, or NULL for another tag. */
inline Iter Var.as_iter(Var x) {
  if (x.u64 >> 48 != 0x0009 || (x.u64 & 0x7) != 0x2) return NULL;
  return (Iter) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `Map` pointer from `x`, or NULL for another tag. */
inline Map Var.map(Var x) {
  if (x.u64 >> 48 != 0x0009 || (x.u64 & 0x7) != 0x6) return NULL;
  return (Map) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `string` payload after the caller establishes the matching
    `Var` kind.
*/
inline String Var.string(Var x) {
  if (x.u64 >> 48 != 0x000B || (x.u64 & 0x7) != 0x1) return NULL;
  return (String) (x.u64 & 0x0000FFFFFFFFFFF8ul);
}

/** Extracts the `symbol` payload after the caller establishes the matching
    `Var` kind.
*/
inline Symbol Var.symbol(Var x) {
  if (x is <symbol>) return x.integer();
  return 0;
}

/* Scalar readers apply the Var.convert rules. Each direct branch is a fast
   path for a tag it already recognizes and gives the same result as
   converting. The fallback converts to the named target and reads the raw
   payload; a scalar reader after conversion would recurse. */

/** Returns `x` as a native `char` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
char Var.char(Var x) {
  if (x is <i8> || x is <u8>) return (char) x.integer();
  return (char) Var.convert(x, <i8>).integer();
}

/** Returns `x` as a native `uchar` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
uchar Var.uchar(Var x) {
  if (x is <u8>) return (uchar) x.integer();
  return (uchar) Var.convert(x, <u8>).integer();
}

/** Returns `x` as a native `short` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
short Var.short(Var x) {
  if (x is <i16>) return (short) x.integer();
  return (short) Var.convert(x, <i16>).integer();
}

/** Returns `x` as a native `ushort` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
ushort Var.ushort(Var x) {
  if (x is <u16>) return (ushort) x.integer();
  return (ushort) Var.convert(x, <u16>).integer();
}

/** Returns `x` as a native `int` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
int Var.int(Var x) {
  if (x is <i32>) return (int) x.integer();
  return (int) Var.convert(x, <i32>).integer();
}

/** Returns `x` as a native `uint` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
uint Var.uint(Var x) {
  if (x is <u32>) return (uint) x.integer();
  return (uint) Var.convert(x, <u32>).integer();
}

/** Returns `x` as a native `unsigned` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
unsigned Var.unsigned(Var x) {
  if (x is <u32>) return (unsigned) x.integer();
  return (unsigned) Var.convert(x, <u32>).integer();
}

/** Returns `x` as a native `long` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
long Var.long(Var x) {
  if (x is <long>) return x.long_value();
  if (x is <i48> || x is <i32> || x is <u32> ||
      x is <i16> || x is <u16> || x is <i8> || x is <u8>)
    return (long) x.integer();
  return Var.convert(x, <long>).long_value();
}

/** Returns `x` as a native `ulong` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
ulong Var.ulong(Var x) {
  if (x is <ulong>) return x.ulong_value();
  if (x is <u48> || x is <u32> || x is <u16> || x is <u8>)
    return (ulong) x.integer();
  return Var.convert(x, <ulong>).ulong_value();
}

/** Returns `x` as a native `long long` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
long long Var.long_long(Var x) {
  if (x is <llong>) return x.long_long_value();
  if (x is <long>) return (long long) x.long_value();
  if (x.kind() == <integer>) return (long long) x.integer();
  return Var.convert(x, <llong>).long_long_value();
}

/** Returns `x` as a native `unsigned long long` under the `Var.convert`
    rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, out
    of floating range, or invalidly encoded.
*/
unsigned long long Var.ulong_long(Var x) {
  if (x is <ullong>) return x.ulong_long_value();
  if (x is <ulong>) return (unsigned long long) x.ulong_value();
  if (x is <u48> || x is <u32> || x is <u16> || x is <u8>)
    return (unsigned long long) x.integer();
  return Var.convert(x, <ullong>).ulong_long_value();
}

/** Returns `x` as a native `long double` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, or
    invalidly encoded.
*/
long double Var.long_double(Var x) {
  if (x is <ldouble>) return x.long_double_value();
  if (x is <f64> || x is <f32>) return (long double) x.floating();
  return Var.convert(x, <ldouble>).long_double_value();
}

/** Returns `x` as a native `float` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, or
    invalidly encoded.
*/
float Var.float(Var x) {
  if (x is <f32>) return (float) x.floating();
  return (float) Var.convert(x, <f32>).floating();
}

/** Returns `x` as a native `double` under the `Var.convert` rules.
    Raises: `Var.convert`'s causes when the source is nonnumeric, `void`, or
    invalidly encoded.
*/
double Var.double(Var x) {
  if (x is <f64>) return x.floating();
  return Var.convert(x, <f64>).floating();
}

/* Source-only declarations for centrally declared Block adoptions. Static
   inline definitions are in array.x/block.x; placing these at the public
   boundary keeps them in the protocol declaration view without changing C
   linkage or the generated header. */
static inline Block Array.block(Array);
static inline Block Bytes.block(Bytes);
static inline void Block.pop(Block);
static inline void Block.truncate(Block, size_t);

/** Runs compiler-generated runtime protocol registration. */
void x2c_initialize_protocols(void) {
}

/** Initializes the x2c runtime once for the current process. */
void x2c_initialize(void) {
  void Atom.initialize(void), File.initialize(void);
  void List.initialize(void), Scope.initialize(void);
  void MatchCache.initialize(void);
  void String.initialize(void), Logger_initialize(void);
  Scope Scope.new(void), *Scope.top(void);
  static int initialized = 0;
  if (initialized) return;
  initialized = 1;
  x2c_initialize_protocols();
  Scope.initialize();
  if (!*Scope.top()) *Scope.top() = Scope.new();
  String.initialize();
  List.initialize();
  Atom.initialize();
  MatchCache.initialize();
  File.initialize();
  Logger_initialize();
}

/* Normalize an ordinary element index following x2c index conventions.
   Negative indices count once from the end. Returns -1 when the normalized
   index is outside the concrete element range.

   Raises: `<bad-arg>` when length is negative. */
/** Normalizes one element index against `length`. */
int x2c_normalize_index(int index, int length) {
  if (length < 0)
    raise %(bad-arg (owner "x2c_normalize_index") (length $length));
  if (index < 0) index += length;
  if (index < 0 || index >= length) return -1;
  return index;
}

/* Normalize slice bounds in place following x2c conventions:
   - Forward negative stops use the endpoint after the final element, so -1
     becomes len and larger magnitudes move left.
   - Start uses the concrete element domain (0..len-1) and stays within
     [-1, len], depending on step direction.
   - INT_MIN marks a missing bound. Start defaults to 0 or len - 1; stop
     defaults to the forward endpoint or the reverse sentinel before zero.
   Returns the resulting element count or 0 if the slice is empty.

   Raises: `<bad-arg>` when either bound pointer is NULL, step is zero, or
   length is negative. */
/** Normalizes slice bounds and returns the resulting element count. */
int x2c_normalize_slice(int *start, int *stop, int step, int length) {
  if (!start || !stop || !step || length < 0)
    raise %(bad-arg (owner "x2c_normalize_slice"));
  int orig_stop = *stop;
  if (*start == INT_MIN) *start = (step > 0) ? 0 : length - 1;
  if (*stop == INT_MIN) *stop = -1;
  // normalize start against the concrete element range
  if (*start < 0) {
    *start += length;
    if (*start < 0) *start = (step < 0) ? -1 : 0;
  }
  else if (*start >= length)
    *start = (step < 0) ? length - 1 : length;

  // normalize negative forward stops against the endpoint after the last item
  if (*stop < 0) {
    if (step > 0) *stop += length + 1;
    else {
      // preserve the default -1 sentinel so a reverse slice includes index 0
      if (orig_stop != INT_MIN)
        *stop += length;  // explicit negative stop is relative to len
    }
  }
  if (*stop < -1) *stop = -1;
  if (step > 0 && *stop > length) *stop = length;
  if (step < 0 && *stop > length) *stop = length;
  int newlen = 0;
  if (step < 0 && *start >= *stop) newlen = (*start - *stop - 1) / (-step) + 1;
  else if (step > 0 && *start <= *stop)
    newlen = (*stop - *start - 1) / step + 1;
  return newlen;
}

#pragma private

#include "dispatch.x"
#include <limits.h>

File Stdin, Stdout, Stderr;
/* Sentinel symmetry for Var encoding:
   - Null: all bits 0 (0x0000000000000000), raw pointer null and external nil
   - void: all bits 1 (0xFFFFFFFFFFFFFFFF), in-band "no value" sentinel */
Var Void = (Var) { .u64 = VAR_VOID_BITS };
List nil = NULL;
