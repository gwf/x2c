# Lowering with macros

A compiler lowering reads a parsed form and writes the C it stands for.
Written with macros, the lowering reads like its input and its output:
a `case` on a macro whose body is the source form recognizes the input, and a
template whose body is the C builds the output. This page shows the try
lowering, which every later lowering copies, and states the rules a
lowering meets. The try lowering is a shipped component,
`src/components/try-catch.x`, registered through `$rewrite` like
`src/components/bracket-access.x`. The
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
    Catch @arms) {
  try $body catch @arms finally $finalizer
}
```

The component registers its translator for both forms. `$rewrite` files the
patterns under the statement family keyed by the `try` head, and the cleanup
walk applies the rule to each `try` before it collects regions. A program's
rule on `try` runs there too, after the transform has lowered the parts of
the `try`. Binding and lowering the replacement keep each part it holds as
it is (`Compiler.rewrite_lowered` and `Compiler.lower_replacement`), so no
statement rule sees a part twice. A `return` that the replacement writes
converts to the function's declared result. A `defer` whose finalizer needs
a landing, such as one that returns, lowers to a `try` that the kernel
writes. That `try` is not source, so only the shipped rule lowers it
(`Compiler.rewrite_written`); a program's rule sees the finalizer's own
statements but not the `try`.

```x2c
$rewrite($caught)
$rewrite($tried)
/** Lowers the parsed try `node` to its landing form. */
meta Code try_lowering(Code node) {
  match (node) {
    case $caught(?body, ?finalizer, *arms):
      return _try_landing(node, body, arms, finalizer);
    case $tried(?body, ?finalizer):
      return _try_landing(node, body, NULL, finalizer);
  }
  return node;
}
```

## The lowering

The finalizer, the body, and each arm lower inside regions that only the
cleanup walk can open, so the translator answers a landing form,
`(landing CODE ROWS)`, instead of finished code. Each row names a token
that the walk replaces in CODE and in later rows with what the row lowered:
a fresh binding, bound exits, or a region that runs the exits bound before
it on every transfer out of it. The finalizer's region leaves the frame,
and the body and each arm run the try's exits. The walk applies the rows in
order and then binds CODE. `source_catch_handle` reads the handler the parser
introduced, which no source form writes.

```x2c
/* The landing form of the try `node`: its frame, its finalizer in a
   region that leaves the frame, its exits, then its body and each arm
   inside them. */
meta static Code _try_landing(
  Code node, List body, List arms, List finalizer) {
  _try_check_label(finalizer);
  Atom frame = Atom.intern("?__exception_frame");
  Atom exits = Atom.intern("?__try_exits");
  Atom lowered = Atom.intern("?__try_body");
  Atom finished = NULL;
  List handle = arms ? source_catch_handle(node) : NULL;
  Array rows = [%(new-name $frame "exception_frame")];
  if (finalizer) {
    Atom departure = Atom.intern("?__try_departure");
    finished = Atom.intern("?__try_finalizer");
    rows.push(%(exits $departure ${_try_departure(frame)}));
    rows.push(%(region $finished $finalizer));
  }
  rows.push(%(exits $exits ${_try_exits(frame, handle, finished)}));
  rows.push(%(region $lowered $body));
  List clause = _try_catch_clause(handle, arms, rows);
  Macro shape = $x2c.try.frame;
  List code = shape(frame, clause, lowered, exits);
  return Code.lowered(%(landing $code ${rows.list_free()}), NULL);
}
```

`_try_catch_clause` gathers the facts the templates are written from and adds
one region row for each arm.

```x2c
meta static List _try_catch_clause(List handle, List records, Array rows) {
  if (!records) return NULL;
  String state = "ERROR_CATCH_PENDING";
  Array arms = [], patterns = [];
  foreach (List record, records) {
    Code pattern = record.car();
    if (pattern) {
      if (!pattern.is_static_pattern()) state = "ERROR_CATCH_TRANSIENT";
      patterns.push(pattern);
    }
    Atom arm = Atom.intern(%"?__try_arm_${arms.len()}");
    rows.push(%(region $arm ${record.cadr()}));
    arms.push(arm);
  }
  return %($handle $state ${arms.list_free()} @{patterns.list_free()});
}
```

## The templates

A shipped component's own macros take `x2c.` spellings, such as
`$x2c.try.frame`. Only the compiler's prelude sources may define them, so
a program's macro or meta function never meets one by name. Adding or
renaming such a macro needs no bootstrap transition; changing the rule
that reserves the spelling does.

```x2c
/* A try pushes its frame and lands on it when something raises. */
macro Stmt $x2c.try.frame(
  Name $frame, Expr $clause, Stmt $body, Stmt $exits) {
  {
    ExceptionFrame $frame;
    @_x2c_try_catch_site($frame, $clause)
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else {
      x2c_exception_landed(&$frame);
      @_x2c_try_landing($frame, $clause, $exits)
    }
    @_x2c_try_exits_placement($exits)
  }
}

