/*  dispatch.x -- typed descriptors for runtime `Var` behavior

    Copyright (c) 2025 Gary William Flake

    A registered type supplies a descriptor of function pointers. Boxed `Var`
    operations find the descriptor by tag and call its registered functions;
    an operation without one uses built-in behavior or raises `<no-member>`.
    Ordinary method lookup remains static.

    Equality, identity, and rendering can inspect `void`. Operations that need
    an ordinary value, including hashing, ordering, truthiness, and iteration,
    reject it as an invariant violation.
*/

#pragma once

$(import "error-macros.xmacro")
#include "common.x"
#include "map.x"

#pragma private
#include "var.x"
#include "varconvert.x"
#include "symbol.x"
#include "string.x"
#include "array.x"
#include "buffer.x"
#include "list.x"
#include "file.x"
#include "iter.x"
#include "exception.x"
#include "mutex.x"
#include <float.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// descriptor rows

/* One row per boxed ledger tag, in ledger order, so a decoded value indexes
   the table without another tag search. */
static VarDescriptor builtin_descriptors[_var_ - _array_ + 1] = {0};

int x2c_var_descriptor_index(Var value);
VarDescriptor *x2c_var_custom_descriptor(Var value);
VarDescriptor *x2c_var_declare(Symbol tag);
int x2c_var_tag_descriptor_index(Symbol tag);

static VarDescriptor *_descriptor(Var value) {
  VarDescriptor *descriptor = _row(x2c_var_descriptor_index(value));
  if (!descriptor) descriptor = x2c_var_custom_descriptor(value);
  return descriptor && descriptor.value_dispatch ? descriptor : NULL;
}

static VarDescriptor *_row(int index) {
  int count = sizeof(builtin_descriptors) / sizeof(builtin_descriptors[0]);
  return index >= 0 && index < count ? &builtin_descriptors[index] : NULL;
}

// display text

/** Returns the display `String` of `Var`. */
String Var.str(Var v) {
  VarDescriptor *descriptor = _descriptor(v);
  if (descriptor && descriptor.methods.str) return descriptor.methods.str(v);
  return v.fallback_str();
}

/** Returns the non-dispatch display `String` of `Var`. */
String Var.fallback_str(Var v) {
  Symbol tag = v.tag();
  switch (v.kind()) {
    case <floating>: case <integer>:   return _primitive_str(v, tag);
    case <pointer>:  case <reference>: return v.pointer_string();
    case <void>:     return "void";
  }
  return v.pointer_string();
}

static String _primitive_str(Var v, Symbol tag) {
  switch (tag) {
    case <i8>:   case <u8>:   return "%c".printf(v);
    case <i16>:  case <i32>:  return "%d".printf(v);
    case <i48>:  case <long>:  return "%ld".printf(v);
    case <llong>: return "%lld".printf(v);
    case <u16>:  case <u32>:  return "%u".printf(v);
    case <u48>:  case <ulong>:  return "%lu".printf(v);
    case <ullong>: return "%llu".printf(v);
    case <f32>:  case <f64>:  return "%lf".printf(v);
    case <ldouble>: return "%Lf".printf(v);
    case <nan>:  case <+inf>: case <-inf>: return %"$tag";
  }
  return v.pointer_string();
}

/** Formats the fallback display `String` for a pointer-bearing `Var`. */
String Var.pointer_string(Var v) {
  Symbol tag = v.tag();
  if (tag == <p48>) return "<0x%012lX>".printf((long) v.pointer());
  return "<%s: 0x%012lX>".printf(tag.str(), (long) v.pointer());
}

/** Appends the display text of `Var` to a `Buffer`.
    A descriptor that registers `write_str` streams straight into `out`. One
    that registers only `str` writes its `String` through, which materializes
    the text but keeps existing custom descriptors working. Neither fallback
    re-enters this function, so a descriptor providing neither cannot
    recurse.
*/
Buffer Var.write_str(Var v, Buffer out) {
  if (out == NULL) return NULL;
  VarDescriptor *descriptor = _descriptor(v);
  if (descriptor && descriptor.methods.write_str)
    return descriptor.methods.write_str(v, out);
  if (descriptor && descriptor.methods.str)
    return _write_text(out, descriptor.methods.str(v));
  return v.fallback_write_str(out);
}

/* A NULL text is the empty `String` and writes nothing. */
static Buffer _write_text(Buffer out, String text) =>
  text ? out.write(text) : out;

