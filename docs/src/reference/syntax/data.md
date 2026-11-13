# Syntax as Data

The source grammar and lexical rules are ordinary x2c `List` values. A tool
can compile them, inspect their structure, and generate another representation
without first parsing the prose specification.

Three modules under `etc/syntax/` hold the data:

| Module | Accessor | Contents |
| --- | --- | --- |
| `grammar.x` | `syntax_grammar()` | Entry point and productions |
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
production parser and tokenizer do not consult them.

## Grammar model

The root has the shape `(grammar (start NAME) (rules RULE...))`. Each rule
is `(rule NAME EXPRESSION)`. Names are atoms and terminal spellings are Strings.
Rule expressions use these forms:

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

The [EBNF](x2c.ebnf) is generated from this value. The [grammar
chapter](grammar.md) explains binding, macro signatures, precedence, and other
contextual contracts. An external leaf marks a rule that the grammar chapter
describes in prose. A parser generator would need code for each one.

## Lexical model

Character regular expressions cannot describe the lexer. A quoted List, for
example, changes the significance of punctuation and signed numbers. An
interpolation such as `$(expr)` temporarily returns to code scanning.

The [generated inventory](lexical-data.md) exposes every record. The
[lexical specification](lexical.md) explains the operations and boundary cases.
The sections are:

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
`one-of-bytes`. `ref` refers to a class or rule. `seq`, `choice`, `optional`,
and `repeat MINIMUM` compose patterns. `ordered` tries children in dispatch
order; `until` records whether a closing delimiter is consumed; `except`
excludes listed byte patterns or prefixes. Guards such as `when-prefix` and
`when-mode` select the applicable pattern. They are structured records.

Actions record `emit`, consumed width, failure behavior, and `transition`. A
transition's `push` stores a new mode; `pop` restores the previous stack mode.
The transition table's `defaults` record applies unless a row overrides it.
Predicates record Boolean conditions and token-history operations. Passes
record ordered transformations and the state they use. `external` marks work
done by other code.

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
and closing delimiters return to the previous stack mode.

`write` generates the EBNF, lexical inventory, and the table in the
[x2c syntax map](../../guide/x2c-syntax-map.md). `check` validates references and
reports stale generated outputs without changing them.

The extension data lists the productions that x2c adds to or changes from C.

## Further uses and limits

These values could support:

- Generate railroad diagrams for productions with no external leaves.
- Produce candidate token sequences from bounded derivations, then filter them
  through the real compiler and retain accepted and rejected cases.
- Compare scanner outputs against an interpreter of the lexical records.
- Generate highlighting tables from keyword and operator spellings.
- Select documentation examples and diagrams by extension family.

## Sources and status

### Existing sources of syntax rules

This catalog lists the existing sources of syntax rules. Paths below are
repository-relative. The table gives function names because line numbers
change.

