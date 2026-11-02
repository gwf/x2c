/*  runtime.x -- runtime lifetime contracts */

// runtime effects

/* The runtime operations the pass reads by C name. (alloc) returns storage
   born in the active region and (alloc slot) in the Scope its first
   argument names; (alloc final) is an (alloc) whose result a `meta` body
   owns in its own frame, because a finalizer ends it when the lowered call
   returns; (pool) conses both arguments into pool cells; (store)
   puts its later arguments into its receiver; (wrap) boxes its argument
   unchanged; (free) ends its argument, or owns it from a `defer`, and
   (free scope) also requires Scope storage; (alloc moved) is a Scope
   allocation that ends its first argument; (destroy) ends a Scope local's
   storage; (open KIND) and (close KIND) bracket a region; (move) and
   (exit) hand their argument to another owner, though Scope_move hands
   over only a container's record; (summary OWNER SINKS) is a literal
   summary. (element) reads a stored value without inheriting the
   container handle's deferred free. */
static Map runtime = _typed_families(
  %{
    "Scope_malloc": (alloc),           "Scope_calloc": (alloc),
    "Scope_memdup": (alloc),           "Scope_malloc_finalized": (alloc),
    "xmalloc": (alloc),                "xcalloc": (alloc),
    "xmemdup": (alloc),                "xrealloc": (alloc moved),
    "Scope_realloc": (alloc moved),    "String_malloc": (alloc pool),
    "String_new": (alloc pool),        "String_new_len": (alloc pool),
    "String_new_fill": (alloc pool),
    "String_printf": (alloc pool),     "String_vprintf": (alloc pool),
    "MapSubInt_strings": (alloc),
    "Block_new": (alloc),              "Bytes_new": (alloc),
    "Array_new": (alloc),              "Map_new": (alloc),
    "Buffer_new": (alloc),             "Map_new_capacity": (alloc),
    "Array_copy": (alloc),             "Array_concat": (alloc),
    "Array_getslice": (alloc),         "Array_remslice": (alloc),
    "Array_splice": (alloc),           "Array_map": (alloc),
    "Array_map2": (alloc),             "Map_copy": (alloc),
    "List_array": (alloc),             "SymbolSet_encode": (alloc),
    "Url_parse_query": (alloc),        "Args_parse": (alloc),
    "String_base64_decode_bytes": (alloc),
    "String_base64url_decode_bytes": (alloc),
    "String_hex_decode_bytes": (alloc),
    "Scope_malloc_in": (alloc slot),   "Scope_calloc_in": (alloc slot),
    "Scope_memdup_in": (alloc slot),
    "Scope_malloc_finalized_in": (alloc slot),
    "cons": (pool),                    "Var_cons": (pool),
    "List_cons": (pool),
    "Array_push": (store),             "Array_insert": (store),
    "Array_unshift": (store),          "Array_setindex": (store),
    "Map_setindex": (store),           "Map_set": (store),
    "Map_setdefault": (store),         "Var_setindex": (store),
    "Var_map": (wrap),                 "Map_var": (wrap),
    "Symbol_var": (summary 0 ()),      "Var_integer": (summary 0 ()),
    "Var_is_row": (summary 0 ()),       "Var_kind": (summary 0 ()),
    "Var_int": (summary 0 ()),          "Var_is_void": (summary 0 ()),
    "Var_is_nil": (summary 0 ()),       "Var_is_atom": (summary 0 ()),
    "Map_len": (summary 0 ()),
    "List_len": (summary 0 ()),         "String_equal": (summary 0 ()),
    "Symbol_str": (alloc pool),
    "int_var": (summary 0 ()),          "uint_var": (summary 0 ()),
    "char_var": (summary 0 ()),         "uchar_var": (summary 0 ()),
    "short_var": (summary 0 ()),        "ushort_var": (summary 0 ()),
    "float_var": (summary 0 ()),        "double_var": (summary 0 ()),
    "long_var": (alloc),                "Var_box_long": (alloc),
    "ulong_var": (alloc),               "Var_box_ulong": (alloc),
    "Var_box_long_long": (alloc),       "Var_box_ulong_long": (alloc),
    "Var_box_long_double": (alloc),     "Var_clone_wide": (alloc),
    "Func_var": (wrap),
    "List_car": (summary 0 ((0 return))),
    "List_cdr": (summary 0 ((0 return))),
    "Array_getindex": (element),
    "Array_shift": (element),
    "Array_take_last": (element),
    "Array_remove": (element),
    "Map_getindex": (element),
    "Map_get": (element),
    "Map_del": (element),
    "Array_block": (wrap),              "Block_array": (wrap),
    "String_lower": (summary 2 ((0 return))),
    "String_upper": (summary 2 ((0 return))),
    "String_capitalize": (summary 2 ((0 return))),
    "String_strip": (summary 2 ((0 return))),
    "String_add": (summary 2 ((0 return) (1 return))),
    "puts": (summary 0 ()),             "File_puts": (summary 0 ()),
    "assert": (summary 0 ()),
    "Var_array": (wrap),               "Array_var": (wrap),
    "Var_list": (wrap),                "List_var": (wrap),
    "Var_string": (wrap),              "String_var": (wrap),
    "Var_block": (wrap),               "Block_var": (wrap),
    "Var_buffer": (wrap),              "Buffer_var": (wrap),
    "Array_free": (free),              "Array_list_free": (free),
    "Array_cleanup": (free),           "Map_cleanup": (free),
    "Block_free": (free),              "Block_cleanup": (free),
    "Bytes_cleanup": (free),           "Buffer_free": (free),
    "Buffer_cleanup": (free),          "Context_close": (free),
    "Context_cleanup": (free),         "Scope_free": (free scope),
    "xfree": (free scope),
    "Scope_destroy": (destroy),        "Scope_cleanup": (destroy),
    "Scope_open": (open scope),      "Scope_close": (close scope),
    "Pool_open": (open pool),          "Pool_close": (close pool),
    "Pool_open_named": (open pool),
    "Scope_push": (open slot),         "Scope_pop": (close slot),
    "Scope_move": (move),              "Context_export": (exit),
    "Block_move_to": (move),           "Buffer_move_to": (move),
    "Map_move_to": (move),             "Var_move_wide_to": (move),
    "List_promote": (exit),            "String_promote": (exit),
    "Atom_promote": (exit),
    "Var_as_iter": (wrap),             "Iter_var": (wrap),
    "Var_array_payload": (wrap),       "Var_block_payload": (wrap),
    "Var_buffer_payload": (wrap),      "Var_bytes_payload": (wrap),
    "Var_file_payload": (wrap),        "Var_iter_payload": (wrap),
    "Var_list_payload": (wrap),        "Var_map_payload": (wrap),
    "Var_adnode": (wrap),              "AdNode_var": (wrap),
    "Var_token": (wrap),               "Token_var": (wrap),
    "Var_file": (wrap),                "File_var": (wrap),
    "Var_job": (wrap),                 "Job_var": (wrap),
    "Var_jsonbool": (wrap),            "Var_regexcapture": (wrap),
    "Var_regexmatch": (wrap),          "Var_regex": (wrap),
    "List_job": (alloc final),
    "Job_start": (summary 0 ((0 return))),
    "String_lines": (summary 1 ((0 result))),
    "String_words": (summary 1 ((0 result))),
    "String_splits": (summary 1 ((0 result) (1 result))),
    "Var_fallback_iter": (summary 0 ((1 return))),
    "String_write_str": (summary 0 ((1 return))),
    "String_write_repr": (summary 0 ((1 return))),
    "List_write_str": (summary 0 ((1 return))),
    "List_write_repr": (summary 0 ((1 return))),
    "Var_write_str": (summary 0 ((1 return))),
    "Var_write_repr": (summary 0 ((1 return))),
    "Symbol_write_str": (summary 0 ((1 return))),
    "Symbol_write_repr": (summary 0 ((1 return))),
    "Atom_write_str": (summary 0 ((1 return))),
    "Atom_write_repr": (summary 0 ((1 return))),
    "Array_write_str": (summary 0 ((1 return))),
    "Array_write_repr": (summary 0 ((1 return))),
    "Map_write_str": (summary 0 ((1 return))),
    "Map_write_repr": (summary 0 ((1 return))),
    "Buffer_reserve": (summary 0 ((0 return))),
    "Buffer_clear": (summary 0 ((0 return))),
    "Buffer_write_len": (summary 0 ((0 return))),
    "Buffer_write": (summary 0 ((0 return))),
    "Buffer_write_char": (summary 0 ((0 return))),
    "Buffer_write_code_point": (summary 0 ((0 return))),
    "Buffer_write_repeat": (summary 0 ((0 return))),
    "Buffer_unwrite": (summary 0 ((0 return))),
    "Buffer_pad": (summary 0 ((0 return))),
    "Buffer_newline": (summary 0 ((0 return))),
    "Buffer_indent": (summary 0 ((0 return))),
    "Buffer_newline_indent": (summary 0 ((0 return))),
    "Buffer_push": (summary 0 ((0 return))),
    "Buffer_pop": (summary 0 ((0 return))),
    "Buffer_printf": (summary 0 ((0 return))),
    "Array_reverse": (summary 0 ((0 return))),
    "Array_setslice": (summary 0 ((0 return))),
    "Array_sort": (summary 0 ((0 return))),
    "Array_sort_with": (summary 0 ((0 return))),
    "Array_sort_by": (summary 0 ((0 return))),
    "Map_merge": (summary 1 ((0 return))),
    "Scope_new": (summary 0 ()),       "Scope_new_named": (summary 0 ()),
    "Context_open": (summary 0 ()),    "Context_current": (summary 0 ()),
    "Iter_new": (alloc),               "Iter_array": (alloc),
    "Iter_list": (alloc pool),
    "Iter_next": (summary 0 ()),       "Iter_count": (summary 0 ()),
    "Iter_sum": (summary 0 ()),        "Iter_product": (summary 0 ()),
    "Iter_max": (summary 0 ()),        "Iter_min": (summary 0 ()),
    "Array_iter": (summary 0 ((0 (param 1)) (1 return))),
    "List_iter": (summary 0 ((0 (param 1)) (1 return))),
    "Map_iter": (summary 0 ((0 (param 1)) (1 return))),
    "Map_keys": (summary 0 ((0 (param 1)) (1 return))),
    "Map_enumerate": (summary 0 ((0 (param 1)) (1 return))),
    "String_iter": (summary 0 ((0 (param 1)) (1 return))),
    "Var_iter": (summary 0 ((0 (param 1)) (1 return))),
    "range": (summary 0 ((3 return))),
    "Iter_map": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
    "Iter_filter": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
    "Iter_zip": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
    "Iter_chain": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
    "Iter_accumulate": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
    "Iter_enumerate": (summary 0 ((0 (param 2)) (2 return))),
    "Iter_repeat": (summary 0 ((0 (param 2)) (2 return))),
    "Iter_head": (summary 0 ((0 (param 2)) (2 return))),
    "Iter_unique": (summary 1 ((0 (param 1)) (1 return))),
    "Iter_zip_with":
      (summary 0 ((0 (param 3)) (1 (param 3)) (2 (param 3)) (3 return))),
    "Iter_map2":
      (summary 0 ((0 (param 3)) (1 (param 3)) (2 (param 3)) (3 return))),
    "Iter_scan":
      (summary 0 ((0 (param 3)) (1 (param 3)) (2 (param 3)) (3 return)))
  });