/** Appends the non-dispatch display text of `Var` to a `Buffer`.
    A primitive, pointer, or `void` renders straight into `out` instead of
    through an intermediate `String`.
*/
Buffer Var.fallback_write_str(Var v, Buffer out) {
  Symbol tag = v.tag();
  switch (v.kind()) {
    case <floating>:
    case <integer>:   return _write_primitive_str(v, tag, out);
    case <pointer>: case <reference>:
      return out.write(v.pointer_string());
    case <void>:      return out.write("void");
  }
  return out.write(v.pointer_string());
}

static Buffer _write_primitive_str(Var v, Symbol tag, Buffer out) {
  switch (tag) {
    case <i8>:   case <u8>:   return out.printf("%c", v);
    case <i16>:  case <i32>:  return out.printf("%d", v);
    case <i48>:  case <long>:  return out.printf("%ld", v);
    case <llong>: return out.printf("%lld", v);
    case <u16>:  case <u32>:  return out.printf("%u", v);
    case <u48>:  case <ulong>:  return out.printf("%lu", v);
    case <ullong>: return out.printf("%llu", v);
    case <f32>:  case <f64>:  return out.printf("%lf", v);
    case <ldouble>: return out.printf("%Lf", v);
    case <nan>:  case <+inf>: case <-inf>: return out.write(%"$tag");
  }
  return out.write(v.pointer_string());
}

// readable representation

/** Returns the readable representation of `Var`. */
String Var.repr(Var v) {
  VarDescriptor *descriptor = _descriptor(v);
  if (descriptor && descriptor.methods.repr) return descriptor.methods.repr(v);
  if (descriptor && descriptor.methods.str) return descriptor.methods.str(v);
  return v.fallback_repr();
}

/** Returns the non-dispatch readable representation of `Var`.
    It renders through `Var.fallback_write_repr`, so the two forms cannot
    drift apart.
*/
String Var.fallback_repr(Var v) =>
  v.fallback_write_repr(Buffer.new(0)).str_free();

/** Appends the readable representation of `Var` to a `Buffer`. */
Buffer Var.write_repr(Var v, Buffer out) {
  if (out == NULL) return NULL;
  VarDescriptor *descriptor = _descriptor(v);
  if (descriptor && descriptor.methods.write_repr)
    return descriptor.methods.write_repr(v, out);
  if (descriptor && descriptor.methods.repr)
    return _write_text(out, descriptor.methods.repr(v));
  if (descriptor && descriptor.methods.str)
    return _write_text(out, descriptor.methods.str(v));
  return v.fallback_write_repr(out);
}

/** Appends the non-dispatch representation of `Var` to a `Buffer`. */
Buffer Var.fallback_write_repr(Var v, Buffer out) {
  Symbol tag = v.tag();
  switch (v.kind()) {
    case <floating>:
    case <integer>:   return _write_primitive_repr(v, tag, out);
    case <pointer>: case <reference>:
      return v.write_pointer_repr(out);
    case <void>:      return out.write("void");
  }
  return v.write_pointer_repr(out);
}

/* Each numeric tag prints its own value with its own C spelling, so the text
   names both the number and the width it was boxed at. The narrow integer
   tags read their payload through `Var.long`, which does not widen a signed
   value into another tag's domain. */
static Buffer _write_primitive_repr(Var v, Symbol tag, Buffer out) {
  switch (tag) {
    case <i8>:  case <u8>:
      return _write_byte_repr(out, (unsigned) (uchar) v.long());
    case <u16>: case <i16>:
      return out.printf("0x%04X", (unsigned) (ushort) v.long());
    case <i32>:  return out.printf("%d", (int) v.long());
    case <u32>:  return out.printf("%uu", (unsigned) v.long());
    case <u48>:  return out.printf("0x%012lXul", v.ulong() & 0xFFFFFFFFFFFFul);
    case <i48>:
      return out.printf("0x%012lXl", (ulong) v.long() & 0xFFFFFFFFFFFFul);
    case <long>:  return out.printf("%ldl", v.long());
    case <ulong>:  return out.printf("%luul", v.ulong());
    case <llong>: return out.printf("%lldll", v.long_long());
    case <ullong>: return out.printf("%lluull", v.ulong_long());
    case <f32>:  return _write_float_repr(out, v.floating(), <f32>, "f");
    case <f64>:  return _write_float_repr(out, v.floating(), <f64>, NULL);
    case <ldouble>:
      return _write_float_repr(out, v.long_double(), <ldouble>, "l");
    case <nan>:  return out.write("NaN");
    case <+inf>: return out.write("+Inf");
    case <-inf>: return out.write("-Inf");
  }
  return v.write_pointer_repr(out);
}

