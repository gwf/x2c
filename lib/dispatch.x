/*  dispatch.x -- typed descriptors for runtime `Var` behavior

    Copyright (c) 2025 Gary William Flake

    A registered type supplies a descriptor of function pointers for repr,
    write, hash, equality, comparison, truthiness, and iteration. Boxed `Var`
    operations find the descriptor by tag and call its registered functions.
    Ordinary method lookup remains static.
    Equality, identity, and rendering can inspect `void`. Operations that need
    an ordinary value, including hashing, ordering, truthiness, and iteration,
    reject it as an invariant violation.
 */

#pragma once

$(import "error-macros.xmacro")
$(import "var-tags.xmacro")
#include "common.x"
#include "map.x"

/** Tries the registered truth callback for `value`.
    A null `handled`, missing descriptor, or missing callback returns zero.
    Otherwise `handled` is set to one and the synchronous callback result is
    returned; an available `handled` is cleared before lookup.
*/
int Var.dispatch_truth(Var value, int *handled) {
  if (!handled) return 0;
  *handled = 0;
  VarDescriptor *descriptor = _descriptor_for_value(value);
  if (!descriptor || !descriptor.methods.truth) return 0;
  *handled = 1;
  return descriptor.methods.truth(value);
}

/** Tries one registered binary callback for `lhs`.
    Only `<add>`, `<sub>`, `<mul>`, `<div>`, and `<mod>` select callbacks.
    Returns one and writes the synchronous callback result when available;
    otherwise returns zero and leaves `result` unchanged. A null `result`
    returns zero.
*/
int Var.try_dispatch_binary(Var lhs, Symbol member, Var rhs, Var *result) {
  if (!result) return 0;
  VarDescriptor *descriptor = _descriptor_for_value(lhs);
  if (!descriptor) return 0;
  VarBinaryFn callback = NULL;
  with descriptor.methods {
    switch (member) {
      case <add>: callback = _.add; break;
      case <sub>: callback = _.sub; break;
      case <mul>: callback = _.mul; break;
      case <div>: callback = _.div; break;
      case <mod>: callback = _.mod; break;
    }
  }
  if (!callback) return 0;
  *result = callback(lhs, rhs);
  return 1;
}

/** Tries the registered `<neg>` callback for `value`.
    Returns one and writes the synchronous callback result when available;
    otherwise returns zero and leaves `result` unchanged. A null `result`
    returns zero.
*/
int Var.try_dispatch_unary(Var value, Symbol member, Var *result) {
  if (!result) return 0;
  VarDescriptor *descriptor = _descriptor_for_value(value);
  if (!descriptor || member != <neg> || !descriptor.methods.neg) return 0;
  *result = descriptor.methods.neg(value);
  return 1;
}

/** Attempts to make lowercase `name` available as a process-global `Var` tag.
    This no-result form silently ignores invalid names and unavailable custom
    rows. An active built-in name selects its existing row. The canonical name
    is borrowed for process-wide collision diagnostics, so its owning pool
    must outlive later descriptor use.

    Raises: `<bad-state>` after descriptor registration is frozen, or
    `<alloc-fail>` while checking lowercase spelling.
    Distinct full names that encode one `Symbol` through `_`/`-` folding or
    truncation abort.
*/
void x2c_register_type(String name) {
  _descriptor_lock();
  defer _descriptor_unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_register_type"));
  _reserve_descriptor(name);
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
  _descriptor_lock();
  defer _descriptor_unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_register_builtin_descriptor"));
  VarDescriptor *descriptor = _reserved_builtin_descriptor_for_tag(tag);
  if (!descriptor) return 0;
  descriptor.value_dispatch = 1;
  _install_descriptor_methods(descriptor, methods);
  return 1;
}

