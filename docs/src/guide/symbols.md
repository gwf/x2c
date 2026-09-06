# Symbols and Atoms

C gives you two ways to spell a name in data: an `enum` constant, which is
fast to compare but has no text; and a `char *`, which has text but costs a
`strcmp` every time you ask whether two names match. x2c adds two types that
give you both halves at once.

- A `Symbol` is a **short** name packed directly into a 64-bit integer.
- An `Atom` is an **exact** name of any length, canonicalized so that equal
  spellings are the same value.

Both compare names with a single machine comparison. They differ in which
spellings they preserve.

The literal and representation rules are in
[the language reference](../reference/language.md), and the runtime rules
are in [the standard library overview](../library/overview.md).

## A Symbol is a name packed into an integer

`Symbol` is a typedef for `unsigned long`. Its literal syntax is angle
brackets: `<name>` for a bare spelling, and `<"punctuated name">` when the
spelling contains characters that would otherwise end the token. The
characters are encoded in the value itself. There is no allocation, table,
or pointer.

```x2c
Symbol state = <ready>;
Symbol also_ready = <ready>;
Symbol arrow = <"->">;

printf("equal: %d\n", state == also_ready);
printf("%s has %d characters\n", state.str(), state.len());
printf("repr: %s\n", arrow.repr());
```

The whole name is encoded in the integer, so a symbol literal is a compile-time
constant. A `Symbol` works as a `case` label, and a closed set of names
dispatches through a C `switch`.

```x2c
static Symbol check_port(int port) {
  if (port < 0) return <negative>;
  if (port > 65535) return <too-big>;
  return <ok>;
}

static const char *explain(Symbol outcome) {
  switch (outcome) {
    case <ok>:       return "usable";
    case <negative>: return "below the valid range";
    case <too-big>:  return "above the valid range";
  }
  return "unrecognized outcome";
}
```

Zero is the empty symbol. Construction returns it for empty or missing
input, it is falsy in a condition, and its representation is `<>`.

## What interning solves, and how a Symbol avoids it

Interning is the classic fix for name comparison: push every spelling
through one table so that a given spelling always yields the same object,
then compare objects instead of bytes. You get cheap identity comparison and
a name that stays valid as long as the table does.

A `Symbol` gets there another way. It is **not** interned and never enters a
table. It is *encoded*, and the characters are the value. Two `<ready>`
literals are equal for the same reason two `42`s are equal, and comparing
them is one integer compare.

The limit is capacity: an integer holds only so many characters. The payload
selects between two encodings.

- A restricted 5-bit alphabet holds up to **ten** characters. It covers the
  letters, `*`, `+`, `?`, `!`, and a separator. Uppercase folds to lowercase,
  and `-` and `_` are the same separator.
- The general 7-bit encoding holds up to **seven** ASCII characters and
  preserves each byte.

A source literal must reproduce its spelling when decoded. The compiler
rejects case folding, separator folding, and truncation. `Symbol.new`
accepts runtime text and applies those normalizations:

```x2c
printf("%d\n", Symbol.new("Alpha") == <alpha>);          /* 1 */
printf("%d\n", Symbol.new("read_only") == <read-only>);  /* 1 */
printf("%s\n", Symbol.new("verylongidentifier").str());  /* verylongid */
printf("%d\n", <"Token@!">.len());                       /* 7 */
```

Two runtime names can normalize to the same value, so use `Atom.intern`
when the exact dynamic spelling matters. Keep a closed set of `Symbol`s short
and spell its decoded names in source.

The encoded integers are not in alphabetical order. Use `Symbol.compare`,
which compares the decoded text:

```x2c
printf("raw integers say b < abc: %d\n", <b> < <abc>);
printf("Symbol.compare says b > abc: %d\n", <b>.compare(<abc>) > 0);
```

`Symbol.str` returns the canonical `String` for the decoded text, so
calling it twice gives you the same pointer. Call it, or `Symbol.repr`, when
you need the text. The symbol is already the identity.