/* A byte is spelled the way C spells a character constant. Writing the raw
   byte instead would put a NUL or a control byte inside the repr text. */
static Buffer _write_byte_repr(Buffer out, unsigned byte) {
  switch (byte) {
    case '\\': return out.write("'\\\\'");
    case '\'': return out.write("'\\''");
    case '\n': return out.write("'\\n'");
    case '\t': return out.write("'\\t'");
    case '\r': return out.write("'\\r'");
  }
  if (byte >= 0x20 && byte < 0x7F) return out.printf("'%c'", (int) byte);
  return out.printf("'\\x%02X'", byte);
}

/* The shortest decimal that reads back as `value`, followed by the suffix
   that names its C type. `*_DECIMAL_DIG` is the precision that always
   round-trips that width on this target; starting three digits short keeps
   0.1 spelled `0.1` instead of `0.10000000000000001`. The candidate is
   narrowed to `width` before the comparison, so a float is not asked to match
   a double's digits. */
static Buffer _write_float_repr(
  Buffer out, long double value, Symbol width, String suffix) {
  int limit = width == <f32> ? FLT_DECIMAL_DIG
            : (width == <f64> ? DBL_DECIMAL_DIG : LDBL_DECIMAL_DIG);
  char text[48];
  int digits = limit - 3;
  for (; digits < limit; digits++) {
    snprintf(text, sizeof text, "%.*Lg", digits, value);
    long double back = strtold(text, NULL);
    if (width == <f32>) back = (float) back;
    else if (width == <f64>) back = (double) back;
    if (back == value) break;
  }
  if (digits == limit) snprintf(text, sizeof text, "%.*Lg", limit, value);
  /* `%g` drops the point for a whole value, and bare digits read back as an
     integer, so restore the form that says floating. */
  if (text[strspn(text, "+-0123456789")] == '\0') strcat(text, ".0");
  out.write(text);
  return suffix ? out.write(suffix) : out;
}

/** Writes the fallback readable form of a pointer-bearing `Var`. */
Buffer Var.write_pointer_repr(Var v, Buffer out) {
  Symbol tag = v.tag();
  if (tag == <p48>) return out.printf("<0x%012lX>", (long) v.pointer());
  char name[32] = { 0 };
  tag.decode(name);
  return out.printf("<%s: 0x%012lX>", name, (long) v.pointer());
}

// recursive rendering

static threaded RenderPath *render_path;

/** Enters an object's recursive rendering, or returns zero for a cycle.
    Keep `path` alive and defer `path.leave()` after a successful entry.
    Identities are compared only along this thread's active path, so repeated
    references outside that path render independently. No allocation occurs.
*/
int RenderPath.enter(RenderPath *path, const void *identity) {
  for (RenderPath *active = render_path; active; active = active.previous)
    if (active.identity == identity) return 0;
  path.identity = identity;
  path.previous = render_path;
  render_path = path;
  return 1;
}

/** Restores the path after the most recent successful `enter` on this thread.
    Ordinary defer unwinding also restores it when a child renderer raises.
*/
void RenderPath.leave(RenderPath *path) {
  render_path = path.previous;
}

// hashing and equality

