# Pattern Matching

A `match` statement takes a `List` apart by describing the shape you expect.
Instead of a run of `List_car`, `List_cdr`, length checks, and tag tests, you
write a pattern that looks like the data, name the pieces you care about, and
use those names as ordinary local variables.

The `match` statement and the runtime matcher share one pattern language.
The exhaustive rules are in
[the language reference](../reference/language.md).

## The match statement

A `match` has a subject in parentheses and a sequence of arms. Each arm is
`case pattern:` followed by one statement, and an optional final `default:`
arm runs when nothing matched.

```x2c
List reply = %(status ok 200);
match (reply) {
  case %(status ok ?code):
    printf("ok with code %d\n", Var_int(code));
  case %(status ?state ?code):
    printf("%s with code %d\n", String_str(Var_str(state)), Var_int(code));
  default:
    printf("not a status reply\n");
}
```

The subject is evaluated once. Arms are then tried in source order, and the
**first** one that matches runs. The second arm above would also have matched,
but it is never tried. If no arm matches and there is no
`default`, the whole statement does nothing.

An arm's body is a single statement, so use braces when you want several.
A pattern is always a `%(...)` `List` literal.

For a single arm you may drop the outer braces, the same way you can
with `if`:

```x2c
List value = %(one);
match (value)
  case %(one):
    printf("no braces needed for a single arm\n");
```

Arm order is also cost order, so put cheap, common shapes first.

### Typed captures and expression guards

Write `?(Type name)` to capture a value as a native typed local. The pattern
tests the value's `Var` tag; a different tag fails the pattern without
converting the value. The supported types are the same as for `value is Type`.
The `?(` opener must be adjacent; `? (String text)` remains a wildcard
followed by a sublist pattern.

```x2c
List reply = %(message "ready");
match (reply) {
  case %(message ?(String text)) if (text.len() > 3):
    printf("long message: %s\n", text.str());
  case %(message ?(String text)):
    printf("short message: %s\n", text.str());
}
```

An optional `if (expression)` before the colon runs after the pattern
matches, with its captures in scope. A false guard tries the next arm;
errors propagate normally. The guard uses ordinary expression truth rules.

A typed name has the same type throughout its arm, including other
occurrences written as `?name` and occurrences in alternative patterns.
Repeated names still require equal values. `!quote` remains opaque, and the
existing rule that each binder must be assigned in every alternative still
applies. Explicit `(!is ?name type string)` keeps `name` as a `Var`.

The shorthand lowers to the existing `!is` pattern predicate and ordinary
typed local declarations. An expression guard lowers to an ordinary `if`;
both forms match exactly as the explicit patterns do.

## The pattern vocabulary

Patterns are written in `List`-literal notation, which is described in
[strings, lists, arrays, and maps](collections.md).

### Literals

A bare spelling in a pattern is an exact `Atom` that must appear in that
position. Numbers and strings compare by value, and `$name` or
`${expression}` unquotes a value to compare against. A pattern can require a
`match` with something computed at run time.

### Wildcards

`?` matches exactly one element and discards it. `*` matches any number of
elements and discards them.

### Binders

`?name` matches one element and binds it; `*name` matches a run of elements
and binds them as a `List`.

```x2c
List command = %(move 10 20 fast quiet);
match (command) {
  case %(move ?x ?y *flags):
    printf("to %d,%d with %d flag(s)\n",
           Var_int(x), Var_int(y), List_len(flags));
}
match (command) {
  case %(move ? ? *): printf("some move\n");
}
```

A `?name` binder is a `Var`; a `*name` binder is a `List`. A `*name` takes
the leftmost split that lets the rest of the pattern succeed, and matching a
`*name` against typed `nil` binds an empty `List` rather than failing.

Repeating a binder name in one pattern means "these must be equal":
`%(?x ?x)` matches `%(same same)` and rejects `%(other same)`.

Binder names follow the C identifier grammar, `[A-Za-z_][A-Za-z0-9_]*`. A
sigil followed by anything else is a mistake, and the compiler reports it with
a position. `%(node ?bad-name)` reports `invalid match binder name`.

### Nested shapes

A parenthesized group inside a pattern is a sublist, so nesting states nested
structure without any index arithmetic:

```x2c
List tree = %(tree (node 3 4) leaf);
match (tree) {
  case %(tree (node ?a ?b) ?rest):
    printf("%d\n", Var_int(a) * Var_int(b));
}
Symbol wanted = <leaf>;
match (tree) {
  case %(tree ? $wanted): printf("ends with the wanted tag\n");
}
```

### Guards