/* One catch site: its patterns prepared once, its handler pushed with
   them. */
macro Stmt $x2c.try.site(
  Name $frame, Name $handle, Expr $count, Expr $fallback, Expr $state,
  Expr @patterns) {
  static MatchCaptureSite arms[$count];
  Var patterns[$count];
  static ErrorCatchSite site = {arms, $fallback, $count, $state, -1};
  if (x2c_error_catch_site_pending(&site)) {
    @_x2c_try_catch_patterns(patterns, $patterns)
  }
  volatile ErrorHandler $handle =
    x2c_error_catch_site_push(&$frame, &site, patterns);
}

/* A landing that hands a raised error to the arm its handler selected. */
macro Stmt $x2c.try.handled(
  Name $frame, Name $handle, Stmt $unhandled, Stmt @arms) {
  if (x2c_exception_is_error_target(&$frame)) {
    int selected = x2c_error_catch_selected($handle);
    x2c_error_catch_detach($handle);
    x2c_exception_mark_handled(&$frame);
    @_x2c_try_catch_cases(selected, $arms)
  }
  else $unhandled
}
```

## The slot functions

A slot function is a public `meta` function of the component, so the
template finds it by name. Each one is defined before the definitions that
call it, because the compiler settles whether a linked copy reaches a
compile-time operation when the copy binds.

```x2c
/** Returns each lowered arm of `arms` chosen by its index in `selected`;
    `$x2c.try.handled` calls this in a slot. ... */
meta List _x2c_try_catch_cases(List selected, List arms) {
  Array cases = [];
  int index = 0, exits = 1;
  foreach (List arm, arms) {
    cases.push($!{ if ($selected == $index) $arm });
    index++;
    exits &= _try_arm_exits(arm);
  }
  if (exits) cases.push($!{ __builtin_unreachable(); });
  return cases.list_free();
}

/** Returns what runs when `frame` lands: the catch arm the clause's
    handler selected, or `exits` and no return; `$x2c.try.frame` calls
    this in a slot. ... */
meta List _x2c_try_landing(List frame, List clause, List exits) {
  Macro landing = $x2c.try.handled;
  List otherwise = $!{ { $exits __builtin_unreachable(); } };
  match (clause)
    case %(?handle ? ?arms *):
      return landing(frame, handle, otherwise, arms);
  return otherwise;
}
```

`_try_arm_exits` asks `Code.exits` whether an arm returns or raises on every
path, and `Code.is_static_pattern` decides whether a catch site prepares its
patterns once. Both are compiler queries declared in `lib/meta.x`.

## Where the rules stop

- A bound `defer` carries the environment, callback and records binding
  computed, and a bound `return` has no declared-type slot while a template
  writes one. No source-form macro matches either, so `_rewrite` recognizes
  them with a `%()` pattern and says why beside it.
- Lowering an arm needs the walk's region stack, so the translator names each
  arm with a region row and the walk lowers it before CODE binds; the slot
  functions number and place the lowered arms.
- The exits a region runs on a transfer are lexical. A `defer`, and an
  `x2c_place(%(block-exit), ...)` placement, also run on an `Error` transfer
  through a runtime record, which the try frame's landing replaces, so the
  try regions use exits rows instead.
- A slot argument in an expression position inside a `meta` body is an
  ordinary call, so a count the C needs in both a declarator and a call is
  a hole, as in the Func call template.

## Verbatim C text

A translator that returns a lowered carrier may write part of its result as
C text. A List whose head is a String is verbatim C: the emitter writes each
String in it as it is and emits each node between the Strings in place. The
transform and the cleanup walk step into those nodes, so an expression or a
statement placed in the text is lowered, and its `defer`, `return`, and
`break` run their exits as they would anywhere else. The parts of the source
statement lower outside the rule, so a nested statement of the same kind
applies it again. Statements the kernel writes while lowering, including
those a shipped rule's carrier writes, are not source and reach only shipped
rules, so a program's statement rules see the source parts but not them.
Definitions follow the same contract. A function the kernel writes, such as
a `defer`'s cleanup callback or a `Func` adapter, and one a shipped rule
places or returns, such as a lifted lambda or a protocol's forwarding
member, is written (`Ast.written_definitions`): only shipped function rules see
it, while its source statements still reach a program's statement rules. A
definition the source writes, or a program's meta code places or returns,
reaches every function rule (`_written_support` in `src/macros/rewrites.x`).
The walk does not read the text. Text therefore declares only locals that
no region owns, transfers control only where no region opens, and holds a
`switch` or a loop as a node, which stays the barrier its `break` and
`continue` need.
`unittest/compiler-fixtures/rewrite-verbatim-text.x` writes a match with only
a default arm as text around its subject and body:

```x2c
return Code.lowered(
  %(block ("counted++; (void) (" $subject "); {" $body "}")), NULL);
