# Symbols and Atoms

In C, a name in data is an `enum` constant or a `char *`. An `enum`
constant compares quickly and has no text. A `char *` has text, and each
comparison costs a `strcmp`. x2c adds two name types that have text and
compare with one machine comparison:

- A `Symbol` is a short name packed into a 64-bit integer.
- An `Atom` is an exact name of any length. Equal spellings produce the
  same value.

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

## How a Symbol is encoded

A `Symbol` stores its characters in the integer. Two `<ready>` literals are
equal for the same reason two `42`s are equal, and comparing them is one
integer comparison. An integer holds a limited number of characters, so the
spelling selects one of two encodings:

- A restricted 5-bit alphabet holds up to ten characters. It covers the
  letters, `*`, `+`, `?`, `!`, and a separator. Uppercase folds to lowercase,
  and `-` and `_` are the same separator.
- The general 7-bit encoding holds up to seven ASCII characters and
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

`Symbol.str` decodes the value and returns the canonical `String`, so two
calls return the same pointer. Call `Symbol.str` or `Symbol.repr` only
when you need the text.

## An Atom is an exact name

Use an `Atom` when the spelling must survive intact. `Atom` is a `Var`, and
`Atom.intern` turns a spelling into one. Interning one spelling twice
produces identical `Var` bits, so equality is a bit comparison. Interning
keeps the spelling exactly: it does not fold case or separators, and it does
not truncate.

```x2c
Atom exact = Atom.intern("VeryLongIdentifierName");
Atom again = Atom.intern(String.new("VeryLongIdentifierName"));
Atom lower = Atom.intern("verylongidentifiername");

printf("%s\n", exact);              /* VeryLongIdentifierName */
printf("same value: %d\n", exact == again);
printf("case matters: %d\n", exact == lower);
```

The source literal `<VeryLongIdentifierName>` is rejected because its
encoded value would decode as `verylongid`.
`Symbol.new("VeryLongIdentifierName")` is the lossy runtime operation, and
it returns `verylongid`.

| | `Symbol` | `Atom` |
| --- | --- | --- |
| written as | `<name>`, `<"name">` | `Atom.intern(text)`, bare `%()` element |
| spelling | exact in source | exact |
| length limit | 10 or 7 characters | none |
| storage | none; encoded in the value | the canonical `String`, when needed |
| constant? | yes, usable as a `case` label | no; interned at run time |

`Atom.intern` requires a non-empty spelling. A null or empty spelling is a
programming error and terminates the process.

### How an Atom is stored

`Atom.intern` stores an atom in one of two forms:

- If `Symbol` encoding reproduces every byte of the spelling, the atom is
  that compact immediate symbol and needs no storage.
- Otherwise the atom is a private `<lsym>` value that points to the
  canonical `String`.

`Atom.intern("alpha")` is an immediate with no storage, while
`Atom.intern("Mixed_Case_Identifier")` points at a canonical `String`. Most
code does not need to know which form it has. When it does,
`value.is_atom()` is true for both, and `value is Symbol` is true only for
the compact form. `Atom.str` returns the exact bytes without copying. For a
`String`-backed atom, hashing uses the `String`'s cached hash.

## Identity and equality

For both types, equal values are identical.

A `Symbol` is an integer, so `==` compares encoded values. Two different
runtime spellings can have one encoding, so `Symbol.new("Alpha") == <alpha>`
is true.

An `Atom` is a `Var`, so `==` compares values and `===` compares identity.
Interning makes the two agree:

```x2c
~Atom left = Atom.intern("VeryLongIdentifierName");
~Atom right = Atom.intern("VeryLongIdentifierName");
printf("equal:    %d\n", left == right);
printf("identical: %d\n", left === right);
printf("raw bits:  %d\n", left.u64 == right.u64);
```

All three print `1`. An equality test is one comparison, even for a long
name.

Two cautions:

- Equality is exact-spelling equality. `Atom`s differing only in case are
  different atoms.
