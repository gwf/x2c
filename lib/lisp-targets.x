/*  lisp-targets.x -- the native operations a Lisp session can bind

    Copyright (c) 2026 Gary William Flake

    `bind` resolves a name through the session callbacks `lisp.x` adapts and
    then through the table this unit builds: the library operations Lisp code
    names, every operation the modules included here advertise with `meta`,
    and adapters for the operations that need the active session or a check.
    This unit includes the optional modules the evaluator binds so that
    `lisp.x`, which the implicit prelude includes, does not: every unit
    replays an included file's includes, private ones too, so the prelude
    would carry their source APIs into every program.
*/

#pragma once
#include "x2c.x"

#include "diff.x"
#include "digest.x"
#include "json.x"
#include "lisp-init.x"
#include "list-selectors.x"
#include "process.x"
#include "regex.x"
#include "typed-array.x"
#include "typed-list.x"
#include "typed-map.x"

/* The direct targets let the compiler generate their call adapters and
   read each signature from the declared prototype. The `x2c_` operations
   `meta.x` declares exist only inside a compiler, which supplies them. */
static $(import "../etc/lisp-bindings.xlisp")
static $(def lisp.native.target.rows (append '(
  (Var_is_void)
  (Func_apply)
  (Func_signature)
  (String_try_next)
  (Split_try_next)
  (List_try_next)
  (Array_try_next)
  (Map_try_next)
  (Iter_try_next)
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
  (List_listchar)
  (List_listshort)
  (List_listint)
  (List_listfloat)
  (List_listdbl)
  (List_liststring)
  (List_listsymbol)
  (List_cdddr)
  (List_cddddr)
  (Var_listchar)
  (Var_listshort)
  (Var_listint)
  (Var_listfloat)
  (Var_listdbl)
  (Var_liststring)
  (Var_listsymbol)
  (Var_cdddr)
  (Var_cddddr)
  (Var_json)
  (Var_pretty_json)
  (String_sha256)
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

static macro Expression $lisp.native.target.map() =>
  $(lisp.native.targets lisp.native.target.rows);

static Map native_targets = $lisp.native.target.map();

// Session callbacks take precedence over this table.
Map lisp_native_targets(void) => native_targets;

// adapters

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
  $scope(Lisp.active().storage()) { job = command; }
  return job;
}

static Job _lisp_Job_start(Job job) {
  $scope(Lisp.active().storage()) { job.start(); }
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