/** Returns the runtime hash of `Var`.
    Raises: `<void-op>` for `void`.
*/
unsigned Var.hash(Var v) {
  if (v.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.hash"));
  if (v.is_wide()) return v.wide_hash();
  /* Canonical `List`s are most of what the pool tables hash, and both these
     hashes are constant time. Unboxing a known tag is one mask and compare,
     where the descriptor row costs a full decode. `nil` and the empty
     `String` unbox as NULL and take the general path. */
  List list = v;
  if (list) return list.hash();
  String text = v;
  if (text) return _nonzero(text.hash());
  VarDescriptor *descriptor = _descriptor(v);
  if (descriptor && descriptor.methods.hash)
    return _nonzero(descriptor.methods.hash(v));
  return _default_hash(v);
}

/* Map stores a nonzero hash beside each record, so zero becomes all ones. */
static unsigned _nonzero(unsigned hash) => hash ? hash : -1;

/** Returns the non-dispatch runtime hash of `Var`.
    Raises: `<void-op>` for `void`.
*/
unsigned Var.fallback_hash(Var v) {
  if (v.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.fallback_hash"));
  if (v.is_wide()) return v.wide_hash();
  return _default_hash(v);
}

/* A Var is one 64-bit word, so it hashes as one through the shared mixer.
   Every Map, Set, and symbol table runs this hash on every lookup. Map masks
   the low bits, which fmix64 avalanches as well as the high ones. */
static unsigned _default_hash(Var v) => x2c_hash_word(v.u64);

/** Applies the registered equality operation for `a` and `b`. */
int Var.equal(Var a, Var b) {
  if (a.u64 == b.u64) return 1;
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS) return 0;
  /* Built-in object and Symbol rows identify the tag, so equal rows are
     equal tags and the row selects the descriptor without a second decode. */
  int index = x2c_var_descriptor_index(a);
  VarDescriptor *row = _row(index);
  if (row) {
    if (x2c_var_descriptor_index(b) != index) return 0;
    return row.value_dispatch && row.methods.equal
         ? row.methods.equal(a, b) : 0;
  }
  Symbol atag = a.tag(), btag = b.tag();
  if (atag == btag) {
    if (a.is_wide()) return a.wide_equal(b);
    VarDescriptor *descriptor = _descriptor(a);
    if (descriptor && descriptor.methods.equal)
      return descriptor.methods.equal(a, b);
  }
  return 0;
}

/** Applies non-dispatch equality to `a` and `b`. */
int Var.fallback_equal(Var a, Var b) {
  if (a.u64 == b.u64) return 1;
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS) return 0;
  if (a.tag() == b.tag() && a.is_wide()) return a.wide_equal(b);
  return 0;
}

/** Reports whether `a` and `b` have identical `Var` bits. */
meta native int Var.same(Var a, Var b) => a.u64 == b.u64;

/* ordering

   Ordinary values order by group: numbers < symbols < strings < arrays <
   lists < maps < objects < references < pointers. Arrays and Lists order
   lexicographically by element. */

/** Compares `a` and `b` by runtime value group and registered ordering.
    Raises: `<void-op>` when either operand is `void`.
*/
meta native int Var.compare(Var a, Var b) {
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS)
    raise %(void-op (owner "Var.compare"));
  if (a.u64 == b.u64) return 0;
  Symbol ak = a.kind(), bk = b.kind(), atag = a.tag(), btag = b.tag();
  int ag = _group(ak, atag), bg = _group(bk, btag);
  if (ag != bg) return (ag < bg) ? -1 : 1;
  if (ag == 0) return _numeric_compare(a, b, ak, bk, atag, btag);
  VarDescriptor *descriptor = atag == btag ? _descriptor(a) : NULL;
  if (descriptor && descriptor.methods.compare)
    return descriptor.methods.compare(a, b);
  return _group_compare(a, b, ak, atag, btag);
}

/** Compares without consulting a runtime descriptor.
    Raises: `<void-op>` when either operand is `void`.
*/
int Var.fallback_compare(Var a, Var b) {
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS)
    raise %(void-op (owner "Var.compare"));
  if (a.u64 == b.u64) return 0;
  Symbol ak = a.kind(), bk = b.kind(), atag = a.tag(), btag = b.tag();
  int ag = _group(ak, atag), bg = _group(bk, btag);
  if (ag != bg) return (ag < bg) ? -1 : 1;
  if (ag == 0) return _numeric_compare(a, b, ak, bk, atag, btag);
  return _group_compare(a, b, ak, atag, btag);
}

static int _group(Symbol kind, Symbol tag) {
  if (_is_numeric_kind(kind)) return 0;
  if (kind == <symbol>) return 1;
  switch (tag) {
    case <string>: return 2;
    case <array>:  return 3;
    case <list>:   return 4;
    case <map>:    return 5;
  }
  if (kind == <object>) return 6;
  if (kind == <reference>) return 7;
  if (kind == <pointer>) return 8;
  return 9;
}

static int _is_numeric_kind(Symbol kind) =>
  (kind == <integer>) || (kind == <floating>);

/* Values of one group without a registered ordering order by tag, then by
   address or encoding. */
static int _group_compare(
  Var a, Var b, Symbol kind, Symbol atag, Symbol btag) {
  int tc = atag.compare(btag);
  if (tc) return tc;
  if (kind == <pointer> || kind == <reference> || kind == <object>)
    return _compare_addresses(a, b);
  return _compare_bits(a, b);
}

static int _compare_addresses(Var a, Var b) {
  uintptr_t ap = (uintptr_t) a.pointer(), bp = (uintptr_t) b.pointer();
  if (ap == bp) return 0;
  return (ap < bp) ? -1 : 1;
}