## An Atom is an exact name

Use an `Atom` when the spelling must survive intact. `Atom` is a `Var`, and
`Atom.intern` turns a spelling into one. Interning one spelling twice
produces identical `Var` bits, so equality is a bit comparison, and nothing
was folded, truncated, or case-mapped on the way in.

```x2c
Atom exact = Atom.intern("VeryLongIdentifierName");
Atom again = Atom.intern(String.new("VeryLongIdentifierName"));
Atom lower = Atom.intern("verylongidentifiername");

printf("%s\n", exact.str());        /* VeryLongIdentifierName */
printf("same value: %d\n", exact == again);
printf("case matters: %d\n", exact == lower);
```

The source literal `<VeryLongIdentifierName>` is rejected because its
encoded value would decode as `verylongid`.
`Symbol.new("VeryLongIdentifierName")` is the lossy runtime operation, and
it does return `verylongid`. Side by side:

| | `Symbol` | `Atom` |
| --- | --- | --- |
| written as | `<name>`, `<"name">` | `Atom.intern(text)`, bare `%()` element |
| spelling | exact in source | exact |
| length limit | 10 or 7 characters | none |
| storage | none; encoded in the value | the canonical `String`, when needed |
| constant? | yes, usable as a `case` label | no; interned at run time |

`Atom.intern` requires a non-empty spelling. A null or empty spelling is a
programming error and terminates the process.

### Two representations, one identity

An `Atom` is not a wrapper object. `Atom.intern` picks one of two
representations:

- if `Symbol` encoding round-trips every byte of the spelling, the atom *is*
  that compact immediate symbol;
- otherwise the atom is a private `<lsym>` value pointing straight at the
  canonical `String`.

`Atom.intern("alpha")` is an immediate with no storage, while
`Atom.intern("Mixed_Case_Identifier")` points at a canonical `String`. You
can see which one you have: `value.is_atom()` accepts both, and
`value is Symbol` tells them apart. Most code does not need to. Because
canonicalization happens once, in one place, `Atom.str` returns the exact
bytes without copying and `Atom.hash` is the `String`'s cached hash.

## Identity and equality

Equality and identity agree for both types, but for different reasons.

**`Symbol`.** It is an integer, so `==` is the right operator and means "the
same encoded value". That is a claim about the *encoding*, not about your
source spelling: `Symbol.new("Alpha") == <alpha>`.

**`Atom`.** `Atom`s are `Var`, so `==` uses value equality and `===` uses
identity. For atoms the two agree, and that agreement is what interning
gives you:

```x2c
~Atom left = Atom.intern("VeryLongIdentifierName");
~Atom right = Atom.intern("VeryLongIdentifierName");
printf("equal:    %d\n", left == right);
printf("identical: %d\n", left === right);
printf("raw bits:  %d\n", left.u64 == right.u64);
```

All three print `1`. Structural equality and bit identity coincide for
atoms, so an equality test costs one comparison even for a long name.

Two cautions:

- Equality is exact-spelling equality. `Atom`s differing only in case are
  different atoms.
- Ordering is narrower than equality. `compare` orders two long atoms by
  their spellings and two compact atoms by their decoded text, but ordering
  *across* the two representations does not follow the spelling. For a text
  order over a mixed set, compare `Atom.str` values.

## Where each one belongs

The question is who chose the names.

**Use a `Symbol` for a closed set of names that you wrote.** Outcome and
lifecycle values are the common case. `Lisp.read` reports `<value>`,
`<eof>`, `<incomplete>`, or `<malformed>`, and `Error` causes include
`<bad-sig>`, `<no-symbol>`, `<bad-arity>`, `<bad-types>`, and
`<bad-result>`. Each one describes itself in a debugger, where an `enum`
constant prints as `3`. The compiler does the same thing internally: AST
node heads and the match operator and predicate names are compact symbols,
because the compiler chose them.

`Symbol`s also make good map keys for fixed configuration:

```x2c
Map config = %{host: "localhost", port: 8080};
printf("%s:%d\n", config.get(<host>).string(), config.get(<port>).int());
```

Keep numeric enums where the number is the point: indexes, packed fields,
arithmetic, and external encodings.

**Use an `Atom` for names that come from outside your code.** Identifiers
read from source text, keys in serialized data, user-supplied tags, anything
where truncating to ten characters or folding case would corrupt the data.
Bare elements of a `%()` [list literal](collections.md) are atoms for that
reason. Do not add brackets to request a compact value. A bare `Atom` is
already the compact `Symbol` when its spelling fits. Brackets inside a `%()`
`List` literal quote text that would otherwise be another kind of element:

```x2c
List names = %(alpha Mixed_Case_Identifier 1 <1>);

printf("%s\n", names.getindex(1));   /* Mixed_Case_Identifier */
printf("alpha is compact: %d\n", names.getindex(0) is <symbol>);
printf("number then Symbol: %d %d\n",
       names.getindex(2) is <i32>, names.getindex(3) is <symbol>);
```

`alpha` is short and lowercase, so its exact spelling round-trips through the
compact encoding and the `Atom` is that `Symbol`. The mixed-case name cannot
round-trip, so it keeps its canonical `String`. The brackets on `<1>` quote a
`Symbol` spelling that bare `1` would parse as an integer. `<"">` is the empty
`Symbol` and has no bare `Atom` spelling. [Pattern matching](match.md) splits
the same way. `Match` operators are compact symbols, and named binder keys
such as `?name` are canonical atoms, so long and case-sensitive binder names
work.

`Atom` representation escapes delimiters, comment openers, numeric-looking
prefixes, whitespace, control bytes, and backslashes, so a printed atom reads
back as the same value through `%()` and through the Lisp reader.

## Speed and capacity

`Symbol`:

- construction from a literal is free; it is a compile-time constant;
- comparison is one integer comparison;
- there is no allocation, table, or lifetime to manage;
- the limit is capacity: ten restricted or seven general characters. A source
  literal that would truncate, fold case, or fold separators is rejected,
  since it would not reproduce its spelling;
- runtime `Symbol.new` is lossy. It truncates past the selected encoding's
  capacity and folds case and separators in the 5-bit form;
- `Symbol.str` and `Symbol.repr` are the expensive operations, because they
  decode and then canonicalize a `String`.

`Atom`:

- `Atom.intern` is not free. It canonicalizes the spelling through the
  `String` canonicalizer, a hash plus a pool lookup, and an allocation the
  first time a spelling is seen, and then tries the compact encoding. Intern
  once and pass the atom around; do not re-intern in a loop;
- after that, equality, identity, and hashing are cheap: a bit comparison,
  and the `String`'s cached hash;
- the atom value needs no storage. A compact atom is an immediate, and a
  long atom points at the canonical `String` that interning already
  produced. There is no wrapper object and no second intern table;
- long atoms live as long as their canonical `String`, as described below.

Neither type replaces `String`. Text you slice or concatenate, such as a
message or a file's contents, belongs in a `String`. Use a name type when the
main task is recognizing and comparing names.

## Lifetime of long atoms

A compact atom is an immediate value and has no lifetime. A long atom holds
the canonical `String` and follows that `String`'s pool lifetime. If you
intern inside a child string pool and the atom must outlive it, promote the
spelling first:

```x2c
String.pool_retain_named("scratch-names");
Atom row = Atom.intern(String.printf("row-%d", 314159));
String.promote(row.str());
String.pool_release();

printf("%s\n", row.str());
```

`List.promote` promotes the long atoms inside a list, so a promoted list
keeps every identity it contains. The promotion above is for a standalone
atom. See [Scopes and Lifetime](memory.md) for the lifetime rules.

## Where to look next

- [The language reference](../reference/language.md) has the literal
  and representation rules. [The standard library
  overview](../library/overview.md) has the identity and equality rules
  for the other types.
