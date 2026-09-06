# ASTs as x2c's shared compiler language

ASTs are not merely shared storage. They are the shared language spoken by
the parser, macros, compile-time Lisp, Match, transforms, and the C backend.
That is stronger than preferring `match` over `car()` and `cdr()`: it means a
new way of producing syntax should normally construct the same canonical AST
and enter the same semantic operations as ordinary source.

Match owns structural recognition and substitution. Literal templates own
fixed output structure. Ordinary compiler operations own meaning: binding
names, resolving types, opening scopes, enforcing placement and lifecycle,
preserving source positions, issuing diagnostics, and ordering emission. A
macro, Lisp function, or transform should not acquire a second implementation
of those operations merely because it produced the AST differently.

The macro path in `src/macros.x` is the current vertical example. An invocation
parses typed capture rows, matches them against the definition, and performs
one `template.replace(replacement_bindings)`. The resulting `constructed` AST
then goes to `Compiler.bind_syntax` with its `AstPos` and return type. From
there, the ordinary recursive syntax binder calls the declaration,
expression, statement, function, scope, and protocol operations also used by
source parsing. Some orchestration around those operations remains separate;
shared reachability is a reason to inspect it, not proof that the paths are
already identical. There is no macro-only grammar or post-expansion validator.

When designing compiler work, ask these questions before choosing machinery:

1. What canonical AST does the producer already construct?
2. Can the structural change be stated as a Match pattern and visible output
   template?
3. Which ordinary semantic operation should consume the result?
4. What genuinely operational work remains after the structure is matched?

Keep genuinely primitive work in the compiler. Binding, typing, cleanup,
ABI handling, lifecycle, diagnostics, and ordered C emission are not textual
substitutions. The opportunity is to let every source of canonical syntax use
those primitives rather than growing another route to them.

Do not send an already bound and typed transform result through
`Compiler.bind_syntax` merely to make two call graphs look alike. Reuse is
real when it deletes parallel semantic construction. A no-op rebinding pass
that leaves the producer's binding, typing, conversion, and placement work in
place is another traversal, not consolidation.

The method below grew from the `hamburg-v3` rewrite, prepared in commits
`6d7766fa` and `97cf8dd9` and merged as `e1dcfa1c` through PR #467. PR #516
then established the same model vertically for macro construction.

The code fragments below are illustrative excerpts, not standalone programs.

The authored changes covered `src/emit.x`, `src/expressions.x`,
`src/macros.x`, and `src/transform.x`. They replaced positional AST decoding,
recursive cons-cell walking, and small tag-dispatch helpers with structural
patterns, named captures, ordinary collection iteration, and literal AST
templates. The authored source became 58 lines smaller even though many
previously compressed positional expressions were expanded into named cases.

## The fact that unlocked the rewrite

An x2c AST is not fundamentally a `List`. It is an instance of a grammar
production whose storage happens to be a `List`.

The old code approached a node as storage:

1. check that the value is a List;
2. read `car()` to discover the tag;
3. check `len()`;
4. read `cadr()`, `caddr()`, or a longer `cdr()` chain;
5. convert the extracted `Var` values;
6. repeat some of those checks in a helper;
7. construct the result with `cons()` because the implementation is already
   thinking in cons cells.

The successful code approached the same node as syntax:

```x2c
match (ast) {
  case %(expr ?type ?content): ...
  case %(call ?function (args *arguments)): ...
  case %(op ?operator ?left ?right): ...
}
```

That change of model mattered more than any individual syntax substitution.
Once the grammar production was visible, the field names, legal alternatives,
arity, and output shape could all be written in one place. The code stopped
needing a second, procedural description of the AST layout.

The other decisive fact was that structural recognition and semantic
decisions do not have to be combined. A pattern can establish that a node is
an `(expr TYPE VALUE)` while the case body still asks whether `TYPE` is a Var
type, whether an operator has a protocol member, or whether a captured binding
is automatic. Earlier attempts treated the remaining semantic question as a
reason to keep the entire manual structural walk. It is not. `match` owns the
shape; ordinary code inside the case owns the semantics.

