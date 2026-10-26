/*  literal-cache.x -- compiler literal cache

    Interns immutable literal forms under stable unit cache IDs; dynamic
    values use runtime construction.
*/

/** Interns a constant key and returns its stable `(cache id)` reference. */
List Compiler.cache(Compiler c, List key) {
  List alias = _cache_alias(key);
  if (alias) return alias;
  int nextid = c.id_keys.len(), id = c.key_ids.setdefault(key, nextid);
  if (id == nextid) c.id_keys.push(key);
  return %(cache $id);
}

static List _cache_alias(List key) {
  match (key) {
    case %(cache ?):                          return key;
    case %(var (cache ?id)):                  return %(cache $id);
    case %(expr ? (cache ?id)):               return %(cache $id);
    case %(var (expr ("Var") (cache ?id))):   return %(cache $id);
  }
  return NULL;
}

/** Caches a cons cell when both parts have immutable cache forms.

    Returns `NULL` when runtime literals are required or either part cannot
    be represented by the immutable cache graph.
*/
List Compiler.cache_cons_cell(Compiler c, List head, List tail) {
  if (c.runtime_literals) return NULL;
  List head_cache = NULL, tail_cache = NULL;
  if (head ~= %(expr ("Var") (cache *))) head_cache = head.caddr();
  else if (head ~= %(cache *)) head_cache = head;
  if (!head_cache) return NULL;
  if (tail ~= %(expr ("List") (cache *))) tail_cache = tail.caddr();
  else if (tail ~= %(nil)) tail_cache = tail;
  if (!tail_cache) return NULL;
  List cached = c.cache(%(cons $head_cache $tail_cache));
  return %(expr ("List") $cached);
}

/** Interns an immutable value and returns its `(cache id)` reference.
    `value` is a `List` of such values, a `String`, a number with its tag, or
    a `Symbol`; any other value returns NULL.
*/
List Compiler.cache_literal_var(Compiler c, Var value) {
  if (value is <list>) {
    List cached = _cache_literal_list(c, value);
    return c.cache(%( var (expr ("List") (expr ("List") $cached)) ));
  }
  if (value is <string>) {
    List literal = %(expr ("String") (literal ("String") $value));
    List cached = c.cache(%(string $literal));
    return c.cache(%(var (expr ("String") $cached)));
  }
  if (value.is_integer() || value.is_floating())
    return _cache_boxed(c, c.meta_value_expression(NULL, value, NULL));
  if (value is <lsym>)
    return _cache_boxed(
      c, %(expr ("Atom") (literal ("Atom") $(value.str()) $value)));
  if (value is not <symbol>) return NULL;
  String spelling = value.symbol();
  List literal = %(
    expr ("Symbol") (literal ("Symbol") $spelling $value)
  );
  return c.cache(%(var $literal));
}

// A number or atom is cached through its conversion to a `Var`.
static List _cache_boxed(Compiler c, List literal) {
  literal = c.convert_expression(literal, %("Var"));
  return c.cache(%(var $literal));
}

static List _cache_literal_list(Compiler c, List values) {
  Array heads = auto [];
  foreach (Var value in values) heads.push(c.cache_literal_var(value));
  List cached = %(nil);
  for (int i = (int) heads.len() - 1; i >= 0; i--) {
    List head = heads[i];
    cached = c.cache(%(cons $head $cached));
  }
  return cached;
}

/** Returns a runtime `List` expression for cached compiler-owned syntax.

    `values` may contain nested `List`s, `String`s, integer `Var`s, and
    `Symbol`s.
*/
List Compiler.cache_literal_list(Compiler c, List values) {
  List cached = _cache_literal_list(c, values);
  return %(expr ("List") (expr ("List") $cached));
}
