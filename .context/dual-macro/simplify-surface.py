from pathlib import Path
import re
p=Path('plans/dual-use-syntax-templates.md')
s=p.read_text()
# Terminology edits to this plan only. Existing source identifiers and paths
# remain exact; no compiler sources or historical probe artifacts are renamed.
s=s.replace('syntax-template', 'macro-value').replace('syntax-capture', 'macro-capture')
s=s.replace('SyntaxTemplate', 'Macro')
s=re.sub(r'\bsyntax\b', 'code', s)
s=re.sub(r'\bSyntax\b', 'Code', s)
s=s.replace('spellings', 'names').replace('spelling', 'name')
s=s.replace('references spelled', 'references named').replace('also spelled', 'also named')
s=s.replace('Retain current named macro code', 'Retain current named macro syntax')
s=s.replace('surface code', 'surface syntax')
s=s.replace('same printed name', 'same name')
s=s.replace('## Proposed source code', '## Proposed syntax')
s=s.replace('code-alpha-equivalent', 'alpha-equivalent').replace('code alpha-equivalence', 'alpha-equivalence')
s=s.replace('Code alpha-equivalence', 'Alpha-equivalence')
s=s.replace('explicit template-value code', 'explicit macro-value syntax')
s=s.replace('anonymous code is included', 'anonymous macro literals are included')
s=s.replace('body and slot metadata', 'body and parameter metadata')
start=s.index('`Macro.try_match(subject, captures)`')
end=s.index('\nCompile recognition',start)
s=s[:start]+'''A macro value is called to build code and used as the callee in a Match case
to recognize code. The public forms are `sum(left, right)` and
`case sum(?left, ?right)`. The existing Match engine publishes captures only
on success. Its internal out-parameter API still distinguishes empty success
from a miss; users need no separate template matching method.

A call in meta code returns an inspectable code value. Inserting that value
into a program uses existing macro expansion and `Compiler.bind_syntax`.
Matching never inserts, expands or evaluates the candidate code. The different
stages remain part of the value contract, not separate public verbs.
''' +s[end:]
start=s.index('## Proposed syntax\n')
end=s.index('## Worked examples and counterexamples\n',start)
s=s[:start]+'''## Proposed syntax

The previous surface mixed a special getter, a contextual case introducer,
dotted methods and prefixed APIs. That proposal is withdrawn. The revised
surface has one idea: a macro can be a value, called to build code or used in a
Match case to recognize code. These forms are proposals, not current features.

```x2c
macro Expression $sum(Expr $left, Expr $right) => $left + $right;

// Proposed: referring to a macro without calling it produces a value.
Macro sum = $sum;

// Call it to build an addition from two pieces of code.
List result = sum(left, right);

// Use the same value to recognize an addition and capture its operands.
match (expression) {
  case sum(?left, ?right): consume(left, right);
}
```

In this example, `left` and `right` are code values supplied by the surrounding
meta function. `expression` holds the code being examined. If it holds
`price + tax`, the case captures price code as left and tax code as right.
It does not evaluate price or tax. If it holds `price - tax`, the case fails.
`Macro` is a proposed value type, represented by ordinary canonical Lists,
not an opaque native handle. It identifies callable macro values without
making every List callable or changing ordinary List matching.

`$sum` as a value is new behavior. The current compiler only supports the
existing named definition and invocation forms; this plan does not assume
that an unapplied reference works already. The value captures the visible
outer definition and its binding relationships. Existing named calls keep
their meaning. Within `case`, the surrounding Match context makes the call
shape a pattern instead of a construction; no extra introducer is needed.

A macro value passed to a meta function works in the same way:

```x2c
meta static List left_operand(List expression, Macro addition) {
  match (expression) {
    case addition(?left, ?right): return left;
  }
  return NULL;
}
```

`addition` is an ordinary parameter holding a macro value. The two captures
refer to that macro's two parameter slots. The compiler must check that the
case and macro interface agree. How much of a dynamically selected macro's
interface is known statically is still an implementation question; simplifying
the notation does not answer it.

Anonymous macros use the same value type and call form:

```x2c
meta static Macro make_addition(void) {
  return macro Expression(Expr $left, Expr $right) => $left + $right;
}
```

For an anonymous Expression macro, the surrounding expression delimiter ends
the body; the return above has one semicolon, not two. Named definitions keep
their existing terminator. An anonymous Statement macro keeps a braced body.
Parser probes must establish these forms without changing precedence or taking
valid existing calls. No braced Expression alternative is required by this
proposal; that independent grammar choice remains open.

Composition is written using nested macro calls in an anonymous body, rather
than a compose method:

```x2c
meta static Macro parenthesized(Macro addition) {
  return macro Expression(Expr $left, Expr $right) =>
    (addition($left, $right));
}
```

The anonymous macro captures addition as a macro value. Recognition follows
its structural body, aligns the child parameters, and preserves binding
relationships across that boundary. Arbitrary meta function calls do not
become reversible merely because they can be written inside a body.
Native helper values are captured as values; program references carried in
code retain the program's binding identities. The helper-domain bridge remains
necessary and unprototyped. A captured macro call in this example is an
explicit structural composition, rather than an unresolved name looked up
again during expansion.

Call notation determines the operation; the surrounding stage determines
when ordinary compiler binding happens. In a meta body, calling a macro value
constructs inspectable code. Returning/inserting it into a program invokes
ordinary binding and evaluates any deferred child calls when required.
Existing pending call records can be inspected as data. Users do not need
separate construct, invoke or expand methods for these stages.

The ability to call arbitrary Macro values directly in ordinary program source
with Type/Decl/Statement arguments needs more than notation: the parser must
know their grammar categories before parsing those arguments. The initial
value call prototype can accept already captured code values inside meta
functions. It must not be presented as proving fully dynamic source argument
parsing. The final interface policy remains an explicit design question.

## Surface inventory

| Form | Meaning | Status |
| --- | --- | --- |
| `macro Expression $sum(...) => ...;` | Define a named macro | Existing |
| `$sum(a, b)` | Apply the named macro | Existing |
| `$sum` | Obtain that macro as a value without applying it | Proposed |
| `Macro sum = $sum;` | Store a macro value | Proposed type name and value behavior |
| `sum(a, b)` | Call the stored macro to build code | Proposed |
| `case sum(?left, ?right):` | Use that macro to recognize code and capture its parameters | Proposed |
| `case $sum(?left, ?right):` | The same pattern using the named macro directly | Proposed |
| `macro Expression(...) => expression` | An anonymous macro value | Proposed |
| `macro Statement(...) { ... }` | An anonymous macro with a statement body | Proposed |
| `?left`, `*items` | Match captures | Existing notation reused |
| `$left`, `$items...` | Macro parameters and sequence insertion inside a body | Existing notation reused |

There is no new template keyword, getter function, method family or prefixed
public API in this revised proposal. Macro is a type name, not a tokenizer
keyword. Expression/Statement and Expr/Name/Type reuse existing categories.
Composition and passing values use calls, parameters and anonymous bodies.
No general partial application or inverse computation API is specified.

Canonical descriptor fields, capture rows, scope maps and helper environments
remain implementation details that are inspectable as ordinary data. They do
not each require another user-facing operation. Existing names such as
`Compiler.bind_syntax` are quoted exactly to locate their current owners;
this plan does not adopt their terminology for new public names.

''' +s[end:]
old='''// Proposed macro literals and compose API:
List sum = macro Expression(Expr $x, Expr $y) => $x + $y;;
List wrap = macro Expression(Expr $inside) => ($inside);;
List wrapped_sum = relay(wrap.compose(<inside>, sum, %((x left) (y right))));'''
new='''// Proposed macro values and structural composition:
meta static Macro wrapped(Macro addition) {
  return macro Expression(Expr $left, Expr $right) =>
    (addition($left, $right));
}
// wrapped($sum) returns the composed macro value.'''
assert old in s
s=s.replace(old,new)
s=s.replace('List t = x2c_template($sum);\nList pending = t.invoke(%((left A) (right B)));\n// body matching and invocation matching are explicitly different operations.', '''// pending is captured code that still contains an unexpanded $sum(A, B).
// Inspect its existing macro-invoke record with ordinary structural Match.
// A sum body pattern does not implicitly expand that record.''')
old='''meta static List add_audit(List statement) {
  List found;
  List input = x2c_template($returned);
  if (!input.try_match(statement, found)) return statement;
  List output = x2c_template($audited);
  return output.construct(found);
}'''
new='''meta static List add_audit(List statement) {
  Macro returned = $returned, audited = $audited;
  match (statement) {
    case returned(?value): return audited(value);
  }
  return statement;
}'''
assert old in s
s=s.replace(old,new)
s=s.replace('2. **Expose data-only values and construction.** Add the explicit named getter\n   in macro/meta expression parsing; snapshot visible definitions.', '2. **Expose macro values and calls.** Add an unapplied named reference\n   in macro/meta expression parsing; snapshot visible definitions. Teach meta\n   calls to apply a Macro value using its existing parameter interface.')
s=s.replace('full getter/literal scope', 'full reference/literal scope')
s=s.replace('named getter or anonymous literal', 'named reference or anonymous literal')
s=s.replace('getter/literal availability', 'macro-reference/literal availability')
s=s.replace('no macro-value getter', 'no unapplied macro reference')
s=s.replace('not the new source getter', 'not the new macro-value reference')
s=s.replace('anonymous literals or macro-derived source cases', 'anonymous macro values or macro-derived source cases')
s=s.replace('Composition renames slots and freshens child declarations', 'Captured structural macro calls rename slots and freshen child declarations')
s=s.replace('**Surface grammar:** explicit getter, anonymous terminator and dynamic case\n  names are proposals.', '**Surface grammar:** unapplied references, anonymous expression delimiters\n  and ordinary call-shaped cases are proposals. Dynamic interface/category\n  checking and argument parsing need focused prototypes.')
s=s.replace('descriptor/capture field names and slot mapping API', 'descriptor/capture field names and internal slot mapping')
s=s.replace('syntax', 'syntax')
s=s.replace('Macro definitions have positive identity and name', 'Macro definitions have positive identity and name')
s=s.replace('an anonymous literal referring to a local', 'an anonymous literal referring to a local')
p.write_text(s)
assert s.isascii()
assert not any(l.rstrip()!=l for l in s.splitlines())