## The compiler is a recursive-descent parser

The parallel protocol, expression, and lambda rewrites exposed a missing part
of the original guidance. Agents could replace selectors with `match` and
still retain head-only dispatch, pass the full node onward, or monolithically
interpret several productions. `match` is the syntax; recursive descent is
the design that makes it useful.

Do not read "parser" narrowly as only the code that turns source tokens into
the first AST. The compiler continues to interpret a grammar at every later
stage. A parsing function receives the token stream positioned at the start of
a production. A resolver, transform, or emitter receives an AST positioned at
the root of a production. In both cases the normal operation is the same:

1. match the next grammatical alternative;
2. consume the distinguishing prefix;
3. bind the parts established by that match;
4. pass a child, tail, or other more specific value to the function that owns
   the next grammatical rule;
5. form and return the resulting subtree.

For a token parser, consuming the prefix advances the token stream. For an AST
consumer, it means destructuring the production and passing its captures
forward instead of handing the complete node to another function that parses
the same head again.

For example, after matching:

```x2c
case %(expr ?type (call ?callee (args *arguments))):
```

the caller knows that it has an expression, knows its type, knows that its
content is a call, and has the callee and argument sequence. The next function
should receive `type`, `callee`, and `arguments` as appropriate. It should not
receive the original expression and repeat the `expr`, `call`, and `args`
checks before doing its work.

Every dispatch should therefore advance what the program knows. Matching only
the constant head and then passing the unchanged AST onward wastes the match.
It is another form of distrusting an internal value: the caller established a
fact but its callee refuses to use it. A useful function boundary removes an
already recognized prefix from the next function's problem.

This also determines where functions should be split. Do not make one
monolithic function interpret several independent grammar rules through
nested switches, selector chains, flags, and temporary state. Match the rule
owned by the current function, capture what the next rule needs, and descend.
Conversely, do not preserve tiny helpers whose only job is to receive the
whole node and decode the same positions again. Keep a helper when it owns the
next grammatical decision or substantial semantic behavior, and give it the
already narrowed inputs.

A practical test for every recursive call or helper call is: **what
uncertainty did this call's caller eliminate?** If the callee must recognize
the same head or recover the same fields, the descent has not advanced.

## What I needed to know before changing the code

### 1. Which component had already established the shape

The rewrite depended on knowing whether the value came from arbitrary source
or from an x2c producer that had already parsed, bound, typed, or lowered it.
For every family, I needed to trace the node back far enough to state its
canonical forms.

For example, the emitter does not receive arbitrary Lists. It receives the
compiler's lowered AST. A transform consumer does not need to rediscover that
an operator node has the shape selected by the parser and expression resolver.
Public macro SDK operations still own their argument types and arity. A raw
canonical AST List returned by compile-time Lisp is different: x2c
deliberately accepts its structure without authenticating whether the parser,
a template, a capture, or handwritten Lisp produced it. Do not add origin
tracking or a parallel validator to distinguish those producers. The complete
language rule is in `docs/src/reference/language.md` under "Macro-visible
syntax".

This did not mean deleting every semantic error. It meant deleting or avoiding
consumer-side shape validation that merely repeated the producer. A missing
pattern can fall through to the existing compiler path. It does not need a new
catch-all diagnostic merely because a manual checker used to have one.

### 2. Enough of the pattern language to describe the real grammar

Simple `case %(tag ?field)` patterns were not enough. The broad rewrite became
possible because the source matcher can express the structures that the old
code was manually probing:

- `*items` captures the remaining sequence;
- `(!or a b c)` expresses tag alternatives;
- `(!set ?node PATTERN)` captures a complete subtree while also destructuring
  it;
- `(!is ?name type string)` combines a capture with a genuine dynamic type
  requirement;
- nested patterns describe nested grammar productions directly;
- `(!quote ->)` and similar forms distinguish punctuation that would
  otherwise be pattern syntax.