```

Prefer quotations. C text is for a lowering whose measured cost needs it.

## Choosing how to build syntax

Compiler and `meta` code that builds C writes it as C. Take the first
choice below that fits; a `%(...)` List of node tags is the last one. The
book owns the semantics:
[Quoting code with `$!`](../docs/src/guide/generating-code.md#quoting-code-with-)
and [Macro values](../docs/src/reference/language.md#macro-values). The
examples are excerpts from current source.

1. **A quotation**, for code the compiler binds where it lands. `$!( )`
   builds an expression, `$!{ }` statements, and `$!Unit{ }` or another
   category that kind of code. Names the body declares are private to
   that landing; other names resolve there. A quotation that applies no
   other template is built where it is written, so it costs about what the
   equal List costs (PR #130). From `_scope_expand` in `src/builtins.x`:

   ```x2c
   List enter = destinations ? $!( Scope_push(@destinations) )
                             : $!( Scope_retain() );
   List leave = destinations ? $!( Scope_pop() ) : $!( Scope_release() );
   return $!{ { $enter; { defer $leave; $body } } };
   ```

2. **Holes from locals.** `$name` inserts a local's value and `@name`
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
   result without a local, and `@{expr}` splices a List. The function
   evaluates each hole once, where the quotation is written, in written
   order. Call helpers this way rather than as `$helper(...)` slots. A slot
   makes the quotation apply a template, so it is no longer built where it
   is written (PR #135). `_loop` in `src/builtins.x`:

   ```x2c
   return $!{ { ${f.declaration} @setup while ($condition) $body } };
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
   work. `Compiler.run_once_body` in `src/generate/generate.x`:

   ```x2c
   List flag = $!int{ $guard };
   return c.rebuild_statement($!{ if ($flag) return; $flag = 1; }).cdr();
   ```

   A declaration of a bound name rebuilds the same way, so
   `c.rebuild_statement($!{ $storage_type $field; }).cadr()` needs no
   `declaration_parts`: a pointer, array, or function type moves its
   modifiers onto the declarator, as parsing does. `$!Type{ ... }` builds
   a constant type at once.

   [Retained template construction](#retained-template-construction)
   explains why the lambda producers use it.

A hand-built `%(...)` List is still right in these cases:

- **Patterns and data.** `case` patterns are not code. Neither are fact
  rows, such as the one `_try_catch_clause` returns above.
- **Parser productions.** The parser assembles nodes from children it has
  already parsed and bound, as in `%(while $cond $body)` in
  `src/statements.x`. A quotation would bind them again.
- **Binder output.** Identifier resolution in `src/expressions/expressions.x` returns
  `%(expr $type (ident $binding))`. A quotation would call the binder that
  is producing it.
- **Forms with no source spelling.** Examples are a call whose native
  callee is a String, as in `Ast.entry_call` in `src/ast.x`, the
  `(cache ID)` that `Compiler.cache` returns, and `(initval ...)`
  initializer rows.
- **Typed inner nodes.** A typed quotation types only its outermost
  expression. `_assignment` in `src/cache.x` also types the identifier
  inside: `%( stmnt (expr $type (op = (expr $type (ident $binding)) $rhs)))`.
- **Code queued with `Compiler.add_init`.** Generation splices it after the
  transform, so it must already be lowered. Bind a quotation for it only
  when nothing in it still needs lowering; a `String` literal still does.
  Otherwise build it from lowered pieces, as `_cache_value` in
  `src/cache.x` does.
- **Measured hot paths.** Keep the List where a converged A/B shows that
  the quotation costs more. As a quotation, `_assignment` cost 2.1% more
  (PR #142). A placed `$!Unit` quotation binds every declaration and
  expression of the function again, so `_lambda_function`,
  `_lambda_record`, and `_lambda_adapter` stay Lists. Translating
  `unittest/test-lambda.x` cost 0.6% more with the function as a
  quotation, and 4.9% more with all three. Measure before converting a
  producer that runs for every expression or statement.

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

The defer source macro recognizes the cleanup statement. `_lower_defer`
keeps region ownership and exit placement, then binds one statement
quotation. Its template visibly declares the cleanup record, pushes
it, runs the lowered body and leaves the region. The record slot chooses
plain or captured storage; the capture slot applies one field-assignment
template per captured address, in the established order. A zero-initialized
environment plus those assignments uses ordinary source forms without an
initializer sequence hole. Generated environment types go through the
ordinary declaration binder before these templates use their members.