static int _compare_bits(Var a, Var b) {
  if (a.u64 == b.u64) return 0;
  return (a.u64 < b.u64) ? -1 : 1;
}

/* numeric ordering

   Numbers order -Inf < finite < +Inf < NaN. Equal values break ties by rank,
   wider first, then by tag and encoding. */

static int _numeric_compare(
  Var a, Var b, Symbol ak, Symbol bk, Symbol atag, Symbol btag) {
  int awide = a.is_wide(), bwide = b.is_wide();
  long double da = _float_value(a, ak, awide), db = _float_value(b, bk, bwide);
  int ca = _numeric_class(atag, da), cb = _numeric_class(btag, db);
  if (ca != cb) return (ca < cb) ? -1 : 1;
  if (ca == 1) {
    int cmp;
    if (ak == <integer> && bk == <integer>) cmp = a.integer_compare(b);
    else if (ak == <integer>) cmp = a.integer_floating_compare(b);
    else if (bk == <integer>) cmp = -b.integer_floating_compare(a);
    else cmp = da < db ? -1 : da > db ? 1 : 0;
    if (cmp) return cmp;
  }
  return _numeric_tie(a, b, atag, btag, awide && bwide);
}

/* An integer compares through its payload, so only a floating kind reads a
   value here. */
static long double _float_value(Var v, Symbol kind, int wide) {
  if (kind != <floating>) return 0.0L;
  return wide ? v.long_double_value() : (long double) v.floating();
}

static int _numeric_class(Symbol tag, long double value) {
  if (tag == <-inf>) return 0;
  if (tag == <+inf>) return 2;
  if (tag == <nan> || value != value) return 3;
  if (value == 1.0 / 0.0) return 2;
  if (value == -1.0 / 0.0) return 0;
  return 1;
}

/* The encoding decides last, so distinct encodings of one value keep a
   strict order. */
static int _numeric_tie(Var a, Var b, Symbol atag, Symbol btag, int wide) {
  int ra = _numeric_rank(atag), rb = _numeric_rank(btag);
  if (ra != rb) return (ra < rb) ? 1 : -1;  // Higher rank sorts first.
  int tc = atag.compare(btag);
  if (tc) return tc;
  if (atag == btag && wide) return a.wide_compare(b);
  return _compare_bits(a, b);
}

static int _numeric_rank(Symbol tag) {
  if (tag == <float>) tag = <f32>;
  if (tag == <double>) tag = <f64>;
  X2CVarNumericInfo info;
  return Var.numeric_info(tag, info) ? info.rank : 0;
}

// iteration

