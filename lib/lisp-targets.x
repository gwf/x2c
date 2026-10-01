/*  lisp-targets.x -- evaluator targets of the optional pure modules

    Copyright (c) 2026 Gary William Flake

    The compile-time evaluator binds the pure Json, Diff, and Path operations
    that their `meta native` definitions advertise. This unit builds their
    table so that `lisp.x`, which the implicit prelude includes, does not
    include those modules: every unit replays an included file's includes,
    private ones too, so the prelude would carry their source APIs into every
    program.
*/

#pragma once
$(import "private-keywords.xmacro")
#include "x2c.x"

#pragma private

#include "json.x"
#include "diff.x"
#include "process.x"
#include "regex.x"
#include "typed-array.x"
#include "typed-map.x"
#include "lisp-init.x"

$(import "../etc/lisp-bindings.xlisp")
macro Expression $lisp.optional.target.map() => $(lisp.native.targets
  (filter (lambda (row)
            (let ((name (car row)))
              (not (eq? (+ (String.startswith name "Json_")
                           (String.startswith name "Diff_")
                           (String.startswith name "Path_"))
                        0))))
    (_x2c.native-meta.targets)));

static Map optional_targets = $lisp.optional.target.map();

// The evaluator targets the optional pure modules supply.
Map lisp_optional_native_targets(void) => optional_targets;

/* native targets

   `bind` resolves a name through the table the compiler generates from the
   rows below, then through the optional modules' table. An adapter here
   stands in for a library operation that needs the session or a check. */

/* Optional modules stay outside the implicit prelude. The compiler links
   their runtime units, so private checked aliases can install their pure
   value operations in the evaluator without importing their source APIs
   into every program. These C-only declarations do not enter the x2c
   interface; typed List names are ABI aliases for List. */
macro Unit $lisp.optional.native.declarations() {
  $(quote (
    (preproc "extern List List_listchar(List);")
    (preproc "extern List List_listshort(List);")
    (preproc "extern List List_listint(List);")
    (preproc "extern List List_listfloat(List);")
    (preproc "extern List List_listdbl(List);")
    (preproc "extern List List_liststring(List);")
    (preproc "extern List List_listsymbol(List);")
    (preproc "extern List Var_listchar(Var);")
    (preproc "extern List Var_listshort(Var);")
    (preproc "extern List Var_listint(Var);")
    (preproc "extern List Var_listfloat(Var);")
    (preproc "extern List Var_listdbl(Var);")
    (preproc "extern List Var_liststring(Var);")
    (preproc "extern List Var_listsymbol(Var);")
    (preproc "extern String String_sha256(String);")
    (preproc "extern String Var_json(Var);")
    (preproc "extern String Var_pretty_json(Var);")
    (preproc "extern Map lisp_optional_native_targets(void);")))...
}

$lisp.optional.native.declarations();

$x2c.foreign.alias(List_listchar)
static List _lisp_list_listchar(List value);
$x2c.foreign.alias(List_listshort)
static List _lisp_list_listshort(List value);
$x2c.foreign.alias(List_listint)
static List _lisp_list_listint(List value);
$x2c.foreign.alias(List_listfloat)
static List _lisp_list_listfloat(List value);
$x2c.foreign.alias(List_listdbl)
static List _lisp_list_listdbl(List value);
$x2c.foreign.alias(List_liststring)
static List _lisp_list_liststring(List value);
$x2c.foreign.alias(List_listsymbol)
static List _lisp_list_listsymbol(List value);
$x2c.foreign.alias(Var_listchar)
static List _lisp_var_listchar(Var value);
$x2c.foreign.alias(Var_listshort)
static List _lisp_var_listshort(Var value);
$x2c.foreign.alias(Var_listint)
static List _lisp_var_listint(Var value);
$x2c.foreign.alias(Var_listfloat)
static List _lisp_var_listfloat(Var value);
$x2c.foreign.alias(Var_listdbl)
static List _lisp_var_listdbl(Var value);
$x2c.foreign.alias(Var_liststring)
static List _lisp_var_liststring(Var value);
$x2c.foreign.alias(Var_listsymbol)
static List _lisp_var_listsymbol(Var value);
$x2c.foreign.alias(String_sha256)
static String _lisp_string_sha256(String value);
$x2c.foreign.alias(Var_json)
static String _lisp_var_json(Var value);
$x2c.foreign.alias(Var_pretty_json)
static String _lisp_var_pretty_json(Var value);
$x2c.foreign.alias(lisp_optional_native_targets)
static Map _lisp_optional_targets(void);