/* Runtime operations with a pooled result that the pass does not read:
   the table has no row for most, and the rows for Array_list_free and
   String_add state their argument effects. String_add may return an
   operand unchanged, and Atom_intern a value that already exists. */
static Map pooled_results = %{
  "Array_list_free": 1, "Atom_intern": 1, "List_append": 1,
  "String_add": 1,      "String_join": 1
};

/** The owner of the storage the runtime operation `name` returns: `<scope>`
    for the active Scope, `<slot>` for the Scope its first argument names,
    `<pool>` for the canonical-value pool, or 0 when nothing is known. What
    the operation does to its arguments is a separate fact.
*/
Symbol Compiler.region_result(String name) {
  match (runtime[name]) {
    case %(alloc slot): return <slot>;
    case %(alloc pool): return <pool>;
    case %(alloc *): return <scope>;
    case %(pool): return <pool>;
  }
  return name in pooled_results ? <pool> : 0;
}

/** Reports whether the runtime operation `name` returns its argument's
    storage unchanged, as a `Var` box or its unboxing does.
*/
int Compiler.region_wrapper(String name) => runtime[name] == %(wrap);

/** Reports whether the runtime table proves the lifetime effects of the
    native function `name`.
*/
int Compiler.has_region_row(String name) => name in runtime;