`!set` was especially important. It lets a case name both a semantic whole and
its relevant interior. For example, a transform can capture the complete
expression for reuse while also binding its type:

```x2c
case %(postfix ?operator
               (!set ?argument (expr ?argument_type ?))):
```

Without that facility, an agent is tempted to match the tag and then resume
walking the original node by position.

### 3. Which matching form fits each job

Four forms were needed, and treating them as interchangeable would have made
the result worse.

- Use a source `match` when static alternatives select local control flow and
  the captures are consumed in that branch.
- Use `match_replace` for a pure static template extraction or replacement,
  such as obtaining a function body or converting a function definition to a
  declaration shape.
- Use flat destructuring for one unconditional, already trusted fixed shape.
- Use `foreach` for the generic operation "visit every child". The matcher
  recognizes node grammar; iteration traverses the collection.

Keep runtime `List.match` when the pattern itself is built or selected at
runtime, when its binding List must escape, or when direct source captures do
not express the operation. The problem was not that every use of List methods
was wrong. The problem was using runtime match plus `assoc`, or positional
selectors, to rediscover a static source grammar and consume all captures
immediately.

### 4. The output grammar had to be equally visible

The rewrite was incomplete if it matched the input declaratively and then
returned a node with `cons()`.

When a function returns a fixed AST form, the return should be an AST literal:

```x2c
return %(raise $cause (args @converted));
return %(block @body);
return %($node @tail);
```

The literal is the output grammar. A reviewer can compare the input pattern
and output template without executing a cons-cell program mentally. `cons()`
still belongs where newest-first accumulation or suffix sharing is the actual
algorithm. It does not belong merely because AST nodes use List storage.

### 5. Match captures do not remove semantic ordering requirements

The pattern can bind all children at once, but transformations and emission
may still have side effects or required source order. In `Emitter.emit`, the
successful rewrite assigns emitted operands to named locals in order before
building the returned token literal. It does not hide several emitter calls
inside a compact expression and assume their evaluation order is harmless.

The same caution applies to:

- cleanup-stack entry and exit around loop bodies;
- temporary compiler state such as source origin and function owner;
- left-to-right call operand materialization;
- fixed-point transforms that distinguish an unchanged node from a rewritten
  one;
- match arm order when shapes overlap.

Declarative structure does not mean erasing operational semantics. It means
making the structure declarative and leaving the necessary operations explicit
inside the matching case.

### 6. x2c's implicit conversions, including their limits

The final cleanup removed six `.var()` calls introduced by the first rewrite.
A function returning `Var`, a `Var` assignment, or an `Array.push` argument
already supplies the target type. A returned List or String should normally be
written in its natural type and boxed by that context.

Two details required generated-C inspection:

1. The conditional operator resolves the types of its two branches before the
   surrounding target conversion. A `List` branch and a `Var` branch therefore
   cannot always be written as one ternary without explicit boxing. The right
   answer was direct branch control flow, not restoring `.var()`.
2. Removing `child.list()` from a known-List branch caused the generic
   Var-to-pointer conversion to win and generated `Var_pointer(child)` rather
   than `Var_list(child)`. Restoring `.list()` preserved the intended checked
   extraction while leaving the result's List-to-Var boxing implicit.

The rule is not "remove every converter." It is "let a real target type request
the conversion, and inspect generated C when aliases or mixed expressions can
change which converter wins."

## The successful conversion patterns

### Turn positional recognizers into grammar cases

`_direct_identifier` and `_addressed_identifier` in `src/emit.x` previously
checked the head tag and then selected `cadr()` or `caddr()` differently for
each tag. They now state the accepted grammar directly:

```x2c
match (ast) {
  case %(ident ?binding): ...
  case %(expr ? ?inner): ...
  case %(parens ?inner): ...
  case %(index (!set ?base (expr ?base_type ?)) ?): ...
  case %(op . ?base *): ...
}
```