static List _lisp_list_cdddr(List value) => value.cdr().cdr().cdr();
static List _lisp_list_cddddr(List value) => value.cdr().cdr().cdr().cdr();
static List _lisp_var_cdddr(Var value) => value.cdr().cdr().cdr();
static List _lisp_var_cddddr(Var value) => value.cdr().cdr().cdr().cdr();

/* Native const-char pointers use represented String storage here. */
static String _lisp_string_new_len(String text, int length) =>
  String.new_len(text, length);
static Symbol _lisp_symbol_parse(String text) => Symbol.parse(text);
static Symbol _lisp_symbol_new_len(String text, int length) =>
  Symbol.new_len(text, length);

/* A Job started in compile-time Lisp, with its finalizer and capture
   files, belongs to the session that started it. */
static Job _lisp_List_job(List command) {
  Job job;
  $scope(&lisp_active.scope) { job = command; }
  return job;
}

static Job _lisp_Job_start(Job job) {
  $scope(&lisp_active.scope) { job.start(); }
  return job;
}

/* Meta text is a NUL-terminated String, so a count past its end would read
   beyond it. */
static Buffer _lisp_Buffer_write_len(
  Buffer buf, const char *text, size_t length) {
  if (text && strnlen(text, length) < length)
    raise %(bad-arg (operation "Buffer.write_len"));
  return buf.write_len(text, length);
}

/* The direct targets let the compiler generate their call adapters and
   read each signature from the declared prototype. The `x2c_` operations
   `meta.x` declares exist only inside a compiler, which supplies them. */
