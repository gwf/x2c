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
   (exit) hand their argument to another owner; (summary OWNER SINKS) is a
   literal summary. */
static Map runtime = %{
  "Scope_malloc": (alloc),           "Scope_calloc": (alloc),
  "Scope_memdup": (alloc),           "Scope_malloc_finalized": (alloc),
  "xmalloc": (alloc),                "xcalloc": (alloc),
  "xmemdup": (alloc),                "xrealloc": (alloc moved),
  "Scope_realloc": (alloc moved),    "String_malloc": (alloc pool),
  "String_new": (alloc pool),        "String_new_len": (alloc pool),
  "String_new_fill": (alloc pool),
  "Block_new": (alloc),              "Bytes_new": (alloc),
  "Array_new": (alloc),              "Map_new": (alloc),
  "Buffer_new": (alloc),
  "Scope_malloc_in": (alloc slot),   "Scope_calloc_in": (alloc slot),
  "Scope_memdup_in": (alloc slot),   "Scope_malloc_finalized_in": (alloc slot),
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
  "Func_var": (wrap),
  "List_car": (summary 0 ((0 return))),
  "List_cdr": (summary 0 ((0 return))),
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
  "Scope_retain": (open scope),      "Scope_release": (close scope),
  "Pool_open": (open pool),          "Pool_close": (close pool),
  "Scope_push": (open slot),         "Scope_pop": (close slot),
  "Scope_move": (move),              "Context_export": (exit),
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
  "Var_arraychar": (wrap),           "ArrayChar_var": (wrap),
  "Var_arrayshort": (wrap),          "ArrayShort_var": (wrap),
  "Var_arrayint": (wrap),            "ArrayInt_var": (wrap),
  "Var_arraylong": (wrap),           "ArrayLong_var": (wrap),
  "Var_arrayfloat": (wrap),          "ArrayFloat_var": (wrap),
  "Var_arraydbl": (wrap),            "ArrayDbl_var": (wrap),
  "Var_arraystring": (wrap),         "ArrayString_var": (wrap),
  "Var_mapintint": (wrap),           "MapIntInt_var": (wrap),
  "Var_maplongdouble": (wrap),       "MapLongDouble_var": (wrap),
  "Var_mapstringstring": (wrap),     "MapStringString_var": (wrap),
  "Var_mapstringint": (wrap),        "MapStringInt_var": (wrap),
  "Var_jsonbool": (wrap),            "Var_regexcapture": (wrap),
  "Var_regexmatch": (wrap),          "Var_regex": (wrap),
  "List_job": (alloc final),
  "Job_start": (summary 0 ((0 return))),
  "String_lines": (summary 1 ((0 result))),
  "String_words": (summary 1 ((0 result))),
  "String_splits": (summary 1 ((0 result) (1 result))),
  "Var_fallback_iter": (summary 0 ((1 return))),
  "Array_write_str": (summary 0 ((1 return))),
  "Array_write_repr": (summary 0 ((1 return))),
  "Map_write_str": (summary 0 ((1 return))),
  "Map_write_repr": (summary 0 ((1 return))),
  "Buffer_reserve": (summary 0 ((0 return))),
  "Buffer_clear": (summary 0 ((0 return))),
  "Buffer_write_len": (summary 0 ((0 return))),
  "Buffer_write": (summary 0 ((0 return))),
  "Buffer_write_char": (summary 0 ((0 return))),
  "Buffer_write_repeat": (summary 0 ((0 return))),
  "Buffer_unwrite": (summary 0 ((0 return))),
  "Buffer_pad": (summary 0 ((0 return))),
  "Buffer_newline": (summary 0 ((0 return))),
  "Buffer_indent": (summary 0 ((0 return))),
  "Buffer_newline_indent": (summary 0 ((0 return))),
  "Buffer_push": (summary 0 ((0 return))),
  "Buffer_pop": (summary 0 ((0 return))),
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
};

/* Runtime operations with a pooled result that the pass does not read:
   the table has no row for most, and the row for Array_list_free is its
   argument effect. A copy such as String_concat keeps none of its
   arguments, and Atom_intern may return a value that already exists. */
static Map pooled_results = %{
  "Array_list_free": 1, "Atom_intern": 1, "List_append": 1,
  "String_concat": 1,   "String_join": 1
};

module Var _effect(Walk &w, String name) {
  if (!w.audit) return runtime[name];
  Var effect;
  return w.effects && w.effects.try_get(name, effect)
       ? effect : runtime[name];
}

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