/** Reserves a custom `Var` tag and merges its descriptor callbacks.
    Returns zero for a null or non-lowercase name, an unavailable tag, or
    exhausted custom capacity, and one otherwise. An already active built-in
    name selects its existing row. Non-NULL fields replace process-global
    slots; NULL fields preserve installed callbacks. The canonical name and
    function pointers are borrowed process-wide: the name's owning pool and
    callback code must outlive later descriptor use. Registration invokes no
    callback.

    Raises: `<bad-state>` after descriptor registration is frozen, or
    `<alloc-fail>` while checking lowercase spelling.
    Distinct full names that encode one `Symbol` through `_`/`-` folding or
    truncation abort.
*/
int x2c_try_register_descriptor(String name, VarMethods methods) {
  _descriptor_lock();
  defer _descriptor_unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_try_register_descriptor"));
  VarDescriptor *descriptor = _reserve_descriptor(name);
  if (!descriptor) return 0;
  _install_descriptor_methods(descriptor, methods);
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

/** Reserves custom `tag` under lowercase type `name` and merges descriptor
    callbacks. Unlike `x2c_try_register_descriptor`, the tag need not be the
    restricted-Symbol encoding of the name. A built-in tag is rejected so an
    explicit custom type cannot replace built-in behavior. The name and
    callbacks have the same process-wide lifetime as ordinary descriptors.

    Returns zero for an invalid name, built-in or unavailable tag, or exhausted
    custom capacity, and one otherwise. Distinct names for one tag abort.
    Raises: `<bad-state>` after registration freezes, or `<alloc-fail>` while
    checking lowercase spelling.
*/
int x2c_try_register_tagged_descriptor(
  Symbol tag, String name, VarMethods methods) {
  _descriptor_lock();
  defer _descriptor_unlock();
  if (descriptor_registration_frozen)
    raise %(bad-state (owner "x2c_try_register_tagged_descriptor"));
  VarDescriptor *descriptor = _reserve_tagged_descriptor(tag, name, 0);
  if (!descriptor) return 0;
  _install_descriptor_methods(descriptor, methods);
  return 1;
}

/** Formats the fallback display `String` for a pointer-bearing `Var`. */
String Var.pointer_string(Var v) {
  Symbol tag = v.tag();
  if (v is <p48>) return %"<0x%012lX>".printf((long) v.pointer());
  return %"<%s: 0x%012lX>".printf(tag.str(), (long) v.pointer());
}

/** Writes the fallback readable form of a pointer-bearing `Var`. */
Buffer Var.write_pointer_repr(Var v, Buffer out) {
  Symbol tag = v.tag();
  if (v is <p48>) return out.printf("<0x%012lX>", (long) v.pointer());
  char name[32] = { 0 };
  tag.decode(name);
  return out.printf("<%s: 0x%012lX>", name, (long) v.pointer());
}

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
#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>

/* Descriptors are process-global and never freed. They borrow native function
   pointers and the canonical `name`: callback code must remain loaded, and
   the name's owning pool must outlive every later use of the row. */
typedef struct VarDescriptor {
  int value_dispatch;
  VarMethods methods;
  String name;
} VarDescriptor;

/* One row per boxed ledger tag, in ledger order, so a decoded value indexes
   the table without another tag search. */
static VarDescriptor
  builtin_descriptors[$var.tag.descriptor.count()] = {0};

int x2c_var_descriptor_index(Var value);
int Var.custom_descriptor_index(Var value);
int x2c_var_tag_descriptor_index(Symbol tag);

/* Custom tag rows and descriptor rows share the same dense index. Successful
   native worker startup freezes both tables so lock-free dispatch can read
   them without racing registration. */
static VarDescriptor custom_descriptors[32] = {0};
static pthread_mutex_t descriptor_mutex;
static pthread_once_t descriptor_mutex_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;
static int descriptor_registration_frozen;

static void _descriptor_mutex_initialize(void) {
  pthread_mutexattr_t attributes;
  if (pthread_mutexattr_init(&attributes) ||
      pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE) ||
      pthread_mutex_init(&descriptor_mutex, &attributes)) {
    fprintf(stderr, "Var descriptor: could not initialize mutex\n");
    abort();
  }
  pthread_mutexattr_destroy(&attributes);
}

