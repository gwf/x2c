# Lowering with macros

A compiler lowering reads a parsed form and writes the C it stands for.
Written with macros, the lowering reads like its input and its output: a
`case` on a macro whose body is the source form recognizes the input, and a
template whose body is the C builds the output. This page shows the try
lowering, which every later lowering copies, and states the rules a
lowering meets. The
[dual-macro contract](../plans/compiler-dual-macro-contract.md) uses these
rules as its acceptance test for later migrations.

The campaign also reviews ownership across the compiler. Shared grammar
macros remove repeated knowledge of source structure; recognition-only use
is sufficient reason for a macro. Group related transformations and their
templates coherently while preserving shared semantic services. Individual
case conversions must serve that architecture, not determine it accidentally.
The contract's [current handoff](../plans/compiler-dual-macro-contract.md#current-campaign-handoff)
records the architectural survey, remaining work and coordination agreement.

## The rules

Each rule is a property a reviewer can check by reading the code.

1. A lowering recognizes its input with a source-form macro or metafunction
   from `src/grammar.xmacro` and builds its output with a template. Primitive
   parsers produce canonical nodes; downstream source recognition shares
   their grammar owner. Bound semantic facts and normalized backend forms
   retain their documented stage-specific operations.
2. Every loop and every choice among C shapes is in a slot function the
   template calls, not in the client. A slot function takes the facts it
   needs as arguments and applies one macro per element.
3. A lowering function fits on a screen and makes one application.
4. No `code-value` literal appears outside a producer. A typed expression
   is bound already and passes to a hole as it is; lowered code is marked
   by the operation that lowered it.
5. Templates sit beside the lowering that applies them. Shared input forms
   live in `src/grammar.xmacro`; native builtin producers keep their output
   templates beside their scope, loop, and class algorithms.

The callable-defer environment is a narrow exception to the second rule's
slot placement: its producer supplies canonical `const void *` field rows to
the adjacent typedef template. Binding a `Field` template separately before
binding that typedef loses the member type in the transform tree. Keep these
rows in the producer until a direct field projection retains the type fact;
capture selection and type checking remain with the existing transform pass.

## Recognition

`src/grammar.xmacro` writes each form as its source. A `Catch` sequence hole
holds a try's catch arms, each a pattern and a body.

```x2c
/* A try whose only exit work is its finalizer. */
macro Statement $tried(Statement $body, Statement $finalizer) {
  try $body finally $finalizer
}

/* A try with catch arms, each a pattern and a body, and a finalizer. */
macro Statement $caught(Statement $body, Statement $finalizer,
    Catch $arms...) {
  try $body catch $arms... finally $finalizer
}
```

`_rewrite` recognizes a try with them and makes one call. The `at` case
comes first: recognition looks through a position wrapper, and that case
records the position for reports.

```x2c
    case caught(?body, ?finalizer, *arms):
      return _lower_try(walk, node, body, arms, finalizer);
    case tried(?body, ?finalizer):
      return _lower_try(walk, node, body, NULL, finalizer);
```

## The lowering

`_lower_try` reports a finalizer label, allocates the frame, lowers the
exits and the body, and applies one template. `catch_handle` reads the
handler the parser introduced, which no source form writes.

```x2c
/* Lowers the parsed try `node`: its body, its catch arms, which may be
   NULL, and its finalizer, which may be NULL. */
static List _lower_try(
  Walk walk, List node, List body, List arms, List finalizer) {
  Compiler c = walk.compiler;
  _check_finalizer_label(walk, finalizer);
  List frame = _region_binding(c, "exception_frame");
  List handle = arms ? catch_handle(node) : NULL;
  List cleanup = _try_cleanup(
    frame, handle, _rewrite(walk, finalizer), !!arms);
  List lowered = _try_region(walk, cleanup, body);
  Macro shape = $compiler_try;
  return c.bind_syntax(
    shape(frame, _catch_clause(walk, handle, cleanup, arms), lowered,
          cleanup),
    AST_BLOCK, c.return_type);
}
```

The region driver lowers each arm, and `_catch_clause` gathers the facts
the templates are written from.

```x2c
/* The facts `$compiler_try` writes a try's catch site and landing from,
   or NULL for a try without catches. Each arm is its own region, which a
   jump from the body may not enter, and leaves `cleanup` on its exits. A
   pattern with a dynamic part is prepared again on each entry. */
static List _catch_clause(
  Walk walk, List handle, List cleanup, List records) {
  if (!records) return NULL;
  String state = "ERROR_CATCH_PENDING";
  Array arms = [], patterns = [];
  foreach (List record, records) {
    List pattern = record.car();
    if (pattern) {
      if (!walk.compiler.match_pattern_is_static(pattern))
        state = "ERROR_CATCH_TRANSIENT";
      patterns.push(pattern);
    }
    arms.push(_try_region(walk, cleanup, record.cadr()));
  }
  return %($handle $state ${arms.list_free()} @{patterns.list_free()});
}
```

## The templates

```x2c
/* A try region pushes its frame and lands on it when something raises. */
macro open Statement $compiler_try(Name $frame, Expr $clause,
    Statement $body, Statement $cleanup) {
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
macro open Statement $catch_site(Name $frame, Name $handle, Expr $count,
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
macro open Statement $catch_pattern(Expr $patterns, Expr $index,
    Expr $pattern) {
  $patterns[$index] = $pattern;
}

/* A landing that hands a raised error to the arm its handler selected. */
macro open Statement $catch_landing(Name $frame, Name $handle,
    Statement $unhandled, Statement $arms...) {
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
macro open Statement $catch_case(Expr $selected, Expr $index,
    Statement $arm) {
  if ($selected == $index) $arm
}


/* A landing no catch arm handles: the region's exits run, and control does
   not come back. */
macro open Statement $try_unhandled(Statement $cleanup) {
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
  writes one. No source-form macro matches either, so `_rewrite` recognizes
  them with a `%()` pattern and says why beside it.
- Lowering an arm needs the walk's region stack, so `_catch_clause` lowers
  the arms in a loop before the application; the slot functions number and
  place them.
- A slot argument in an expression position inside a `meta` body is an
  ordinary call, so a count the C needs in both a declarator and a call is
  a hole, as in the Func call template.

## Rebuilding a bound source expression

### Canonical composition with metafunctions

Use an existing List metafunction when a family carries canonical rows that
an expression hole would reinterpret. String's `source_string_content`
owns the `segments` envelope while preserving cache, `segvar`, `segexp`, and
constructed `segraw` rows. Its callers retain conversion and resolution
order. This needs no new Segment parameter kind.

Derive a source pattern with simple named holes before inserting a consumer's
exact constraints. `source_pattern_with` does this for indexed designation;
passing a nested wildcard through ordinary hole projection instead quoted it
and lost the `volatile` designation. Preserve the original root and wrapper
dispatch: a macro case can look through origins that a raw case did not.

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

The defer source macro recognizes the cleanup statement. `_lower_defer`
keeps region ownership and exit placement, then makes one application of
`$compiler_defer`. Its template visibly declares the cleanup record, pushes
it, runs the lowered body and leaves the region. The record slot chooses
plain or captured storage; the capture slot applies one field-assignment
template per captured address, in the established order. A zero-initialized
environment plus those assignments uses ordinary source forms without an
initializer sequence hole. Generated environment types go through the
ordinary declaration binder before these templates use their members.
