# Lowering with macros

A compiler lowering reads a parsed form and writes the C it stands for.
Written with macros, the lowering reads like its input and its output: a
`case` on a macro whose body is the source form recognizes the input, and a
template whose body is the C builds the output. This page shows the try
lowering, which every later lowering copies, and states the rules a
lowering meets. The
[dual-macro contract](../plans/archive/compiler-dual-macro-contract.md) uses these
rules as its acceptance test for later migrations. Any code that builds
syntax follows [Choosing how to build syntax](#choosing-how-to-build-syntax).

The campaign also reviews ownership across the compiler. Shared grammar
macros remove repeated knowledge of source structure; recognition-only use
is sufficient reason for a macro. Group related transformations and their
templates coherently while preserving shared semantic services. Individual
case conversions must serve that architecture, not determine it accidentally.
The contract's [historical handoff](../plans/archive/compiler-dual-macro-contract.md#current-campaign-handoff)
records the architectural survey and coordination agreement; E45 records the
delivered source-family coverage and retained boundaries.

## The rules

Apply MA-5 to MA-8 in [the standard](x2c-code-standard.md). A loop or a
choice among C shapes can use a slot function or ordinary code around
quotations, as MA-8 specifies.

The callable-defer producer supplies canonical `const void *` field rows
to its adjacent typedef template. Binding a `Field` template separately
loses the member type in the transform tree. Capture selection and type
checking remain with the transform owner.

## Recognition

`src/grammar.x` writes each form as its source. A `Catch` sequence hole
holds a try's catch arms, each a pattern and a body.

```x2c
/* A try whose only exit work is its finalizer. */
macro Stmt $tried(Stmt $body, Stmt $finalizer) {
  try $body finally $finalizer
}

/* A try with catch arms, each a pattern and a body, and a finalizer. */
macro Stmt $caught(Stmt $body, Stmt $finalizer,
    Catch $arms...) {
  try $body catch $arms... finally $finalizer
}
```

`Walk.rewrite` recognizes a try with them and makes one call. The `at` case
comes first: recognition looks through a position wrapper, and that case
records the position for reports.

```x2c
    case caught(?body, ?finalizer, *arms):
      return w._lower_try(node, body, arms, finalizer);
    case tried(?body, ?finalizer):
      return w._lower_try(node, body, NULL, finalizer);
```

## The lowering

`Walk._lower_try` reports a finalizer label, allocates the frame, lowers the
exits and the body, and applies one template. `catch_handle` reads the
handler the parser introduced, which no source form writes.

```x2c
/* Lowers the parsed try `node`: its body, its catch arms, which may be
   NULL, and its finalizer, which may be NULL. */
static List Walk._lower_try(
  Walk &w, List node, List body, List arms, List finalizer) {
  Compiler c = w.c;
  w._check_finalizer_label(finalizer);
  List frame = c._region_binding("exception_frame");
  List handle = arms ? catch_handle(node) : NULL;
  List cleanup = c._try_cleanup(frame, handle, w.rewrite(finalizer), !!arms);
  List lowered = w._try_region(cleanup, body);
  Macro shape = $compiler_try;
  return c.bind_syntax(
    shape(frame, w._catch_clause(handle, cleanup, arms), lowered, cleanup),
    AST_BLOCK, c.return_type);
}
```

The region driver lowers each arm, and `Walk._catch_clause` gathers the facts
the templates are written from.

```x2c
/* The facts `$compiler_try` writes a try's catch site and landing from,
   or NULL for a try without catches. Each arm is its own region, which a
   jump from the body may not enter, and leaves `cleanup` on its exits. A
   pattern with a dynamic part is prepared again on each entry. */
static List Walk._catch_clause(
  Walk &w, List handle, List cleanup, List records) {
  if (!records) return NULL;
  String state = "ERROR_CATCH_PENDING";
  Array arms = [], patterns = [];
  foreach (List record, records) {
    List pattern = record.car();
    if (pattern) {
      if (!w.c.match_pattern_is_static(pattern))
        state = "ERROR_CATCH_TRANSIENT";
      patterns.push(pattern);
    }
    arms.push(w._try_region(cleanup, record.cadr()));
  }
  return %($handle $state ${arms.list_free()} @{patterns.list_free()});
}
```

## The templates

```x2c
/* A try region pushes its frame and lands on it when something raises. */
macro Stmt $compiler_try(Name $frame, Expr $clause,
    Stmt $body, Stmt $cleanup) {
  {
    ExceptionFrame $frame;
    $builtin_try_catch_site($frame, $clause)...
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else {
      x2c_exception_landed(&$frame);
      $builtin_try_landing($frame, $clause, $cleanup)...
    }
    $builtin_try_cleanup_placement($cleanup)...
  }
}

/* One catch site: its patterns prepared once, its handler pushed with
   them. */
macro Stmt $catch_site(Name $frame, Name $handle, Expr $count,
    Expr $fallback, Expr $state, Expr $patterns...) {
  static MatchCaptureSite arms[$count];
  Var patterns[$count];
  static ErrorCatchSite site = {arms, $fallback, $count, $state, -1};
  if (x2c_error_catch_site_pending(&site)) {
    $builtin_catch_patterns(patterns, $patterns)...
  }
  volatile ErrorHandler $handle =
    x2c_error_catch_site_push(&$frame, &site, patterns);
}

/* One arm's pattern, prepared into its slot. */
macro Stmt $catch_pattern(Expr $patterns, Expr $index,
    Expr $pattern) {
  $patterns[$index] = $pattern;
}

/* A landing that hands a raised error to the arm its handler selected. */
macro Stmt $catch_landing(Name $frame, Name $handle,
    Stmt $unhandled, Stmt $arms...) {
  if (x2c_exception_is_error_target(&$frame)) {
    int selected = x2c_error_catch_selected($handle);
    x2c_error_catch_detach($handle);
    x2c_exception_mark_handled(&$frame);
    $builtin_catch_cases(selected, $arms)...
  }
  else $unhandled
}


/* One catch arm, chosen by its index. Each arm is its own statement, so a
   `break` or `continue` in it still reaches the enclosing loop, and only
   one test holds because `selected` does not change. */
macro Stmt $catch_case(Expr $selected, Expr $index,
    Stmt $arm) {
  if ($selected == $index) $arm
}


/* A landing no catch arm handles: the region's exits run, and control does
   not come back. */
macro Stmt $try_unhandled(Stmt $cleanup) {
  { $cleanup __builtin_unreachable(); }
}
```

## The slot functions

```x2c
/** Returns the catch site `frame` pushes for the clause `clause`
    describes, or nothing for a try without one; the `$compiler_try`
    template calls this in a slot. */
List builtin_try_catch_site(List frame, List clause) {
  Macro site = $catch_site;
  match (clause)
    case %(?handle ?(String state) ?(List arms) *patterns): {
      int count = arms.len(), filtered = patterns.len();
      return site(frame, handle, x2c_literal_int(count),
                  x2c_literal_int(filtered < count ? filtered : -1),
                  %(expr (int) $state), patterns);
    }
  return NULL;
}

/** Returns one `$catch_pattern` for each of `items`, prepared into the
    catch site's `patterns`; `$catch_site` calls this in a slot. */
List builtin_catch_patterns(List patterns, List items) {
  Macro prepare = $catch_pattern;
  Array prepared = [];
  int index = 0;
  foreach (List pattern, items)
    prepared.push(prepare(patterns, x2c_literal_int(index++), pattern));
  return prepared.list_free();
}

/** Returns what runs when `frame` lands: the catch arm the clause's
    handler selected, or `cleanup` and no return; the `$compiler_try`
    template calls this in a slot. */
List builtin_try_landing(List frame, List clause, List cleanup) {
  Macro unhandled = $try_unhandled, landing = $catch_landing;
  List otherwise = unhandled(cleanup);
  match (clause)
    case %(?handle ? ?arms *):
      return landing(frame, handle, otherwise, arms);
  return otherwise;
}

/** Returns one `$catch_case` for each lowered arm of `arms`, numbered in
    order and tested against `selected`; `$catch_landing` calls this in a
    slot. */
List builtin_catch_cases(List selected, List arms) {
  Macro choice = $catch_case;
  Array cases = [];
  int index = 0;
  foreach (List arm, arms)
    cases.push(choice(selected, x2c_literal_int(index++), arm));
  return cases.list_free();
}

```

## Where the rules stop

- A bound `defer` carries the environment, callback and records binding
  computed, and a bound `return` has no declared-type slot while a template
  writes one. No source-form macro matches either, so `Walk.rewrite` recognizes
  them with a `%()` pattern and says why beside it.
- Lowering an arm needs the walk's region stack, so `Walk._catch_clause` lowers
  the arms in a loop before the application; the slot functions number and
  place them.
- A slot argument in an expression position inside a `meta` body is an
  ordinary call, so a count the C needs in both a declarator and a call is
  a hole, as in the Func call template.

## Choosing how to build syntax

Compiler and `meta` code that builds C writes it as C. Take the first
choice below that fits; a `%(...)` List of node tags is the last one. The
book owns the semantics:
[Quoting code with `$!`](../docs/src/guide/meta-functions.md#quoting-code-with-)
and [Macro values](../docs/src/reference/language.md#macro-values). The
examples are excerpts from current source.

1. **A quotation**, for code the compiler binds where it lands. `$!( )`
   builds an expression, `$!{ }` statements, and `$!Unit{ }` or another
   category that kind of code. Names the body declares are private to
   that landing; other names resolve there. A quotation that applies no
   other template is built where it is written, so it costs about what the
   equal List costs (PR #130). From `_scope_expand` in `src/builtins.x`:

   ```x2c
   List enter = destinations ? $!( Scope_push($destinations...) )
                             : $!( Scope_retain() );
   List leave = destinations ? $!( Scope_pop() ) : $!( Scope_release() );
   return $!{ { $enter; { defer $leave; $body } } };
   ```

2. **Holes from locals.** `$name` inserts a local's value and `$name...`
   splices a List local. A `Type` local fills a type position, a binding
   identity names that binding, and an `int`, String, or Symbol becomes a
   literal. `_declare` in `src/builtins.x`:

   ```x2c
   static List _declare(Type type, Var binding, List initializer) =>
     initializer ? $!{ $type $binding = $initializer; } : $!{ $type $binding; };
   ```

   A declared name is private to one quotation. When separately built
   quotations must share a name, put `x2c_ident(...)` in a local and use it
   as the hole in each. `_fields_hash` in `src/builtins.x`:

   ```x2c
   List hash = x2c_ident("hash");
   Array body = [$!{ unsigned $hash = 0; }];
   foreach (List field, fields)
     body.push($!{
       $hash = x2c_hash_word($hash ^ Var_hash((Var)${_field_value(field)}));
     });
   body.push($!{ return $hash; });
   ```

   A name that must not collide with user names is a fresh binding from
   `c.sym.introduce(c.fresh_name(...))`, used the same way.

3. **Expression holes.** `${expr}` inserts a field, an element, or a call
   result without a local, and `${expr}...` splices a List. The function
   evaluates each hole once, where the quotation is written, in written
   order. Call helpers this way rather than as `$helper(...)` slots. A slot
   makes the quotation apply a template, so it is no longer built where it
   is written (PR #135). `Foreach.loop` in `src/builtins.x`:

   ```x2c
   return $!{ { ${f.declaration} $setup... while ($condition) $body } };
   ```

4. **A typed quotation.** `$!T{ expr }` builds `(expr T ...)` at once.
   `T` is one type identifier; a type of several words, a type hole, or a
   type spelled like a kind goes in parentheses, as `$!(T){ expr }`. Use it
   when an operation reads the type before the code lands, or when nothing
   binds the code again. It binds nothing, types only the outermost
   expression, converts nothing, declares no name, and applies no template.
   From `src/builtins.x`:

   ```x2c
   static List _iter_call(List function, List collection) =>
     $!Iter{ $function($collection) };

   static List _expr(List type, Var binding) => $!($type){ $binding };
   ```

5. **A retained rebuild.** `c.rebuild_statement(application)` and
   `c.rebuild_expression(type, application)` fill a template around
   children that are already bound or lowered, and bind nothing again. The
   template must be structural: no new names, no slots, and no template
   applications. `rebuild_statement` returns a `seq`; take its `.cdr()` or
   `.cadr()`. `rebuild_expression` applies a named template such as
   `$called`; for a one-off expression, a typed quotation does the same
   work. `_run_once` in `src/cache.x`:

   ```x2c
   List flag = $!int{ $guard };
   return c.rebuild_statement($!{ if ($flag) return; $flag = 1; }).cdr();
   ```

   A declaration of a bound name rebuilds the same way, so
   `c.rebuild_statement($!{ $storage_type $field; }).cadr()` needs no
   `declaration_parts`; `$!Type{ ... }` builds a constant type at once.

   [Retained template construction](#retained-template-construction)
   explains why the lambda producers use it.

A hand-built `%(...)` List is still right in these cases:

- **Patterns and data.** `case` patterns are not code. Neither are fact
  rows, such as the one `Walk._catch_clause` returns above.
- **Parser productions.** The parser assembles nodes from children it has
  already parsed and bound, as in `%(while $cond $body)` in
  `src/statements.x`. A quotation would bind them again.
- **Binder output.** Identifier resolution in `src/expressions.x` returns
  `%(expr $type (ident $binding))`. A quotation would call the binder that
  is producing it.
- **Forms with no source spelling.** Examples are a call whose native
  callee is a String, as in `_entry_call` in `src/cache.x`, the
  `(cache ID)` that `Compiler.cache` returns, and `(initval ...)`
  initializer rows.
- **Typed inner nodes.** A typed quotation types only its outermost
  expression. `_assignment` in `src/cache.x` also types the identifier
  inside: `%( stmnt (expr $type (op = (expr $type (ident $binding)) $rhs)))`.
- **Code queued with `Compiler.add_init`.** Generation splices it after the
  transform, so it must already be lowered. Bind a quotation for it only
  when nothing in it still needs lowering; a `String` literal still does.
  Otherwise build it from lowered pieces, as `_builtin_registration` in
  `src/protocol.x` does.
- **Measured hot paths.** Keep the List where a converged A/B shows that
  the quotation costs more. As a quotation, `_assignment` cost 2.1% more
  (PR #142). Measure before converting a producer that runs for every
  expression or statement.

## Rebuilding a bound source expression

### Canonical composition with metafunctions

Use an existing List metafunction when a family carries canonical rows that
an expression hole would reinterpret. String's `source_string_content`
owns the `segments` envelope while preserving cache, `segvar`, `segexp`, and
constructed `segraw` rows. Its callers retain conversion and resolution
order. This needs no new Segment parameter kind.

Recognize a source form with its macro inside a pattern: `${$indexed(?r,
?s)}` matches the typed expression or its bare content, and inside an
`(expr TYPE ...)` shell it is the content, so the shell captures the type. A
hole's argument may itself be a pattern, such as
`${$indexed(%(!set ?base (expr ?type ?)), ?index)}`; the macro's pattern is
derived with a binder in that hole first, so the argument keeps its exact
constraints. A bare-content dispatch arm keeps `source_content_pattern`,
whose fixed head lets the match emitter label the arm. Preserve the original
root and wrapper dispatch: a macro case can look through origins that a raw
case did not.

New native metafunctions must be available in the seed before their pattern
callers are compiled. Introduce the helper, regenerate linked meta, build a
capable seed, and then compile its adopters. Keep this transition local to the
batch; the final gate rebuilds from the shipped bootstrap.

### Retained template construction

The lambda parser and binder have already established capture identities,
parameter bindings and the result type. Applying an ordinary lambda template
there would bind the lambda again. These producers instead use the same
source templates through the compiler's retained construction operation:

```x2c
Macro captured = $lambda_captured, lambda = $lambda_expression;
if (captures)
  return c.rebuild_expression(type, captured(body, captures, params));
return c.rebuild_expression(type, lambda(body, params));
```

This internal operation shares template projection and substitution. It
preserves child stage, source wrappers and the known root type; it performs
no binding or effects. Its template must be purely structural, with no new
names, computed slots or child template calls. Ordinary lowering continues
to apply and bind templates as in the try example above. Rewriters traverse
outer position wrappers before rebuilding the typed expression within them.

## Defer registration

The defer source macro recognizes the cleanup statement. `Walk._lower_defer`
keeps region ownership and exit placement, then binds one statement
quotation. Its template visibly declares the cleanup record, pushes
it, runs the lowered body and leaves the region. The record slot chooses
plain or captured storage; the capture slot applies one field-assignment
template per captured address, in the established order. A zero-initialized
environment plus those assignments uses ordinary source forms without an
initializer sequence hole. Generated environment types go through the
ordinary declaration binder before these templates use their members.
