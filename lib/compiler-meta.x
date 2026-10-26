/*  compiler-meta.x -- compiler-private meta operations and facts

    Copyright (c) 2026 Gary William Flake

    The operator rows give shipped compiler sources their shared facts.
    Bodyless `meta` prototypes name native operations the compiler
    supplies for those sources: the built-in macros' algorithms
    that need the full meta surface, Lisp binding groups, and the generated
    target tables, hashes, interface records, and SymbolSets. The implicit
    prelude reaches them through `lisp-bindings.x`, but they are not part
    of the documented meta surface, which `lib/meta.x` owns.
*/

#pragma once

#include "meta.x"

/* Operator, precedence, compound assignment, protocol member, and derived
   comparison flag. Zero denotes an absent compound spelling or member. */
meta List _x2c_operator_rows(void) => %(
  (<||>       1 0        0         0)
  (<&&>       2 0        0         0)
  (<|>        3 <|=>     0         0)
  (<^>        4 <^=>     0         0)
  (<&>        5 <&=>     0         0)
  (<~=>       6 0        0         0)
  (<"==">     6 0        <equal>   0)
  (<!=>       6 0        <equal>   1)
  (<"===">    6 0        0         0)
  (<!==>      6 0        0         0)
  (<"<">      7 0        <compare> 1)
  (<"<=">     7 0        <compare> 1)
  (<">">      7 0        <compare> 1)
  (<">=">     7 0        <compare> 1)
  (<in>       7 0        0         0)
  (<"<<">     8 <"<<=">  0         0)
  (<">>">     8 <">>=">  0         0)
  (<+>        9 <+=>     <add>     0)
  (<->        9 <-=>     <sub>     0)
  (<*>       10 <*=>     <mul>     0)
  (</>       10 </=>     <div>     0)
  (<%>       10 <%=>     <mod>     0)
);

/* Returns `values` as a cached literal expression of the expanding unit,
   so a template can insert data such as a signature as a constant. */
meta List _x2c_literal_list(List values);

/* Returns the release `$auto` places after the declarator `local` whose
   binding is `binding`, keeping its value in `acquired`. */
meta List _x2c_auto_release(Code local, List binding, List acquired);

/* Records one `$lisp.binding` row of `function` under `group` and `name`;
   returns no syntax. */
meta List _x2c_binding_record(Var group, Var name, List function);

/* Returns the `Lisp_bind` statements that install `group` into `lisp`,
   and seals the group. */
meta List _x2c_binding_install(List lisp, Var group);

/* Returns the expression building a name-to-`Func` Map from target rows
   `(NAME)`, `(NAME (as KEY))`, or `(NAME rest)`. */
meta List _x2c_target_map(List rows);

/* Returns `leading`, the target rows of `inventory`, then `trailing`.
   `<compiler>` selects the compiler's own `x2c_`, `Code_`, and `Type_`
   operations; `<lisp>` the other advertised targets runtime Lisp binds
   directly; `<runtime>` those targets with the ones that take a `Func`. */
meta List _x2c_native_rows(Symbol inventory, List leading, List trailing);

/* Returns the target rows the sources at the absolute `paths` declare. */
meta List _x2c_declared_rows(List paths);

/* Returns linked definition hashes and provider source dependencies. */
meta Map _x2c_meta_linked_hashes(void);

/* Returns the interface record text of each linked prelude component. */
meta Map _x2c_prelude_records(void);

/* Returns the SymbolSet expression holding the distinct `symbols`. */
meta Var _x2c_symbol_set(List symbols);
