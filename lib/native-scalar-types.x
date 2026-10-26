/*  native-scalar-types.x -- exact C scalar ledger

    These are the native C scalar spellings the compiler can carry through a
    Var.  The compiler projects its Type lookup from these rows, and
    `native_scalar_access` returns each row's native size, alignment, load,
    and store for compile-time code that keeps C objects in bytes and for
    the compiler's layouts.  Var's i48/u48 numeric payload families are
    absent: neither is an exact C type.

    `native_scalar_types` is the one table. Each key is Type.scalar's
    canonical spelling, and each value is:

      (TAG C-EXTRACTOR C-UPDATE)

    C-EXTRACTOR and C-UPDATE retain the existing compiler emission
    spellings. `src/type.x` inserts the table with
    `$native_scalar_types()`, and the meta functions below read it during
    expansion.
*/

#pragma once
#include "common.x"
#include "macrovalue/macrovalue.x"

/* Reads one exact C scalar from `bytes`; a wide result is boxed in
   `owner`. */
typedef Var (*NativeScalarLoad)(const void *bytes, Scope *owner);

/* Writes `value`, converted to one exact C scalar type, to `bytes`. */
typedef void (*NativeScalarStore)(void *bytes, Var value);

/* Describes one exact C scalar type in native bytes: its Var tag, size,
   alignment, load, and store. Compile-time code that keeps C objects in
   bytes, and the compiler's layouts, select a row with
   `native_scalar_access`. */
typedef struct NativeScalarAccess {
  Symbol tag;
  size_t size, alignment;
  NativeScalarLoad load;
  NativeScalarStore store;
} *NativeScalarAccess;

meta Map native_scalar_types(void) => {
  %(char): %(i8 "Var_char" "x2c_var_update_i8"),
  %(signed char): %(i8 "Var_char" "x2c_var_update_schar"),
  %(unsigned char): %(u8 "Var_uchar" "x2c_var_update_u8"),
  %(short): %(i16 "Var_short" "x2c_var_update_i16"),
  %(unsigned short): %(u16 "Var_ushort" "x2c_var_update_u16"),
  %(int): %(i32 "Var_int" "x2c_var_update_i32"),
  %(unsigned): %(u32 "Var_uint" "x2c_var_update_u32"),
  %(long): %(long "Var_long" "x2c_var_update_long"),
  %(unsigned long): %(ulong "Var_ulong" "x2c_var_update_ulong"),
  %(long long): %(llong "Var_long_long" "x2c_var_update_long_long"),
  %(unsigned long long):
    %(ullong "Var_ulong_long" "x2c_var_update_ulong_long"),
  %(float): %(f32 "Var_float" "x2c_var_update_f32"),
  %(double): %(f64 "Var_floating" "x2c_var_update_f64"),
  %(long double):
    %(ldouble "Var_long_double" "x2c_var_update_long_double"),
};

/* The access record for `type` is `_native_scalar_access` followed by each
   word of `type`, so `(unsigned long)` names
   `_native_scalar_access_unsigned_long`. */
meta List _scalar_access_record(Type type) {
  String name = "_native_scalar_access";
  foreach (Symbol word in (List) type) name = %"$(name)_$word";
  return x2c_ident(name);
}

meta Symbol _scalar_tag(Type type) => native_scalar_types()[type].list().car();

/* `type` as the List expression of its words, as the parser builds
   `%(unsigned long)`. A quotation hole does not reach inside `%(...)`. */
meta List _scalar_key(Type type) {
  List key = %(expr ("List") (nil));
  foreach (Symbol word in ((List) type).reverse())
    key = %(expr ("List") (cons $($!Symbol{ $word }) $key));
  return key;
}

/* Native size, alignment, load, and store for one row's type. */
macro Unit $native.scalar.access(Type $type) {
  static Var _load(const void *bytes, Scope *owner) {
    $type native;
    memcpy(&native, bytes, sizeof native);
    Var value = native;
    return value.move_wide_to(owner);
  }

  static void _store(void *bytes, Var value) {
    $type native = value;
    memcpy(bytes, &native, sizeof native);
  }

  static struct NativeScalarAccess $_scalar_access_record($type) = {
    $_scalar_tag($type), sizeof($type), _Alignof($type),
    _load, _store
  };
}

/* One template application per row, in sorted order so emission does not
   depend on hash layout. */
meta List _scalar_access_units(Macro access) {
  Array units = [];
  List rows = native_scalar_types().list().sort();
  foreach (List row in rows) {
    Type type = row.car();
    units.push(access(type));
  }
  return units.list_free();
}

macro Unit $native.scalar.access.all() {
  @_scalar_access_units($native.scalar.access)
}

/* One row of `native_scalar_access`'s lookup: the type to its access
   record, which `$native.scalar.access.all` defines first. */
macro Entry $native.scalar.access.entry(Type $type) {
  $_scalar_key($type): (void *)&$_scalar_access_record($type)
}

macro Entry $native.scalar.access.entries() {
  @_scalar_access_units($native.scalar.access.entry)
}

$native.scalar.access.all();

static Map native_scalars = %{ $($native.scalar.access.entries()) };

/* Returns the access record for an exact C scalar type such as
   `(unsigned long)`, or NULL for any other type. */
NativeScalarAccess native_scalar_access(List exact_type) =>
  native_scalars.getdefault(exact_type, NULL).pointer();
