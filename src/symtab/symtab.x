/*  symtab.x -- the compiler's semantic symbol table

    Copyright (c) 2025 Gary William Flake.

    `Sym` holds one compiler's declarations as a stack of scopes searched
    from inner to outer; its lowest scopes hold file-scope declarations.
    It issues the binding identity of each declared name, resolves typedef
    chains and aggregate fields, and records which file-scope names are
    private. A `SymTxn` stages the rows a macro binds, so a failed expansion
    leaves the table as it was.
*/
#pragma once
#include "compiler/compiler.x"
#include "parse-reports.x"
#include "grammar.x"

// diagnostics

static macro Stmt $fail.symbols_name_package(
  Expr $c, Expr $site, Expr $spelling, Expr $owner) {
  $c.report_error(
    <parse>,
    %"'$($spelling)' is reserved for imported package '$($owner)'",
    $site, NULL);
}

static macro Stmt $fail.symbols_module_shadow(
  Expr $c, Expr $site, Expr $name) {
  $c.report_error(
    <parse>,
    %"'$($name)' is a module name and a static of one file in this unit",
    $site, %("a module declaration's name means one thing in every file"
    "of the unit; rename one of them"));
}

static macro Stmt $fail.symbols_module_tag(Expr $c, Expr $site, Expr $name) {
  $c.report_error(
    <parse>,
    %"two files of this module unit give a type named '$($name)' a Var tag",
    $site, %("a type's Var tag comes from its name without the file prefix,"
    "so it must be unique in the unit; rename one of the types"));
}

static macro Stmt $fail.symbols_name_reserved(
  Expr $c, Expr $site, Expr $spelling) {
  $c.report_error(
    <parse>,
    %"'$($spelling)' is reserved for compiler-generated names",
    $site, NULL);
}

static macro Stmt $fail.symbols_package_collision(
  Expr $c, Expr $site, Expr $kind, Expr $local) {
  $c.report_error(
    <parse>,
    %"package $($kind) '$($local)' collides with a declared name",
    $site, NULL);
}

static macro Stmt $fail.symbols_package_bound(
  Expr $c, Expr $site, Expr $kind, Expr $local, Expr $bound) {
  $c.report_error(
    <parse>,
    %"package $($kind) '$($local)' is already bound",
    $site, %( "bound to: $($bound)" ));
}

static macro Stmt $fail.symbols_typedef_depth(
  Expr $c, Expr $site, Expr $origin) {
  $c.report_error(
    <type>,
    %"typedef chain too deep (possible cycle) resolving $($origin.repr())",
    $site, NULL);
}

// symbol scopes

/*  Type grammar:
      TYPE-LIST : ( TYPE+ )
      TYPE      : ( MOD* SPEC )
      MOD       : (array SIZE?) | * | & | FUNCTION
      FUNCTION  : ( (func TYPE-LIST) MOD* SPEC)
      SPEC      : SCALAR | (union U) | (struct S) | (enum E) | TYPEDEF
      SCALAR    : "any C basic type"
      TYPEDEF   : "any user defined type"

    Symbol table entries:

    Identifier categories:
      V: variable name
      E: enum tag name
      F: function name
      K: field name (key)
      M: method name
      S: struct tag name
      U: union tag name
      T: typedef name

    Entry formats, each a lookup key and the type the table holds for it:
      (V)                   TYPE
      (union U K)             TYPE
      (union U)               (union TYPE-LIST)
      (struct S K)            (TYPE)
      (struct S)              (struct TYPE-LIST)
      (enum E)                (enum)
      (class C M)             (func ...)
      (T)                     (typedef TYPE)
      (F)                     (func (TYPE-LIST) TYPE)

    Notes:
    - Struct fields can have (BIT N) mods as well.
    - A declaration like "struct { int a, b; } x;" will generate two
      symbol table entries: one for an anonymous struct definition, and the
      other for x, which references the named anonymous struct definition.
*/

/** Holds a compiler's declarations in nested scopes.
    The lowest `base_scopes` contain file-scope declarations. Active
    transactions retain the rows each write replaces in `undo`.
*/
module typedef struct Sym {
  Block scopes, Map globals, statics, binding_facts, prefixed;
  int base_scopes, local_macro_names, aliases;
  Block undo, int transactions;
  // Owning compiler, so type resolution can report its own diagnostics.
  Compiler c;
} *Sym;

/* `map[key]` held `value` before a write, or nothing when it is void. */
module typedef struct SymUndo { Map map, Var key, value; } SymUndo;

module {
  "scopes.x",
  "bindings.x",
  "declarations.x",
  "namespaces.x",
  "types.x",
  "transactions.x",
}