The useful review question is now "are these the accepted lvalue shells?" The
old review question was "does each selector still point at the intended list
position after all preceding guards?"

### Match the node, then keep semantic probes in the case

`_transform_operator` in `src/transform.x` did not become a giant pattern that
tried to encode type resolution and protocol behavior. It matches the operator
and typed-expression forms, names `operator`, `lhs`, `rhs`, `argument`, and
`argument_type`, and then performs the existing semantic resolution inside
those cases.

This is the central answer to the objection that semantics still need probing:
they can be probed after the structure has already been named. Manual
destructuring is not a prerequisite for semantic logic.

### Replace runtime match results and `assoc` with source captures

The defer capture functions previously called `ast.match(...)`, received a
binding association List, and immediately recovered `type` and `binding` with
`assoc`. Source `match` now binds those values directly in the branch:

```x2c
match (ast)
  case %(expr ?captured_type (ident ?bound)): {
    ...
  }
```

This removes an intermediate result representation and its follow-up walks.
It also gives generated code direct capture slots instead of constructing and
searching an association List.

### Separate recursive traversal from structural recognition

Several old walkers recursively processed `car(ast)` and `cdr(ast)`, mixing
"what kind of node is this?" with "visit every nested value." The successful
form is:

```x2c
match (ast)
  case %(SPECIAL-SHAPE ...): ...

foreach(Var child, ast)
  if (child is <list>) visit(child.list());
```

For a transforming walk, use an `Array`, transform each item in order, and
return `items.list_free()`. For a recursive tail rewrite whose suffix is
semantically important, bind `%(?head *tail)` and return a literal splice.

This is not a ban on walking trees. It removes manual cons-cell traversal from
code whose real purpose is recognizing and rewriting syntax.

### Collapse helper families into the grammar dispatcher

The largest improvement came from treating `Emitter.emit` as the declarative
owner of many AST productions. Small helpers such as `emit_cast`, `emit_call`,
`emit_index`, `emit_if`, `emit_while`, and `emit_return` existed largely to
decode one tag's positional fields. Their cases now live together in the
source `match`, while helpers remain only where they own substantial behavior.

This made the emitted grammar visible in one place and deleted the repeated
"dispatch by tag, then decode by positions" layer. It also exposed genuine
shared behavior: Array and Map literals could share `emit_var_collection`
because the only semantic difference was their target name.

This is not an instruction to make one giant function own every lower grammar
rule. The dispatcher should own the current choice. A case that reaches a new
grammar rule should call a function for that rule with the named captures,
not with the original AST. Helpers disappeared from `Emitter.emit` when they
only repeated its positional decoding; a helper with real recursive-descent or
semantic work should remain and receive narrower arguments.

The important unit was the function family, not one selector. Replacing one
`caddr()` at a time would have preserved the tangle of helpers and missed the
main simplification.

### Use template replacements for pure AST projections

The macro SDK function helpers were especially clear examples:

- function name: match the function declarator and capture its binding;
- function type: replace the function form with the declaration form;
- function parameters: replace the nested function-modifier structure with
  its bound parameter sequence;
- function body: replace `(function ... (block *body))` with `(*body)`.

These operations are mappings between visible templates. Writing them as
selector chains concealed both the input and output. `match_replace` made each
mapping nearly identical to its grammatical description.

## What I had to be prepared to delete

The code would not have become substantially better if the matcher had merely
been added beside the old machinery. The rewrite required willingness to
delete:

- tag, length, and nested-List checks already implied by the pattern and its
  producer;
- `List.match` result objects and immediate `assoc` extraction;
- helpers whose only job was positional decoding;
- recursive `car`/`cdr` walkers when `foreach` expressed the traversal;
- status and fallback paths that treated an impossible internal shape as
  ordinary absence;
- the emitted binding-identity validator and its validator-only forged-input
  fixture;
- `cons()` construction used only to spell fixed AST shapes;
- explicit `.var()` calls already selected by return, assignment, or argument
  types.