$(import "../etc/lisp-bindings.xlisp")
$(def lisp.native.target.rows (append '(
  (Var_is_void)
  (Func_apply)
  (Func_signature)
  (String_try_next)
  (Split_try_next)
  (List_try_next)
  (Array_try_next)
  (Map_try_next)
  (List_try_match)
  (List_try_match_replace)
  (List_try_search)
  (Map_try_get)
  (Map_try_del)
  (lisp_car (as Var_car))
  (lisp_cdr (as Var_cdr))
  (Var_cons)
  (lisp_atom)
  (lisp_pair)
  (lisp_list)
  (lisp_eq)
  (lisp_type)
  (lisp_number)
  (lisp_string)
  (lisp_symbol)
  (lisp_procedure)
  (List_reverse)
  (List_len)
  (List_match)
  (lisp_match_replace)
  (List_search)
  (List_search_replace)
  (lisp_add)
  (Var_binary)
  (lisp_compare)
  (lisp_plus rest)
  (lisp_minus rest)
  (lisp_times rest)
  (lisp_divide rest)
  (lisp_eq_chain rest)
  (lisp_lt_chain rest)
  (lisp_le_chain rest)
  (lisp_gt_chain rest)
  (lisp_ge_chain rest)
  (lisp_str)
  (lisp_repr)
  (String_len)
  (String_format)
  (lisp_string_append)
  (lisp_substring)
  (lisp_string_downcase)
  (lisp_read_file)
  (lisp_write_file)
  (List_sort)

  // The standard algorithms `etc/init.xlisp` binds.
  (lisp_last)
  (lisp_begin rest)
  (lisp_member)
  (lisp_assoc)
  (lisp_append rest)
  (lisp_not)
  (lisp_null)
  (lisp_sub)
  (lisp_mul)
  (lisp_div)
  (lisp_mod)
  (lisp_caar)
  (lisp_cadr)
  (lisp_cdar)
  (lisp_cddr)
  (lisp_caaar)
  (lisp_caadr)
  (lisp_cadar)
  (lisp_caddr)
  (lisp_cdaar)
  (lisp_cdadr)
  (lisp_cddar)
  (lisp_cdddr)
  (lisp_match)
  (lisp_bound)
  (lisp_search_replace)
  (lisp_binder)
  (lisp_binders)
  (lisp_binder_lets)
  (lisp_string_append_all rest)

  // Interpreted callbacks run through a session-bound Func.
  (_lisp_List_map (as List_map))
  (_lisp_List_filter (as List_filter))
  (_lisp_List_any (as List_any))
  (_lisp_List_all (as List_all))
  (_lisp_List_map2 (as List_map2))
  (_lisp_List_sort_by (as List_sort_by))
  (_lisp_List_sort_with (as List_sort_with))
  (_lisp_List_zip_with (as List_zip_with))
  (_lisp_List_foldl (as List_foldl))
  (_lisp_List_find (as List_find))
  (_lisp_Array_map (as Array_map))
  (_lisp_Array_map2 (as Array_map2))
  (_lisp_Array_sort_by (as Array_sort_by))
  (_lisp_Array_sort_with (as Array_sort_with))
  (_lisp_Array_foldl (as Array_foldl))
  (_lisp_String_map (as String_map))
  (_lisp_String_filter (as String_filter))
  // Iterator operations are declared `meta` in iter.x and adopted with
  // `meta protocol` in protocols.x, which generates their `_into` targets.
  // One that takes a callback binds here through its adapter.
  (_lisp_Iter_init (as Iter_init))
  (_lisp_Iter_map_into (as Iter_map_into))
  (_lisp_Iter_filter_into (as Iter_filter_into))
  (_lisp_Iter_zip_with_into (as Iter_zip_with_into))
  (_lisp_Iter_map2_into (as Iter_map2_into))
  (_lisp_Iter_scan_into (as Iter_scan_into))
  (_lisp_Iter_any (as Iter_any))
  (_lisp_Iter_all (as Iter_all))
  (_lisp_Iter_foldl (as Iter_foldl))
  (_lisp_Iter_find (as Iter_find))
  (Iter_try_next)
  (_lisp_Lisp_List_filter (as Lisp_List_filter))
  (_lisp_Lisp_List_any (as Lisp_List_any))
  (_lisp_Lisp_List_all (as Lisp_List_all))
  (_lisp_Lisp_List_find (as Lisp_List_find))
  (_lisp_Lisp_String_filter (as Lisp_String_filter))
  (_lisp_Lisp_Iter_filter (as Lisp_Iter_filter))
  (_lisp_Lisp_Iter_any (as Lisp_Iter_any))
  (_lisp_Lisp_Iter_all (as Lisp_Iter_all))
  (_lisp_Lisp_Iter_find (as Lisp_Iter_find))

  // The core value types: their operations are the library's own, so a
  // Lisp session and a compiled program build the same List, String, Map,
  // and Array. `etc/lisp-values.xlisp` names them.
  (String_truth)
  (Var_list)
  (Var_array)
  (Var_map)
  (Var_string)
  (Var_symbol)
  (Var_int)
  (Var_hash)
  (Var_is_integer)
  (Var_is_wide)
  (List_truth)
  (_lisp_list_listchar (as List_listchar))
  (_lisp_list_listshort (as List_listshort))
  (_lisp_list_listint (as List_listint))
  (_lisp_list_listfloat (as List_listfloat))
  (_lisp_list_listdbl (as List_listdbl))
  (_lisp_list_liststring (as List_liststring))
  (_lisp_list_listsymbol (as List_listsymbol))
  (_lisp_list_cdddr (as List_cdddr))
  (_lisp_list_cddddr (as List_cddddr))
  (_lisp_var_listchar (as Var_listchar))
  (_lisp_var_listshort (as Var_listshort))
  (_lisp_var_listint (as Var_listint))
  (_lisp_var_listfloat (as Var_listfloat))
  (_lisp_var_listdbl (as Var_listdbl))
  (_lisp_var_liststring (as Var_liststring))
  (_lisp_var_listsymbol (as Var_listsymbol))
  (_lisp_var_cdddr (as Var_cdddr))
  (_lisp_var_cddddr (as Var_cddddr))
  (_lisp_var_json (as Var_json))
  (_lisp_var_pretty_json (as Var_pretty_json))
  (_lisp_string_sha256 (as String_sha256))
  (_lisp_string_new_len)
  (_lisp_symbol_new_len)
  (_lisp_symbol_parse)
  (List_getindex)
  (List_last)
  (List_contains)
  (List_get)
  (List_assoc)
  (List_array)
  (Array_new)
  (Array_push)
  (Array_take_last)
  (Array_shift)
  (Array_insert)
  (Array_remove)
  (Array_list)
  (Map_new)
  (Map_get)
  (Map_del)
  (lisp_string_lstrip)
  (lisp_string_rstrip)
  (String_getindex)
  (String_add)
  (lisp_string_strip)
  (Var_is)
  (Symbol_str)
) (filter (lambda (row) (eq? (String.startswith (car row) "x2c_") 0))
     (_x2c.native-meta.targets)) '(
  // Adapters that replace generated direct targets come last to win.
  (_lisp_List_job (as List_job))
  (_lisp_Job_start (as Job_start))
  (_lisp_Buffer_write_len (as Buffer_write_len))
)))

macro Expression $lisp.native.target.map() =>
  $(lisp.native.targets lisp.native.target.rows);

static Map lisp_native_targets = $lisp.native.target.map();