static void _descriptor_lock(void) {
  if (pthread_once(&descriptor_mutex_once, _descriptor_mutex_initialize) ||
      pthread_mutex_lock(&descriptor_mutex)) {
    fprintf(stderr, "Var descriptor: could not lock mutex\n");
    abort();
  }
}

static void _descriptor_unlock(void) {
  if (pthread_mutex_unlock(&descriptor_mutex)) {
    fprintf(stderr, "Var descriptor: could not unlock mutex\n");
    abort();
  }
}

/** Locks descriptor registration while a native worker starts.
    The caller must pair this on the same thread with
    `x2c_descriptor_thread_start_end`.
*/
void x2c_descriptor_thread_start_begin(void) {
  _descriptor_lock();
}

/** Ends a native worker start and unlocks descriptor registration.
    A nonzero `success` permanently freezes subsequent registration; zero
    leaves it open for another attempt.
*/
void x2c_descriptor_thread_start_end(int success) {
  if (success) descriptor_registration_frozen = 1;
  _descriptor_unlock();
}

/** Reports under the descriptor lock whether registration is frozen. */
int x2c_descriptor_registration_frozen(void) {
  _descriptor_lock();
  int result = descriptor_registration_frozen;
  _descriptor_unlock();
  return result;
}

static VarDescriptor *_reserved_builtin_descriptor_for_tag(Symbol tag) {
  int count = sizeof(builtin_descriptors) / sizeof(builtin_descriptors[0]);
  int index = x2c_var_tag_descriptor_index(tag);
  if (index < 0 || index >= count) return NULL;
  return &builtin_descriptors[index];
}

static VarDescriptor *_builtin_descriptor_for_tag(Symbol tag) {
  VarDescriptor *descriptor = _reserved_builtin_descriptor_for_tag(tag);
  return descriptor && descriptor.value_dispatch ? descriptor : NULL;
}

static VarDescriptor *_descriptor_for_value(Var value) {
  int count = sizeof(builtin_descriptors) / sizeof(builtin_descriptors[0]);
  int index = x2c_var_descriptor_index(value);
  VarDescriptor *builtin = index >= 0 && index < count
                         ? &builtin_descriptors[index] : NULL;
  VarDescriptor *descriptor = builtin;
  if (!descriptor) {
    int custom = value.custom_descriptor_index();
    if (custom >= 0) descriptor = &custom_descriptors[custom];
  }
  if (!descriptor || !descriptor.value_dispatch) return NULL;
  return descriptor;
}

static void _valid_member_operand(Var value, String side) {
  if (!Var.encoding_valid(value)) {
    unsigned long bits = value.u64;
    raise %(bad-enc (value $bits) (side $side));
  }
  if (value is void) raise %(void-op (side $side));
}