/** The runtime table's effect row for the operation `name`, such as
    `(open scope)` or `(exit)`, or void when the table has no row.
*/
Var Compiler.region_effect(String name) => runtime[name];

// runtime lifetime contracts

module Var _effect(Walk &w, String name) {
  if (!w.audit) return runtime[name];
  Var effect;
  return w.effects && w.effects.try_get(name, effect)
       ? effect : runtime[name];
}

/* typed families

   The macros that generate `Array` and `Map` also generate each typed
   family, so a typed member has the row of the boxed member of the same
   name, as `ArrayInt_copy` has the row of `Array_copy`. A typed family
   crosses to `Var` as its boxed family does, and a conversion between the
   two families allocates. */
static Map _typed_families(Map rows) {
  List names = rows.keys();
  foreach (List family in %(
      ("Array" "ArrayChar" "ArrayShort" "ArrayInt" "ArrayLong" "ArrayFloat"
       "ArrayDbl" "ArrayString")
      ("Map" "MapIntInt" "MapLongDouble" "MapStringString" "MapStringInt"
       "MapSubInt")))
    foreach (String typed in family.cdr())
      _typed_family(rows, names, family.car(), typed);
  return rows;
}

static void _typed_family(Map rows, List names, String boxed, String typed) {
  String prefix = %"$(boxed)_", lower = boxed.lower();
  foreach (String name in names)
    if (name.startswith(prefix)) rows[typed + name[boxed.len():]] = rows[name];
  rows[%"Var_$(typed.lower())"] = rows[%"Var_$lower"];
  rows[%"$(typed)_$lower"] = %(alloc);
  rows[%"$(boxed)_$(typed.lower())"] = %(alloc);
}