Six guard operators turn a position in a pattern into a test. Each is written
as a sublist headed by the operator.

`(!or a b ...)` succeeds when any alternative matches, `(!and a b ...)` when
all of them do, and `(!not a b ...)` when none of them do:

```x2c
List reply = %(status created 201);
match (reply) {
  case %(status (!or ok created) ?code):
    printf("success %d\n", Var_int(code));
  case %(status (!not ok) ?code):
    printf("failure %d\n", Var_int(code));
}
match (%(color green)) {
  case %(color (!and (!not red) (!not blue))):
    printf("neither red nor blue\n");
}
```

`(!set PATTERN ...)` is membership: it succeeds when any member matches.
`(!quote PATTERN)` compares the input to the pattern as literal data, with no
binder interpretation inside it. `(!is ...)` is the type and category
predicate: `(!is type string)` checks a `Var` tag, and `(!is atom)`,
`(!is binder)`, `(!is op)`, `(!is var binder)`, and `(!is list binder)` check
the named category.

Every guard except `!quote` accepts an optional leading binder, which
captures the slice of input the guard checked:

```x2c
match (%(node 7 8)) {
  case %(!set ?whole (node ?a ?b)):
    printf("%s holds %d and %d\n",
           String_str(Var_str(whole)), Var_int(a), Var_int(b));
}
match (%(key "abc")) {
  case %(key (!is type string)):
    printf("a String payload\n");
}
match (%(key 42)) {
  case %(key (!is ?found atom)):
    printf("an atom: %s\n", String_str(Var_str(found)));
}
match (%(tag (a b))) {
  case %(tag (!quote (a b))):
    printf("literally (a b)\n");
}
```

Runtime-built patterns may put an interned operator `Symbol` in the head
position. `List.match(input, %($op ...))` applies the same operator semantics
as its literal spelling, and the runtime operator suite checks `!or`, `!not`,
`!quote`, `!is`, and nested dynamic forms. Source `match` arms should spell
operators literally so the compiler can determine which named binders are
available to the arm body.

The `?binder?`, `*binder?`, and `!op?` spellings are reserved in `!is`
operand positions. They are not named binders and do not execute a predicate.
Use the `(!is ...)` forms above.

## Where binders live

Each arm declares its binders as local variables before its body is parsed. A
`?name` has type `Var`, a `*name` has type `List`, and either works with method
syntax. A binder is visible only inside the arm that introduced it, and it
shadows any outer name for the length of that arm:

```x2c
Var value = 99;
List input = %(pair 1 2);
match (input) {
  case %(pair ?value ?other):
    printf("inside the arm value is %d\n", Var_int(value));
}
printf("outside the match value is still %d\n", Var_int(value));
```

The same binder name can appear in two different arms, and a binder does not
exist after the `match` statement ends. There is no
"result of the `match`" to read afterwards; assign to a variable you declared
outside if you need to carry something out.

Method syntax follows those types:

```x2c
match (%(node (a b))) {
  case %(node ?child):
    printf("%d\n", child.list().len());
}
```

Named binders must also be definitely assigned whenever their arm matches.
Binders under `!not` are never available, and a binder under `!or` or
membership-style `!set` must occur in every alternative. `!quote` is opaque
literal data. The compiler diagnoses a maybe-bound name at the pattern.

## Lists, Var, and nil

The subject of a `match` is a `List`, so the shapes you can match are `List`
shapes. `Array`s, `Map`s, and `String`s are not `match` subjects.

A `Var` subject works because the compiler inserts the conversion to `List`
for you. The conversion does not check the tag, so only `match` a `Var` you
already know holds a `List`; test `Var_is(v, <list>)` at the boundary if you do
not. See [values and Var](values.md) for the tag rules and
[symbols and atoms](symbols.md) for what a bare pattern spelling means.

Nil is typed `List` data, not the absence of a `List`. A null `List` is a legal
subject, `%(*rest)` matches it and binds an empty `List`, and an explicitly
stored empty `List` inside a larger structure is a visible node that search can
find. What is *not* a node is the implicit terminal cdr of a proper `List`.

A `match` statement binds captured values to arm-local variables. Captured
values keep their ordinary [lifetime rules](memory.md). For a fixed symbol
followed only by unique named `?` binders, typed or not, the compiler emits
direct checks and captures; other patterns use the runtime matcher with the
same semantics.

## break and continue inside an arm

`break` in an arm body exits the `match`, not any enclosing loop. `continue`
skips to the next iteration of the enclosing loop:

```x2c
List items = %((skip) (keep) (skip));
int seen = 0, kept = 0;
foreach(Var item, items) {
  seen++;
  match (item) {
    case %(skip): continue;
    case %(keep): break;
  }
  kept++;
}
printf("seen %d, kept %d\n", seen, kept);
```

That prints `seen 3, kept 1`: the two `skip` items jump past `kept++`, while
the `keep` item leaves the `match` and falls through to it.

## The runtime matcher

The runtime matcher exposes the same pattern language as `List` methods. Use
it when the pattern is data, when you need the bindings as a value, or when
you are rewriting rather than dispatching.

`try_match` reports success separately from the bindings, and leaves its
output pointer untouched on failure. `match_replace` matches once and expands
a template from the bindings:

```x2c
List input = %(define x 10);
List bindings = NULL;
if (input.try_match(%(define ?name ?value), &bindings))
  printf("%s = %d\n",
         String_str(bindings.assoc(<?name>).str()),
         Var_int(bindings.assoc(<?value>)));
List rewritten = input.match_replace(%(define ?name ?value),
                                     %(assign ?name ?value));
printf("%s\n", rewritten.str());
```

Bindings are an association `List` keyed by the binder `Atom`, so you read them
with `assoc` and the same spelling you wrote in the pattern: `<?name>` for a
`?` binder and `<*rest>` for a `*` binder. These are standalone `Symbol`
literals, outside the `List` syntax that accepts bare `Atom`s.

The search family walks a whole structure instead of matching at the root.
`try_search` returns the first depth-first hit, `search` collects every hit,
and `search_replace` rewrites all of them:

```x2c
List tree = %(root (item 1) (wrapper (item 2)));
Var node = void;
List bindings = NULL;
if (tree.try_search(%(item ?id), &node, &bindings))
  printf("first id %d\n", Var_int(bindings.assoc(<?id>)));
printf("%d matches in all\n", tree.search(%(item ?id)).len());
printf("%s\n", tree.search_replace(%(item ?id),
                                    %(entry ?id)).str());
```

The `try_` forms report success separately from their results. `match` returns
bindings, `%(())` for a binder-free success, or `nil` on a miss.
`match_replace` returns the original input on a miss and `nil` for a successful
scalar replacement. `search` returns its results in reverse visitation order,
so do not read the list as document order. [The standard library
overview](../library/overview.md) has the full API list.

Each of these operations runs a pattern program rather than the pattern value.
When the pattern argument is a literal written at the call, the compiler gives
that call its own program, prepared once for the life of the process. A
pattern computed at run time -- built with `cons`, interpolated with `$`, or
received as a parameter -- is prepared for that call alone, so a loop over a
computed pattern pays one preparation per iteration. Hoist the literal out of
the loop, or match on it directly, when that cost matters. The arms of a
filtered `catch` follow the same rule.

## Match for shape, traversal for search

Use `match` when the data's structure determines what to do. Literal elements
specify what must be present; `?name` and `*tail` name the parts you will use.
Nested patterns describe sublists, and `default` handles the remaining cases.
A pattern made entirely of wildcards often calls for iteration instead.

A loop can find candidate values, then match each candidate:

```x2c
List program = %((set x 1) (call print x) (set y 2));
int assignments = 0;
foreach(Var node, program) {
  match (node) {
    case %(set ?name ?value):
      assignments++;
    case %(call ?fn *args):
      printf("call to %s\n", String_str(Var_str(fn)));
  }
}
printf("%d assignment(s)\n", assignments);
```

Use a plain `if` chain instead when there is no shape to state: one tag test,
one length check, one comparison. A `match` with a single arm whose pattern is
`%(?x)` buys nothing over the test you would have written. Use
[iteration](iteration.md) when order, accumulated state, or early exit
matters. A loop and a pattern can each do part of the work.

A binder does not check the captured value's type. `?value` captures whatever
was in that position. If the arm's body depends on the type, say so in the
pattern with `(!is type string)` or check the type before the `match`.

## Limitations to know up front

**`default` must be the last arm.** The compiler diagnoses a later arm. A final
`default` runs only when every earlier case failed.

**A `case` pattern must be a `%(...)` `List` literal.** The runtime matcher
accepts a standalone `Symbol` pattern such as `<?whole>`, but the statement
form does not. The compiler rejects any other case pattern with a positioned
x2c diagnostic before generating C.

**Source guard operators must be literal.** Runtime-built patterns may
interpolate an interned operator `Symbol`, but a source arm needs a literal
operator so definite binder assignment can be checked. The `?binder?` family
is reserved and is not a working predicate.

The [generated Match reference](../library/modules/match.md) lists the runtime
operations by API tier.
