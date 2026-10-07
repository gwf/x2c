# Syntax as data

The source grammar and lexical rules are ordinary x2c `List` values. A tool
can compile them, inspect their structure, and generate another representation
without first parsing the prose specification.

Three modules under `etc/syntax/` own the data:

| Module | Accessor | Contents |
| --- | --- | --- |
| `grammar.x` | `syntax_grammar()` | Entry point and 179 source productions |
| `lexical.x` | `syntax_lexical()` | Byte patterns, ordered scanning, modes, transitions, predicates, token passes, failures |
| `extensions.x` | `syntax_extensions()` | Reviewed C11 comparison, feature groups, affected rule names, example spellings, documentation links |

For example, an ordinary x2c script can consume the grammar:

<!-- ignore: this script requires repository-root placement and local module linking -->
```x2c,ignore
#!/usr/bin/env -S x2c script
#include "etc/syntax/grammar.x"

List grammar = syntax_grammar();
printf("%s\n", grammar.repr());
```

Save this example at the repository root. `x2c script` builds and links its
included local module. An ordinary `x2c build` invocation must list the module
as a build input. The accessors construct descriptive values; the compiler's
production parser and tokenizer do not consult them yet.

## Grammar model

The root has the shape `(grammar (start NAME) (rules RULE...))`. Each rule
is `(rule NAME EXPRESSION)`. Names are atoms and terminal spellings are Strings.
The current expression algebra is deliberately small:

| Expression | Meaning |
| --- | --- |
| `(ref NAME)` | Recognize another named production |
| `(token "text")` | Recognize the token spelling in the applicable lexical context |
| `(seq EXPR...)` | Recognize every child in order |
| `(choice EXPR...)` | Recognize an alternative; this does not specify PEG priority |
| `(optional EXPR)` | Recognize zero or one occurrence |
| `(repeat 0 EXPR)` | Recognize zero or more occurrences |
| `(external "contract")` | Delegate recognition to the named lexical or contextual contract |

For example, the function-body rule contains both familiar blocks and the
expression-body addition:

```x2c
List rule = %(rule function-body
  (choice
    (ref block)
    (seq (token "=") (token ">") (ref expression) (token ";"))));
```

The [EBNF](x2c.ebnf) is generated from this value. The [grammar chapter](grammar.md)
explains binding, macro signatures, precedence, and other contextual contracts.
An external leaf is an explicit boundary, not an instruction to accept arbitrary
text. A parser generator would need implementations for those contracts.

## Lexical model

Lexing needs more than character regular expressions. A quoted List, for
example, changes the significance of punctuation and signed numbers. Braced
interpolation temporarily returns to code scanning.

The [generated inventory](lexical-data.md) exposes every record. The
[lexical specification](lexical.md) explains the operations and boundary cases.
These sections carry different parts of the operation:

| Section | Meaning |
| --- | --- |
| `input` | Byte encoding, NUL termination, token fields, positions, and trivia |
| `classes`, `rules` | Named byte recognizers and their actions |
| `modes` | Ordered rule dispatch for each scanner mode |
| `transitions` | Source mode, opener/closer bytes, emitted spelling, stack push/pop |
| `predicates` | Conditions on surrounding tokens and named token sets |
| `passes` | Frontend preparation, scanning, layout, conditional processing, keyword retagging, parsing |
| `keywords`, `operators` | Exact scanner spellings and keyword normalization |
| `failures` | Scanner result conventions, status, emitted errors, and stopping behavior |
| `boundaries` | Literal decoding, Symbol representation, host preprocessing, native C acceptance |
| `sources` | Implementation owners used for the extraction |

Byte-pattern primitives are `byte`, `bytes`, inclusive `range`, and
`one-of-bytes`. `ref` names a class or rule. `seq`, `choice`, `optional`, and
`repeat MINIMUM` compose patterns. `ordered` tries children in dispatch order;
`until` records whether a closing delimiter is consumed; `except` excludes
listed byte patterns or prefixes. Guards such as `when-prefix` and `when-mode` select the applicable
pattern. They are structured records, not regular-expression strings.

Actions record `emit`, consumed width, failure behavior, and `transition`.
A transition's `push` stores a new mode; `pop` restores the previous stack mode.
The transition table's `defaults` record applies unless a row overrides it.
Predicates record Boolean conditions and token-history operations. Passes
record ordered transformations and the state they use. `external` explicitly
names work owned elsewhere.

This is a descriptive operational model. The tool validates named references
and renders records; it does not interpret every lexical operation. Building
an executable scanner from these records requires giving each operation an
implementation and comparing its token streams with the existing tokenizer.

## Existing consumers

Run these commands from the repository root with a built compiler:

```sh
builds/0/x2c script tools/syntax-spec summary
builds/0/x2c script tools/syntax-spec dump grammar
builds/0/x2c script tools/syntax-spec uses expression
builds/0/x2c script tools/syntax-spec graph quoted-list
builds/0/x2c script tools/syntax-spec modes
builds/0/x2c script tools/syntax-spec write
builds/0/x2c script tools/syntax-spec check
```

`dump` also accepts `lexical` and `extensions`. It prints the runtime List
representation for inspection. `uses` finds direct callers of a production.
`graph` emits a Mermaid production-dependency graph. `modes` emits a Mermaid
graph of stack-push transitions; ordered dispatch and predicates still apply,
and closing delimiters return to the previous stack mode. These graphs show
dependencies and transitions, not complete railroad diagrams or acceptance
proofs.

`write` generates the EBNF, lexical inventory, and the table in the
[x2c syntax map](../../guide/x2c-syntax-map.md). `check` validates references and
reports stale generated outputs without changing them. These are optional
commands; no recurring build or publication check was added.

The extension data identifies affected productions and the additions within
them. Its grouping is reviewed metadata. It does not claim that subtracting
production names computes the difference between C and x2c.

## Further uses and limits

These values make several bounded next steps possible:

- Generate railroad diagrams for productions with no external leaves.
- Produce candidate token sequences from bounded derivations, then filter them
  through the real compiler and retain accepted and rejected cases.
- Compare scanner outputs against an interpreter of the lexical records.
- Generate highlighting tables from keyword and operator spellings.
- Select documentation examples and diagrams by extension family.

The data is manually extracted from the implementation. Reference checks and
generated-output checks prevent some forms of drift; they do not establish
language equivalence. Type validity, macro expansion, binding, native C rules,
and deliberately opaque recognition contracts remain outside a context-free
production tree. Corpus comparison and differential tests would provide
additional evidence before any generated recognizer replaces existing code.