- `compare` orders two long atoms by their spellings and two compact atoms
  by their decoded text. Between a long atom and a compact atom, the order
  does not follow the spelling. For a text
  order over a mixed set, compare `Atom.str` values.

## Where each one belongs

Choose the type by who wrote the names.

Use a `Symbol` for a closed set of names that you wrote, such as outcome and
lifecycle values. `Lisp.read` reports `<value>`,
`<eof>`, `<incomplete>`, or `<malformed>`, and `Error` causes include
`<bad-sig>`, `<no-symbol>`, `<bad-arity>`, `<bad-types>`, and
`<bad-result>`. A debugger shows each one by name, where an `enum` constant
prints as `3`. The compiler uses symbols the same way: AST node heads and
the match operator and predicate names are compact symbols, because the
compiler chose them.

`Symbol`s also make good map keys for fixed configuration:

```x2c
Map config = {host: "localhost", port: 8080};
printf("%s:%d\n", config[<host>].string(), config[<port>].int());
```

Keep numeric enums where the numeric value matters: indexes, packed fields,
arithmetic, and external encodings.

Use an `Atom` for names that come from outside your code: identifiers
read from source text, keys in serialized data, user-supplied tags, anything
where truncating to ten characters or folding case would corrupt the data.
Bare elements of a `%()` [list literal](collections.md) are atoms for that
reason. A bare element is already the compact `Symbol` when its spelling
fits. Brackets inside a `%()` `List` literal only quote text that would
otherwise parse as another kind of element:

```x2c
List names = %(alpha Mixed_Case_Identifier 1 <1>);

printf("%s\n", names.getindex(1));   /* Mixed_Case_Identifier */
printf("alpha is compact: %d\n", names.getindex(0) is <symbol>);
printf("number then Symbol: %d %d\n",
       names.getindex(2) is <i32>, names.getindex(3) is <symbol>);
```

`alpha` is short and lowercase, so the compact encoding reproduces it and
the `Atom` is that `Symbol`. The compact encoding cannot reproduce the
mixed-case name, so that `Atom` points to its canonical `String`. The
brackets on `<1>` quote a `Symbol` spelling that bare `1` would parse as an
integer. `<"">` is the empty `Symbol` and has no bare `Atom` spelling.
[Pattern matching](match.md) uses both types. `Match` operators are compact
symbols, and named binder keys such as `?name` are canonical atoms, so long
and case-sensitive binder names work.

`Atom` representation escapes delimiters, comment openers, numeric-looking
prefixes, whitespace, control bytes, and backslashes, so a printed atom reads
back as the same value through `%()` and through the Lisp reader.

## Cost

A `Symbol` literal is a compile-time constant. A `Symbol` needs no
allocation, table, or lifetime management. `Symbol.str` and `Symbol.repr`
are its only costly operations.

`Atom.intern` canonicalizes the spelling through the `String` pool: a hash,
a pool lookup, and an allocation the first time the spelling is seen. It
then tries the compact encoding. Intern a name once and pass the atom
around. After interning, equality and identity are one bit comparison.
Hashing a `String`-backed atom reads the `String`'s cached hash. Interning
uses the `String` pool and has no separate atom table.

Use a `String` for text you slice or concatenate, such as a message or a
file's contents. Use a name type when the main task is recognizing and
comparing names.

## Lifetime of long atoms

A compact atom is an immediate value and has no lifetime. A long atom holds
the canonical `String` and follows that `String`'s pool lifetime. If you
intern inside a child pool and the atom must outlive it, call `Atom.promote`
before the pool closes:

```x2c
Pool.open_named("scratch-names");
Atom row = Atom.intern(String.printf("row-%d", 314159));
Atom.promote(row);
Pool.close();

printf("%s\n", row);
```

`List.promote` promotes the long atoms inside a list, so a promoted list
keeps every identity it contains. `Atom.promote` is for a standalone atom.
See [Scopes and Lifetime](memory.md) for the lifetime rules.

## Where to look next

- [The language reference](../reference/language.md) has the literal
  and representation rules.
- [The standard library overview](../library/overview.md) has the runtime
  rules, including identity and equality for the other types.