static VarDescriptor *_required_descriptor(Var value, Symbol member) {
  VarDescriptor *descriptor = _descriptor_for_value(value);
  if (descriptor) return descriptor;
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

/** Tests dynamic membership through the receiver's registered protocol row.
    Raises: `<bad-enc>`, `<void-op>`, or `<no-member>` when the dynamic
    receiver cannot perform membership.
*/
int Var.contains(Var value, Var needle) {
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
Var Var.getindex(Var value, Var key) {
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
Var Var.setindex(Var value, Var key, Var replacement) {
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
Var Var.updateindex(Var value, Var key, Symbol op, Var rhs) {
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
Var Var.postfixindex(Var value, Var key, Symbol op) {
  _valid_member_operand(value, "receiver");
  _valid_member_operand(key, "key");
  Symbol member = <postfx-idx>;
  VarDescriptor *descriptor = _required_descriptor(value, member);
  if (descriptor.methods.postfixindex)
    return descriptor.methods.postfixindex(value, key, op);
  Symbol tag = value.tag();
  raise %(no-member (tag $tag) (member $member));
}

static VarDescriptor *_reserve_tagged_descriptor(
  Symbol tag, String name, int allow_builtin) {
  if (!tag || !name || name != name.lower()) return 0;
  VarDescriptor *descriptor = allow_builtin
                            ? _builtin_descriptor_for_tag(tag) : NULL;
  if (!allow_builtin && _reserved_builtin_descriptor_for_tag(tag)) {
    fprintf(
      stderr, "Var descriptor: explicit tag <%s> is built in\n", tag.str());
    abort();
  }
  if (!descriptor) {
    int id = Var.register_object_tag(tag);
    if (id < 0) return 0;
    descriptor = &custom_descriptors[id];
    descriptor.value_dispatch = 1;
  }
  /* Restricted Symbols fold `_` and `-` and truncate after ten characters;
     the 7-bit form truncates after seven. Distinct full names can therefore
     encode one tag and silently share this descriptor: the second registration
     would overwrite the first's methods, and every `is` test would answer for
     both. The full borrowed name is still here, so compare and diagnose that
     spelling before installation. Registration can run before Error, so use
     the same process-fatal reporting as the mutex paths above. */
  if (!descriptor.name) descriptor.name = name;
  if (descriptor.name != name) {
    fprintf(
      stderr, "Var descriptor: tag <%s> names both %s and %s\n",
      tag.str(), (char *) descriptor.name, (char *) name);
    abort();
  }
  return descriptor;
}

static VarDescriptor *_reserve_descriptor(String name) {
  if (!name || name != name.lower()) return 0;
  return _reserve_tagged_descriptor(Symbol.new(name), name, 1);
}

/*  Every VarMethods field is a function pointer, so one pass over the struct
    installs each supplied method and stays correct when a method is added.
    NULL leaves an earlier callback installed; non-NULL pointers are borrowed
    process-wide until another registration replaces them. The slots have
    distinct function pointer types, so the pass copies bytes: reading and
    writing them through one pointer type lets an optimizer keep newly written
    fields at their old values.
*/
static void _install_descriptor_methods(
  VarDescriptor *descriptor, VarMethods methods) {
  char *installed = (char *) &descriptor.methods;
  const char *supplied = (const char *) &methods;
  void (*method)(void);
  for (size_t i = 0; i < sizeof methods; i += sizeof method) {
    memcpy(&method, supplied + i, sizeof method);
    if (method) memcpy(installed + i, &method, sizeof method);
  }
}

static String _primitive_repr(Var v, Symbol tag) {
  switch (tag) {
    case <i8>:    case <u8>:    return %"'%c'".printf(v);
    case <u16>:   case <i16>:   return %"0x%04X".printf(v);
    case <u32>:   case <i32>:   return %"%d".printf(v);
    case <u48>:   return %"0x%012lXul".printf(v);
    case <i48>:   return %"0x%012lXl".printf(v);
    case <long>:   return %"%ldl".printf(v);
    case <ulong>:   return %"%luul".printf(v);
    case <llong>:  return %"%lldll".printf(v);
    case <ullong>:  return %"%lluull".printf(v);
    case <f32>:   return %"%f".printf(v);
    case <f64>:   return %"%lfl".printf(v);
    case <ldouble>:  return %"%Lfl".printf(v);
    case <nan>:   return "NaN";
    case <+inf>:  return "+Inf";
    case <-inf>:  return "-Inf";
  }
  return Var.pointer_string(v);
}

static String _primitive_str(Var v, Symbol tag) {
  switch (tag) {
    case <i8>:   case <u8>:   return %"%c".printf(v);
    case <i16>:  case <i32>:  return %"%d".printf(v);
    case <i48>:  return %"%ld".printf(v);
    case <long>:  return %"%ld".printf(v);
    case <llong>: return %"%lld".printf(v);
    case <u16>:  case <u32>:  return %"%u".printf(v);
    case <u48>:  return %"%lu".printf(v);
    case <ulong>:  return %"%lu".printf(v);
    case <ullong>: return %"%llu".printf(v);
    case <f32>:  case <f64>:  return %"%lf".printf(v);
    case <ldouble>: return %"%Lf".printf(v);
    case <nan>:  case <+inf>: case <-inf>: return %"$tag";
  }
  return Var.pointer_string(v);
}

/** Returns the non-dispatch display `String` of `Var`. */
String Var.fallback_str(Var v) {
  Symbol tag = v.tag();
  switch (v.kind()) {
    case <floating>: case <integer>:   return _primitive_str(v, tag);
    case <pointer>:  case <reference>: return Var.pointer_string(v);
    case <void>:     return "void";
  }
  return Var.pointer_string(v);
}

/** Returns the display `String` of `Var`. */
String Var.str(Var v) {
  VarDescriptor *descriptor = _descriptor_for_value(v);
  if (descriptor && descriptor.methods.str) return descriptor.methods.str(v);
  return v.fallback_str();
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
  return out.write(Var.pointer_string(v));
}

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
      return out.write(Var.pointer_string(v));
    case <void>:      return out.write("void");
  }
  return out.write(Var.pointer_string(v));
}

/** Appends the display text of `Var` to a `Buffer`.
    A descriptor that registers `write_str` streams straight into `out`. One
    that registers only `str` writes its `String` through, which materializes
    the text but keeps existing custom descriptors working. Neither fallback
    re-enters this function, so a descriptor providing neither cannot
    recurse.
*/
Buffer Var.write_str(Var v, Buffer out) {
  if ((void *) out == NULL) return NULL;
  VarDescriptor *descriptor = _descriptor_for_value(v);
  if (descriptor && descriptor.methods.write_str)
    return descriptor.methods.write_str(v, out);
  if (descriptor && descriptor.methods.str) {
    String text = descriptor.methods.str(v);
    return text ? out.write(text) : out;
  }
  return v.fallback_write_str(out);
}

/** Returns the non-dispatch readable representation of `Var`. */
String Var.fallback_repr(Var v) {
  Symbol tag = v.tag();
  switch (v.kind()) {
    case <floating>: case <integer>:   return _primitive_repr(v, tag);
    case <pointer>:  case <reference>: return Var.pointer_string(v);
    case <void>:     return "void";
  }
  return Var.pointer_string(v);
}

/** Returns the readable representation of `Var`. */
String Var.repr(Var v) {
  VarDescriptor *descriptor = _descriptor_for_value(v);
  if (descriptor && descriptor.methods.repr) return descriptor.methods.repr(v);
  if (descriptor && descriptor.methods.str) return descriptor.methods.str(v);
  return v.fallback_repr();
}

static Buffer _write_primitive_repr(Var v, Symbol tag, Buffer out) {
  switch (tag) {
    case <i8>:  case <u8>:   return out.printf("'%c'", v);
    case <u16>: case <i16>:  return out.printf("0x%04X", v);
    case <u32>: case <i32>:  return out.printf("%d", v);
    case <u48>:  return out.printf("0x%012lXul", v);
    case <i48>:  return out.printf("0x%012lXl", v);
    case <long>:  return out.printf("%ldl", v);
    case <ulong>:  return out.printf("%luul", v);
    case <llong>: return out.printf("%lldll", v);
    case <ullong>: return out.printf("%lluull", v);
    case <f32>:  return out.printf("%f", v);
    case <f64>:  return out.printf("%lfl", v);
    case <ldouble>: return out.printf("%Lfl", v);
    case <nan>:  return out.write("NaN");
    case <+inf>: return out.write("+Inf");
    case <-inf>: return out.write("-Inf");
  }
  return Var.write_pointer_repr(v, out);
}

/** Appends the non-dispatch representation of `Var` to a `Buffer`. */
Buffer Var.fallback_write_repr(Var v, Buffer out) {
  Symbol tag = v.tag();
  switch (v.kind()) {
    case <floating>:
    case <integer>:   return _write_primitive_repr(v, tag, out);
    case <pointer>: case <reference>:
      return Var.write_pointer_repr(v, out);
    case <void>:      return out.write("void");
  }
  return Var.write_pointer_repr(v, out);
}

/** Appends the readable representation of `Var` to a `Buffer`. */
Buffer Var.write_repr(Var v, Buffer out) {
  if ((void *) out == NULL) return NULL;
  VarDescriptor *descriptor = _descriptor_for_value(v);
  if (descriptor && descriptor.methods.write_repr)
    return descriptor.methods.write_repr(v, out);
  if (descriptor && descriptor.methods.repr) {
    String text = descriptor.methods.repr(v);
    return text ? out.write(text) : out;
  }
  if (descriptor && descriptor.methods.str) {
    String text = descriptor.methods.str(v);
    return text ? out.write(text) : out;
  }
  return v.fallback_write_repr(out);
}

/* A Var is one 64-bit word, so it hashes as one through the shared mixer.
   Every Map, Set, and symbol table runs this hash on every lookup. Map masks
   the low bits, which fmix64 avalanches as well as the high ones. */
static unsigned _default_hash(Var var) => x2c_hash_word(var.u64);

/** Applies non-dispatch equality to `a` and `b`. */
int Var.fallback_equal(Var a, Var b) {
  if (a.u64 == b.u64) return 1;
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS) return 0;
  if (a.tag() == b.tag() && a.is_wide()) return a.wide_equal(b);
  return 0;
}

/** Returns the non-dispatch runtime hash of `Var`.
    Raises: `<void-op>` for `void`.
*/
unsigned Var.fallback_hash(Var v) {
  if (v.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.fallback_hash"));
  if (v.is_wide()) return v.wide_hash();
  return _default_hash(v);
}

/** Returns the runtime hash of `Var`.
    Raises: `<void-op>` for `void`.
*/
unsigned Var.hash(Var v) {
  if (v.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.hash"));
  if (v.is_wide()) return v.wide_hash();
  VarDescriptor *descriptor = _descriptor_for_value(v);
  if (descriptor && descriptor.methods.hash) {
    unsigned hash = descriptor.methods.hash(v);
    return hash ? hash : -1;
  }
  return _default_hash(v);
}

/** Applies the registered equality operation for `a` and `b`. */
int Var.equal(Var a, Var b) {
  if (a.u64 == b.u64) return 1;
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS) return 0;
  Symbol tag = a.tag(), btag = b.tag();
  if (tag == btag) {
    if (a.is_wide()) return a.wide_equal(b);
    VarDescriptor *descriptor = _descriptor_for_value(a);
    if (descriptor && descriptor.methods.equal)
      return descriptor.methods.equal(a, b);
  }
  return 0;
}

/** Reports whether `a` and `b` have identical `Var` bits. */
int Var.same(Var a, Var b) => a.u64 == b.u64;

static int _compare_default(Var a, Var b) {
  if (a.u64 == b.u64) return 0;
  return (a.u64 < b.u64) ? -1 : 1;
}

static int _is_numeric_kind(Symbol kind) =>
  (kind == <integer>) || (kind == <floating>);

static int _cmp_ptr(Var a, Var b) {
  uintptr_t ap = (uintptr_t) a.pointer(), bp = (uintptr_t) b.pointer();
  if (ap == bp) return 0;
  return (ap < bp) ? -1 : 1;
}

static int _numeric_rank(Symbol tag) {
  if (tag == <float>) tag = <f32>;
  if (tag == <double>) tag = <f64>;
  X2CVarNumericInfo info;
  return Var.numeric_info(tag, &info) ? info.rank : 0;
}

static int _numeric_class(Symbol tag, long double value) {
  if (tag == <-inf>) return 0;
  if (tag == <+inf>) return 2;
  if (tag == <nan> || value != value) return 3;
  if (value == 1.0 / 0.0) return 2;
  if (value == -1.0 / 0.0) return 0;
  return 1;
}

static int _numeric_compare(
  Var a, Var b, Symbol ak, Symbol bk, Symbol atag, Symbol btag) {
  int awide = a.is_wide(), bwide = b.is_wide();
  long double da = ak == <floating>
                 ? awide ? a.long_double_value() : (long double) a.floating()
                 : 0.0L;
  long double db = bk == <floating>
                 ? bwide ? b.long_double_value() : (long double) b.floating()
                 : 0.0L;
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
  int ra = _numeric_rank(atag), rb = _numeric_rank(btag);
  if (ra != rb) return (ra < rb) ? 1 : -1;  // Higher rank sorts first.
  int tc = atag.compare(btag);
  if (tc) return tc;
  if (atag == btag && awide && bwide) return a.wide_compare(b);
  // preserve strict ordering among encodings of the same value
  return _compare_default(a, b);
}

/* Total ordering for ordinary Var values:
     numbers < symbols < strings < arrays < lists < maps
          < objects < references < pointers.
   Numbers: -Inf < finite < +Inf < NaN; ties broken by rank (wider first).
   Arrays/Lists: lexicographic by elements. */
static int _var_group(Symbol kind, Symbol tag) {
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

/** Compares without consulting a runtime descriptor.
    Raises: `<void-op>` when either operand is `void`.
*/
int Var.fallback_compare(Var a, Var b) {
  if (a.u64 == b.u64) {
    if (a.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.compare"));
    return 0;
  }
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS)
    raise %(void-op (owner "Var.compare"));
  Symbol ak = a.kind(), bk = b.kind(), atag = a.tag(), btag = b.tag();
  int ag = _var_group(ak, atag), bg = _var_group(bk, btag);
  if (ag != bg) return (ag < bg) ? -1 : 1;
  if (ag == 0) return _numeric_compare(a, b, ak, bk, atag, btag);
  int tc = atag.compare(btag);
  if (tc) return tc;
  if (ak == <pointer> || ak == <reference> || ak == <object>)
    return _cmp_ptr(a, b);
  return _compare_default(a, b);
}

/** Compares `a` and `b` by runtime value group and registered ordering.
    Raises: `<void-op>` when either operand is `void`.
*/
int Var.compare(Var a, Var b) {
  if (a.u64 == b.u64) {
    if (a.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.compare"));
    return 0;
  }
  if (a.u64 == VAR_VOID_BITS || b.u64 == VAR_VOID_BITS)
    raise %(void-op (owner "Var.compare"));

  Symbol ak = a.kind(), bk = b.kind(), atag = a.tag(), btag = b.tag();
  int ag = _var_group(ak, atag), bg = _var_group(bk, btag);
  if (ag != bg) return (ag < bg) ? -1 : 1;
  switch (ag) {
    case 0:  return _numeric_compare(a, b, ak, bk, atag, btag);
    default: break;
  }
  if (atag == btag) {
    VarDescriptor *descriptor = _descriptor_for_value(a);
    if (descriptor && descriptor.methods.compare)
      return descriptor.methods.compare(a, b);
  }
  int tc = atag.compare(btag);
  if (tc) return tc;
  if (ak == <pointer> || ak == <reference> || ak == <object>)
    return _cmp_ptr(a, b);
  return _compare_default(a, b);
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

/** Returns an iterator over `Var`.
    Raises: `<void-op>` for `void`. A null `dest` returns NULL without
    raising.
*/
Iter Var.iter(Var x, Iter dest) {
  if (x.u64 == VAR_VOID_BITS) raise %(void-op (owner "Var.iter"));
  if (!dest) return NULL;
  VarDescriptor *descriptor = _descriptor_for_value(x);
  if (descriptor && descriptor.methods.iter)
    return descriptor.methods.iter(x, dest);
  return x.fallback_iter(dest);
}

/** Calls the registered `Context` exporter for `value` when one exists.
    Returns nonzero when the descriptor registers an exporter, and writes its
    result to `out`. `Context` handles built-in value families directly.
*/
int Var.try_export_context(Var value, Context source, Var *out) {
  if (!out) return 0;
  VarDescriptor *descriptor = _descriptor_for_value(value);
  if (!descriptor || !descriptor.methods.export_context) return 0;
  *out = descriptor.methods.export_context(value, source);
  return 1;
}