| Material | Location | What it specifies | Limits |
| --- | --- | --- | --- |
| Language reference | `docs/src/reference/language.md` | User-facing forms, examples, semantic constraints; a small protocol grammar under Protocols | No complete grammar or lexical rule inventory |
| Syntax guides | `docs/src/guide/{from-c,indentation,macros,match,collections,symbols,protocols}.md` | Explanations and examples of individual forms | Examples do not define all accepted token sequences |
| Declaration parser | `src/parse/parse.x` | Recursive-descent rules for units, imports, types, declarations, declarators, parameters, fields, enumerators | Mixes recognition with name binding, collection, and semantic work |
| Expression parser and precedence ledger | `src/expressions/expressions.x`, `src/operator-ledger.x`, `lib/compiler-meta.x` | Expression productions, ambiguity decisions, precedence lookups, and shared binary operator rows | Depends on type and macro state |
| Statement parser | `src/statements.x` | Statements, blocks, match/catch arms, directive-aware governed statements | Macro-produced statements also enter binding |
| Literal and lambda parsers | `src/literals/literals.x`, `src/lambdas.x` | Quoted data, interpolation, patterns, lambdas and captures | Token modes determine which spellings reach them |
| Macro parser and built-ins | `src/macros/macros.x`, `etc/compiler-prelude.x` | Category table, definitions, invocations, quotations, typed holes, keyword aliases; built-in `class` and `foreach` | Grammar is extended by visible definitions; libraries such as `lib/system-macros.x` add more |
| Protocol parser | `src/protocol/protocol.x` | Protocol definitions, associated types, members, adoptions | Witness resolution and type constraints are separate |
| AST source patterns | `src/grammar.x` | Executable source-shaped macro patterns and AST accessors used by lowering | Despite the filename, not a complete source grammar |
| Character scanners | `lib/scan.x` | Allocation-free byte recognizers, keywords, longest operator prefix, literal escapes, failure statuses | A scanner in isolation does not specify tokenizer dispatch or context |
| Tokenizer and layout | `lib/tokenizer.x` | Ordered scanning, mode stack, operand context, keyword reclassification, indentation rewrite, positions | Contextual and stateful, not a single token regex table |
| Preprocessor handling | `src/preprocess.x`, `src/frontend.x` | Directive handling, conditional groups, configured units and host-preprocessed imports | Host C preprocessing has its own language and target configuration |
| Compiler token preparation | `src/compiler/parsing/tokens.x` (`Compiler.tokenize`, `_retag_keywords`) | Phase ordering and contextual `in`/`match` token types | Runs after raw tokenization and conditional scanning |
| Lisp reader | `lib/datum-reader.x` (`LispReader`) | Lists, reader prefixes and atomic forms over Lisp-mode tokens | Evaluation and compile-time operations are not source grammar |
| Generated API pages | `docs/src/internals/compiler-api/`, notably `parse.md` and `grammar.md` | Public signatures and source doc comments | Derived API documentation, not an independent grammar |
| Architecture and ownership map | `docs/src/internals/{architecture,implementation-map}.md` | Phase order and syntax owners | Describes organization, not acceptance rules |
| Scanner/tokenizer tests | `unittest/test-scan.x`, `unittest/test-tokenizer.x` | Executable recognition, boundary, mode and layout cases | Finite observations, not a formal definition |
| Compiler fixtures | `unittest/compiler-fixtures/` | Token dumps, AST/translation outputs, diagnostics, successful and rejected programs | Expectations cover selected cases, not all derivations |
| Editor grammars | `etc/vsc-extension/syntaxes/{x2c,x2c-lisp}.tmLanguage.json` | TextMate regular expressions and highlighting contexts | Approximate; cannot decide acceptance or reproduce binding |
| Editor grammar tests | `etc/vsc-extension/test/current-grammar.test.x` | Expected highlighting scopes | Contains syntax-shaped samples that are not accepted programs; not an acceptance corpus |
| Bootstrap copies | `bootstrap/lib/scan.{c,h}`, `bootstrap/lib/tokenizer.{c,h}` | Generated C implementation of lexical rules | Derived copies, not independent owners |
| Executable examples | `examples/manifest.txt` and its programs | Working uses of the language with recorded checks | Demonstrations, not exhaustive syntax rules |

### Status and boundaries

The specification has three layers:

1. Byte recognition and token transitions in the lexical specification.
2. Token productions in `etc/syntax/grammar.x`, rendered as `x2c.ebnf`,
   with explicit external recognizers.
3. Context and semantic constraints in the grammar chapter and language
   reference.

This specification is written and reviewed by hand. No parser is generated
from it, and nothing proves it equal to the compiler. Named external
recognizers cover the macro syntax, which definitions extend, and
host-specific syntax. The lexical chapter identifies observed implementation
edges separately from the supported spelling described by the book.

C translation constraints, preprocessing expressions, type checking,
ownership, overload/protocol resolution, macro evaluation, AST lowering,
and emitted C are outside the source grammar. The host compiler still
checks the generated C. Resource limits and diagnostic wording are not
productions.
