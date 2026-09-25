/*  type-ledger.x -- the compiler's Var tag tables, projected from the ledger

    Copyright (c) 2025 Gary William Flake

    `lib/var-tags.xmacro` holds the ledger. This unit is the one compiler
    unit that imports it, so the units that include `type.x` do not load
    the ledger. Both tables have process lifetime.
*/

#include "type.x"

$(import "../lib/var-tags.xmacro")

/* Each native pointer type's tag; the ledger adds every boxed class and a
   pointer to it. */
static Map typetags = $(_tag_types '(
  ((* void) p48)                   ((* unsigned char) u8*)
  ((* signed char) i8*)            ((* unsigned short) u16*)
  ((* short) i16*)                 ((* unsigned) u32*)
  ((* int) i32*)                   ((* float) f32*)
  ((* unsigned long) ulong*)       ((* long) long*)
  ((* double) f64*)                ((* unsigned long long) ullong*)
  ((* long long) llong*)           ((* long double) ldouble*)
  ((* * void) p48*)                ((* * unsigned char) u8**)
  ((* * signed char) i8**)         ((* * unsigned short) u16**)
  ((* * short) i16**)              ((* * unsigned) u32**)
  ((* * int) i32**)                ((* * float) f32**)
  ((* * unsigned long) ulong**)    ((* * long) long**)
  ((* * double) f64**)             ((* * unsigned long long) ullong**)
  ((* * long long) llong**)        ((* * long double) ldouble**)
));

/* The encoding rows a statically known tag can be tested against without a
   runtime decode, projected from the same ledger the runtime decoder uses.
   Its keys are tag Symbols, so it outlives a translation unit. */
static Map varrows = %{ ${$var.tag.constant.rows()} };

/** Returns the process-lifetime `Var` tag of each builtin type. */
Map Type.builtin_var_tags(void) => typetags;

/** Returns each constant-row tag's `(top mask bottom)` encoding row. */
Map Type.var_tag_rows(void) => varrows;