It was also necessary to accept that the connected source would be temporarily
unbuildable while the dispatcher signatures, helper deletions, call sites, and
templates were being changed together. That intermediate state was not
evidence that the direction was wrong. Running the full repository gate at
each such point would have forced the work back toward tiny local edits and
made the family-level rewrite practically impossible.

## The failure modes other agents need to avoid

### Do not classify forever instead of rewriting

A scanner score or validator label can identify a place to read. It cannot
decide the new code. The strong clue is often simply a nearby `cadr()` or
`caddr()` combined with a tag check. Once the producer is known, the agent
should attempt to write the grammar case, not spend another pass refining the
candidate category.

### Do not demand that a pattern contain all semantics

This false requirement kept manual walks in place. Match the structure first.
Keep protocol lookup, type compatibility, name comparison, ownership, and
other semantic questions as normal case-body code.

### Do not translate guards mechanically into more guards

The goal is not:

```x2c
match (ast)
  case %(expr ?type ?value):
    if (!type || value is not <list>) report_error(...);
```

unless those facts are genuinely not established and the rejection owns
deliberate behavior. A catch-all assertion, new diagnostic, or `try_*` helper
is relocated validation, not simplification.

### Do not match a tag and then keep navigating by position

If the case body still says `ast.caddr()`, the pattern has not done its job.
Capture that child by its semantic name. Use `!set` when both the subtree and
one of its fields are needed.

### Do not stop at a head-only match

A pattern such as `case %(expr *)` is only useful if the complete remainder is
genuinely the next operation's input. Usually the production has more usable
structure: its type, operator, callee, arguments, receiver, fields, or body.
Bind those parts in the first match and pass them forward.

Do not route to a helper that immediately matches `expr` again. Do not match
every operator and then pass an `(op ...)` node to code that rediscovers the
operator and arity. Once the operator family is known, the next match can
distinguish its unary, binary, and ternary productions, or the current case can
call those handlers with their operands. Each step should consume a real part
of the grammar.

### Do not parse several grammar rules monolithically

A long sequence of tag tests, arity calculations, positional reads, flags,
and fallbacks often means one function is trying to interpret a parent rule
and several child rules at once. Identify the grammar boundaries. Let the
parent match select and bind its production, then recurse with the child or
remaining sequence.

The split is grammatical, not a line-count exercise. A large `match` can be a
clear dispatcher, and a short helper can still be wrong if it reparses its
caller's node. The deciding question is whether every function receives the
input at the beginning of the rule it owns.

### Do not hide the returned AST in construction code

If the result is a fixed or spliced syntax form, use `%()` with `$` and `@`.
Do not return `cons(tag, cons(...))`, and do not create a builder helper whose
only purpose is to obscure the same shape one level away.

### Do not make every traversal a recursive match

Use `foreach` for ordinary child visitation. Use Array accumulation for an
ordered transformed sequence. Keep explicit cursor traversal when cursor
state, suffix sharing, ownership, or an actual sequence algorithm is the
point.

### Do not use broad validation as an editing loop

The productive loop was source reasoning, one coherent family rewrite,
generated-C inspection where conversion or evaluation order was subtle, and
focused fixtures. The independent review happened before the single final
`make agent-pr-check`. Broad gates were proof of the finished tree, not a
substitute for understanding each edit.

## A repeatable method for broader work

### 1. Select a connected grammar family

Work by producer and consumer family: emitter expression forms, transform
operator forms, macro function forms, defer walkers, field declarations, and
so on. Do not assign isolated selector occurrences to separate agents.

Search clues should include:

- `.cadr()`, `.caddr()`, longer `.cdr()` chains, and indexed AST reads;
- `car()` tag switches followed by positional reads;
- `len()` adjacent to tag or child-type checks;
- `List.match` followed immediately by `assoc`;
- recursive `car`/`cdr` reconstruction;
- fixed AST results built with `cons()`;
- explicit `.var()` where the target is already `Var`.

These are prompts to inspect a family, not automatic rewrite rules.