/** Returns an iterator over `Var`.
    Raises: `<void-op>` for `void`. A null `dest` returns NULL without
    raising.
*/
meta native Iter Var.iter(Var x, Iter dest) {
  if (x.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.iter"));
  if (!dest) return NULL;
  VarDescriptor *descriptor = _descriptor(x);
  if (descriptor && descriptor.methods.iter)
    return descriptor.methods.iter(x, dest);
  return x.fallback_iter(dest);
}

/** Returns a non-dispatch iterator over `Var`.
    Raises: `<void-op>` for `void`. A null `dest` returns NULL without
    raising.
*/
Iter Var.fallback_iter(Var x, Iter dest) {
  if (x.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.iter"));
  if (!dest) return NULL;
  return dest.init((Var) {0}, NULL, (Var) { .u64 = 0 });
}

// indexed members

/** Tests dynamic membership through the receiver's registered protocol row.
    Raises: `<bad-enc>`, `<void-op>`, or `<no-member>` when the dynamic
    receiver cannot perform membership.
*/
meta native int Var.contains(Var value, Var needle) {
  _valid_member_operand(value, "receiver");
  _valid_member_operand(needle, "needle");
  Symbol member = <contains>;
  VarDescriptor *descriptor = _required_descriptor(value, member);
  if (descriptor.methods.contains)
    return descriptor.methods.contains(value, needle);
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

/** Reads a dynamic indexed value through the receiver's protocol row.
    Raises: `<bad-enc>`, `<void-op>`, or `<no-member>` when the dynamic
    receiver cannot be indexed.
*/
meta native Var Var.getindex(Var value, Var key) {
  _valid_member_operand(value, "receiver");
  _valid_member_operand(key, "key");
  Symbol member = <getindex>;
  VarDescriptor *descriptor = _required_descriptor(value, member);
  if (descriptor.methods.getindex)
    return descriptor.methods.getindex(value, key);
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

/** Stores and returns a dynamic indexed value through its protocol row.
    Raises: `<bad-enc>`, `<void-op>`, `<no-member>`, or a cause from the
    receiver's indexed assignment.
*/
meta native Var Var.setindex(Var value, Var key, Var replacement) {
  _valid_member_operand(value, "receiver");
  _valid_member_operand(key, "key");
  _valid_member_operand(replacement, "value");
  Symbol member = <setindex>;
  VarDescriptor *descriptor = _required_descriptor(value, member);
  if (descriptor.methods.setindex)
    return descriptor.methods.setindex(value, key, replacement);
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

/** Applies the registered dynamic compound update at `key` and returns its
    result. Mutation and failure behavior belong to that callback; this
    dispatch adds no thread or failure atomicity guarantee.
    Raises: `<bad-enc>`, `<void-op>`, `<no-member>`, or a cause from the
    receiver's indexed update.
*/
meta native Var Var.updateindex(Var value, Var key, Symbol op, Var rhs) {
  _valid_member_operand(value, "receiver");
  _valid_member_operand(key, "key");
  _valid_member_operand(rhs, "right");
  Symbol member = <update-idx>;
  VarDescriptor *descriptor = _required_descriptor(value, member);
  if (descriptor.methods.updateindex)
    return descriptor.methods.updateindex(value, key, op, rhs);
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

/** Applies a dynamic postfix update at `key` and returns its prior value.
    Raises: `<bad-enc>`, `<void-op>`, `<no-member>`, or a cause from the
    receiver's indexed update.
*/
meta native Var Var.postfixindex(Var value, Var key, Symbol op) {
  _valid_member_operand(value, "receiver");
  _valid_member_operand(key, "key");
  Symbol member = <postfx-idx>;
  VarDescriptor *descriptor = _required_descriptor(value, member);
  if (descriptor.methods.postfixindex)
    return descriptor.methods.postfixindex(value, key, op);
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

static void _valid_member_operand(Var value, String side) {
  if (!value.encoding_valid()) {
    unsigned long bits = value.u64;
    raise %(bad-enc (value $bits) (side $side));
  }
  if (value is void) raise %(void-op (side $side));
}

static VarDescriptor *_required_descriptor(Var value, Symbol member) {
  VarDescriptor *descriptor = _descriptor(value);
  if (descriptor) return descriptor;
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

// optional callbacks

/** Tries the registered truth callback for `value`.
    A null `handled`, missing descriptor, or missing callback returns zero.
    Otherwise `handled` is set to one and the synchronous callback result is
    returned; an available `handled` is cleared before lookup.
*/
int Var.dispatch_truth(Var value, int &?handled) {
  if (!handled) return 0;
  handled = 0;
  VarDescriptor *descriptor = _descriptor(value);
  if (!descriptor || !descriptor.methods.truth) return 0;
  handled = 1;
  return descriptor.methods.truth(value);
}

/** Tries one registered binary callback for `lhs`.
    Only `<add>`, `<sub>`, `<mul>`, `<div>`, `<mod>`, and `<matmul>` select
    callbacks.
    Returns one and writes the synchronous callback result when available;
    otherwise returns zero and leaves `result` unchanged. A null `result`
    returns zero.
*/
int Var.try_dispatch_binary(Var lhs, Symbol member, Var rhs, Var &?result) {
  if (!result) return 0;
  VarDescriptor *descriptor = _descriptor(lhs);
  if (!descriptor) return 0;
  VarBinaryFn callback = _binary_callback(&descriptor.methods, member);
  if (!callback) return 0;
  result = callback(lhs, rhs);
  return 1;
}

static VarBinaryFn _binary_callback(VarMethods *methods, Symbol member) {
  switch (member) {
    case <add>:    return methods.add;
    case <sub>:    return methods.sub;
    case <mul>:    return methods.mul;
    case <div>:    return methods.div;
    case <mod>:    return methods.mod;
    case <matmul>: return methods.matmul;
  }
  return NULL;
}

/** Tries the registered `<neg>` callback for `value`.
    Returns one and writes the synchronous callback result when available;
    otherwise returns zero and leaves `result` unchanged. A null `result`
    returns zero.
*/
int Var.try_dispatch_unary(Var value, Symbol member, Var &?result) {
  if (!result) return 0;
  VarDescriptor *descriptor = _descriptor(value);
  if (!descriptor || member != <neg> || !descriptor.methods.neg) return 0;
  result = descriptor.methods.neg(value);
  return 1;
}

/** Calls the registered `Context` exporter for `value` when one exists.
    Returns nonzero when the descriptor registers an exporter, and writes its
    result to `out`. `Context` handles built-in value families directly.
*/
int Var.try_export_context(Var value, Context source, Var &?out) {
  if (!out) return 0;
  VarDescriptor *descriptor = _descriptor(value);
  if (!descriptor || !descriptor.methods.export_context) return 0;
  out = descriptor.methods.export_context(value, source);
  return 1;
}

// registration

/** Attempts to make lowercase `name` available as a process-global `Var` tag.
    This no-result form silently ignores invalid names. A custom tag spends a
    `Var` row only when a value is first boxed. An active built-in name
    selects its existing row. The canonical name is borrowed for process-wide
    collision diagnostics, so its owning pool must outlive later descriptor
    use.

    Raises: `<bad-state>` after descriptor registration is frozen, or
    `<alloc-fail>` while checking lowercase spelling.
    Distinct full names that encode one `Symbol` through `_`/`-` folding or
    truncation abort.
*/
void x2c_register_type(String name) {
  _lock();
  defer _unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_register_type"));
  _reserve(name);
}

/** Merges callbacks into one built-in `Var` descriptor.
    Returns zero for a tag without a reserved descriptor and one otherwise.
    Non-NULL method fields replace their process-global slots; NULL fields
    preserve installed callbacks, and no callback runs during registration.
    Function pointers are borrowed, so their code must remain loaded through
    later dispatch or replacement.

    Raises: `<bad-state>` after descriptor registration is frozen.
*/
int x2c_register_builtin_descriptor(Symbol tag, VarMethods methods) {
  _lock();
  defer _unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_register_builtin_descriptor"));
  VarDescriptor *descriptor = _tag_row(tag);
  if (!descriptor) return 0;
  descriptor.value_dispatch = 1;
  _install_methods(descriptor, methods);
  return 1;
}

/** Declares a custom `Var` tag and merges its descriptor callbacks.
    Returns zero for a null or non-lowercase name, and one otherwise. An
    already active built-in name selects its existing row. Non-NULL fields
    replace process-global slots; NULL fields preserve installed callbacks.
    The canonical name and function pointers are borrowed process-wide: the
    name's owning pool and callback code must outlive later descriptor use.
    Registration invokes no callback.

    Raises: `<bad-state>` after descriptor registration is frozen, or
    `<alloc-fail>` while checking lowercase spelling.
    Distinct full names that encode one `Symbol` through `_`/`-` folding or
    truncation abort.
*/
int x2c_try_register_descriptor(String name, VarMethods methods) {
  _lock();
  defer _unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_try_register_descriptor"));
  VarDescriptor *descriptor = _reserve(name);
  if (!descriptor) return 0;
  _install_methods(descriptor, methods);
  return 1;
}

/** Attempts to reserve a custom `Var` tag and merge its descriptor callbacks.
    This no-result form discards the status from
    `x2c_try_register_descriptor`; all registration and freeze behavior is
    otherwise identical. The name and function pointers are borrowed under
    the same process-wide lifetime requirements.

    Raises: `<bad-state>` after descriptor registration is frozen, or
    `<alloc-fail>` while checking lowercase spelling.
    Distinct full names that encode one `Symbol` through `_`/`-` folding or
    truncation abort.
*/
void x2c_register_descriptor(String name, VarMethods methods) {
  x2c_try_register_descriptor(name, methods);
}

/** Declares custom `tag` under full type `name` and merges descriptor
    callbacks. Unlike `x2c_try_register_descriptor`, the tag need not be the
    restricted-Symbol encoding of the name. A built-in tag is rejected so an
    explicit custom type cannot replace built-in behavior. The name and
    callbacks have the same process-wide lifetime as ordinary descriptors.

    Returns zero for a null tag or name, and one otherwise. A built-in tag or
    distinct names for one tag abort.
    Explicit names retain case; ordinary inferred-tag registration still
    requires lowercase names. Raises: `<bad-state>` after registration freezes.
*/
int x2c_try_register_tagged_descriptor(
  Symbol tag, String name, VarMethods methods) {
  _lock();
  defer _unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_try_register_tagged_descriptor"));
  VarDescriptor *descriptor = _reserve_tagged(tag, name);
  if (!descriptor) return 0;
  _install_methods(descriptor, methods);
  return 1;
}

/** Registers an explicitly tagged type or raises `<bad-state>` for a null tag
    or name. Tag/name collisions follow the existing fatal descriptor
    diagnostic; registration still freezes at worker startup.
*/
void x2c_register_tagged_descriptor(
  Symbol tag, String name, VarMethods methods) {
  if (!x2c_try_register_tagged_descriptor(tag, name, methods))
    raise %(bad-state (owner "x2c_register_tagged_descriptor")
                     (tag $tag) (name $name));
}

/* A lowercase name spells its tag as a restricted Symbol, and a built-in
   row that already dispatches values serves that name. */
static VarDescriptor *_reserve(String name) {
  if (!name || name != name.lower()) return 0;
  Symbol tag = Symbol.new(name);
  if (!tag) return 0;
  VarDescriptor *row = _tag_row(tag);
  if (row && row.value_dispatch) return _claim_name(row, tag, name);
  return _claim_name(_declare(tag), tag, name);
}

/* An explicit tag names a custom type, so a built-in tag aborts. */
static VarDescriptor *_reserve_tagged(Symbol tag, String name) {
  if (!tag || !name) return 0;
  if (_tag_row(tag)) {
    fprintf(
      stderr, "Var descriptor: explicit tag <%s> is built in\n", tag.str());
    abort();
  }
  return _claim_name(_declare(tag), tag, name);
}

static VarDescriptor *_tag_row(Symbol tag) =>
  _row(x2c_var_tag_descriptor_index(tag));

static VarDescriptor *_declare(Symbol tag) {
  VarDescriptor *descriptor = x2c_var_declare(tag);
  descriptor.value_dispatch = 1;
  return descriptor;
}

/* Restricted Symbols fold `_` and `-` and truncate after ten characters;
   the 7-bit form truncates after seven. Distinct full names can therefore
   encode one tag and silently share this descriptor: the second registration
   would overwrite the first's methods, and every `is` test would answer for
   both. The full borrowed name is still here, so compare and diagnose that
   spelling before installation. Registration can run before Error, so use
   the same process-fatal reporting as the mutex paths. */
static VarDescriptor *_claim_name(
  VarDescriptor *descriptor, Symbol tag, String name) {
  if (!descriptor.name) descriptor.name = name;
  if (descriptor.name != name) {
    fprintf(
      stderr, "Var descriptor: tag <%s> names both %s and %s\n",
      tag.str(), (char *) descriptor.name, (char *) name);
    abort();
  }
  return descriptor;
}

/*  Every VarMethods field is a function pointer, so one pass over the struct
    installs each supplied method and stays correct when a method is added.
    NULL leaves an earlier callback installed; non-NULL pointers are borrowed
    process-wide until another registration replaces them. The slots have
    distinct function pointer types, so the pass copies bytes: reading and
    writing them through one pointer type lets an optimizer keep newly written
    fields at their old values.
*/
static void _install_methods(VarDescriptor *descriptor, VarMethods methods) {
  char *installed = (char *) &descriptor.methods;
  const char *supplied = (const char *) &methods;
  void (*method)(void);
  for (size_t i = 0; i < sizeof methods; i += sizeof method) {
    memcpy(&method, supplied + i, sizeof method);
    if (method) memcpy(installed + i, &method, sizeof method);
  }
}

/* registration lock

   One recursive mutex serializes registration. The first successful native
   worker start freezes it, and descriptor lookups take no lock. */

static pthread_mutex_t descriptor_mutex;
static pthread_once_t descriptor_mutex_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;
static int descriptor_registration_frozen;

static void _lock(void) =>
  Mutex.recursive_lock(
    &descriptor_mutex, &descriptor_mutex_once, _mutex_initialize,
    "Var descriptor: could not lock mutex");

static void _unlock(void) =>
  Mutex.recursive_unlock(
    &descriptor_mutex, "Var descriptor: could not unlock mutex");

static void _mutex_initialize(void) =>
  Mutex.recursive_initialize(
    &descriptor_mutex, "Var descriptor: could not initialize mutex");

/** Locks descriptor registration while a native worker starts.
    The caller must pair this on the same thread with
    `x2c_descriptor_thread_start_end`.
*/
void x2c_descriptor_thread_start_begin(void) {
  _lock();
}

/** Ends a native worker start and unlocks descriptor registration.
    A nonzero `success` permanently freezes subsequent registration; zero
    leaves it open for another attempt.
*/
void x2c_descriptor_thread_start_end(int success) {
  if (success) descriptor_registration_frozen = 1;
  _unlock();
}

/** Reports under the descriptor lock whether registration is frozen. */
int x2c_descriptor_registration_frozen(void) {
  _lock();
  int frozen = descriptor_registration_frozen;
  _unlock();
  return frozen;
}