### 2. Write the input grammar and descent before editing

For each function family, list the actual accepted forms as source patterns.
Trace the producer and note which facts are already guaranteed. Separately
list the semantic questions that remain inside each case.

Then draw the call sequence in grammar terms: which prefix does this function
match, what captures does that establish, and which child or remaining stream
does the next function receive? A callee should begin at the next rule, not at
the parent rule its caller already matched.

If the grammar cannot be stated, the agent does not understand the code well
enough to rewrite it. More shape checks will not repair that lack of
understanding.

### 3. Choose the most declarative complete form

For each operation, choose among:

- direct source `match` cases;
- `match_replace` input/output templates;
- flat trusted destructuring;
- `foreach` traversal with match cases for recognized nodes.

Then write the returned AST as a literal template. The intended source should
be reviewable as grammar-to-grammar mappings.

### 4. Rewrite the whole connected slice

Move the cases into their natural dispatcher, change helper signatures to
receive named captures when a helper still owns real behavior, delete
positional-only helpers, and update callers together. Do not stop after the
first successful local conversion.

Break apart monolithic parsing where one function crosses several grammar
rules, but do not replace it with a chain of functions that each receive and
revalidate the same AST. The intended call chain should visibly descend:
parent production to captured child, or consumed token prefix to the next
token production.

Preserve source order, temporary compiler state, cleanup regions, object
identity requirements, and deliberate diagnostics explicitly.

### 5. Review the authored diff before refreshing artifacts

The reviewer should search added lines for:

- `car`, `cdr`, `cadr`, `caddr`, AST indexing, and `len`;
- `is <list>`, tag checks, assertions, new diagnostics, fallbacks, and
  `try_get`;
- `List.match` plus `assoc`;
- `cons()` in returned AST construction;
- explicit `.var()` at typed targets.

Each occurrence needs a concrete reason tied to the algorithm or an untrusted
boundary. The review should also compare case coverage and order with the old
dispatch, and inspect whether side-effecting child operations still occur in
the same order.

### 6. Use focused evidence, then one final gate

Build after the connected authored edit is coherent. Inspect generated C for
capture binding, implicit conversion selection, evaluation order, and
fixed-point behavior. Run the fixtures belonging to that grammar family.

Only after the authored diff is accepted should generated symbols and
bootstrap files be refreshed and the full publication gate run once. Source
line motion and large generated diffs are expected consequences; they are not
reasons to preserve the manual source.

## Writing new compiler code

The default review question must change from "is this selector safe?" to
"what grammar production is this function recognizing or producing?"

An agent writing or changing compiler code should begin with a source pattern
whenever it sees tag-dependent positional access. The burden should be on the
manual walk to justify itself through real cursor semantics, dynamic pattern
selection, ownership, suffix sharing, or measured performance. The presence
of `cadr()` or `caddr()` near a tag check is a strong reason to stop and write
the candidate pattern before writing more procedural code.

For new code, the desired order is:

1. write the source pattern for each accepted AST form;
2. name every consumed field in that pattern;
3. consume the matched prefix and pass only the captured child, tail, or fields
   needed by the next grammatical rule;
4. make each function own one stage of the recursive descent rather than
   reparsing its caller's node or monolithically interpreting several rules;
5. keep semantic decisions inside the corresponding case;
6. write transformed output as a literal template;
7. use `foreach` for generic child traversal;
8. rely on target-typed conversions unless generated C proves an explicit
   crossing is needed.

## Performance observation

Gary's first stress test of this branch was at least 10% faster. That result
has not been isolated or reproduced as part of this document, so it is an
observation rather than a claimed benchmark result. It is nevertheless
consistent with one concrete mechanism in the rewrite: source match captures
are lowered into direct capture storage, while the replaced `List.match` plus
`assoc` paths constructed a binding association List and searched it for
values. The larger gains may also come from simpler traversal and dispatch.
Future performance work should measure those mechanisms separately without
making performance proof a prerequisite for the source improvement.
