# Syntax specifications

x2c's syntax is specified here as a token grammar plus lexical transition
rules that describe the current parser. The first extraction matched revision
`48715bde` on `dev`. Parser changes update these pages and `etc/syntax/` by
hand. `tools/syntax-spec check` verifies grammar references and reports
generated files that differ from their data. It does not compare the data
with the parser, and no gate runs it. The
[language reference](../language.md) supplies the meaning and constraints of
the forms.

- [Source grammar](grammar.md): EBNF, precedence, contextual decisions, and
  macro extension contracts. The [EBNF file](x2c.ebnf) is the same grammar
  included in that chapter, generated from `etc/syntax/grammar.x`.
- [Lexical specification](lexical.md): byte classes, ordered recognition,
  numeric and escape rules, nested modes, token reclassification, layout,
  and failure behavior.
- [Syntax as data](data.md): ordinary x2c Lists, their algebra, and a tool for
  generation, reference checks, dependency graphs, and lexical mode graphs.
- [x2c syntax map](../../guide/x2c-syntax-map.md): the additions beyond C11,
  grouped for onboarding and linked to the specification data.

The grammar describes source after tokenization and indentation rewriting.
It is not a claim that a context-free recognizer can decide whether an x2c
program is valid. Names, types, macro signatures, and preprocessor state
participate in parsing. The grammar marks these dependencies as external
recognizers.

## Catalog of existing material

This catalog lists the existing sources of syntax rules. Paths below are
repository-relative. The table gives function names because line numbers
change.

| Material | Location | What it specifies | Limits |
| --- | --- | --- | --- |
| Language reference | `docs/src/reference/language.md` | User-facing forms, examples, semantic constraints; a small protocol grammar under Protocols | No complete grammar or lexical rule inventory |
| Syntax guides | `docs/src/guide/{from-c,indentation,macros,match,collections,symbols,protocols}.md` | Explanations and examples of individual forms | Examples do not define all accepted token sequences |
| Declaration parser | `src/parse/parse.x` | Recursive-descent rules for units, imports, types, declarations, declarators, parameters, fields, enumerators | Mixes recognition with name binding, collection, and semantic work |
| Expression parser and precedence ledger | `src/expressions/expressions.x`, `src/operator-ledger.x` | Expression productions, ambiguity decisions, complete binary operator precedence rows | Depends on type and macro state |
| Statement parser | `src/statements.x` | Statements, blocks, match/catch arms, directive-aware governed statements | Macro-produced statements also enter binding |
| Literal and lambda parsers | `src/literals/literals.x`, `src/lambdas.x` | Quoted data, interpolation, patterns, lambdas and captures | Token modes determine which spellings reach them |
| Macro parser and built-ins | `src/macros/macros.x`, `etc/compiler-prelude.x` | Category table, definitions, invocations, quotations, typed holes, keyword aliases; built-in `class` and `foreach` | Grammar is extended by visible definitions; libraries such as `lib/system-macros.x` add more |
| Protocol parser | `src/protocol/protocol.x` | Protocol definitions, associated types, members, adoptions | Witness resolution and type constraints are separate |
| AST source patterns | `src/grammar.x` | Executable source-shaped macro patterns and AST accessors used by lowering | Despite the filename, not a complete source grammar |
| Character scanners | `lib/scan.x` | Allocation-free byte recognizers, keywords, longest operator prefix, literal escapes, failure statuses | A scanner in isolation does not specify tokenizer dispatch or context |
| Tokenizer and layout | `lib/tokenizer.x` | Ordered scanning, mode stack, operand context, keyword reclassification, indentation rewrite, positions | Contextual and stateful, not a single token regex table |
| Preprocessor handling | `src/preprocess.x`, `src/frontend.x` | Directive handling, conditional groups, configured units and host-preprocessed imports | Host C preprocessing has its own language and target configuration |
| Compiler token preparation | `src/compiler/parsing/tokens.x` (`Compiler.tokenize`, `_retag_keywords`) | Phase ordering and contextual `in`/`match` token types | Runs after raw tokenization and conditional scanning |
| Lisp reader | `lib/lisp/lisp.x` (`LispReader`) | Lists, reader prefixes and atomic forms over Lisp-mode tokens | Evaluation and compile-time operations are not source grammar |
| Generated API pages | `docs/src/internals/compiler-api/`, notably `parse.md` and `grammar.md` | Public signatures and source doc comments | Derived API documentation, not an independent grammar |
| Architecture and ownership map | `docs/src/internals/{architecture,implementation-map}.md` | Phase order and syntax owners | Describes organization, not acceptance rules |
| Scanner/tokenizer tests | `unittest/test-scan.x`, `unittest/test-tokenizer.x` | Executable recognition, boundary, mode and layout cases | Finite observations, not a formal definition |
| Compiler fixtures | `unittest/compiler-fixtures/` | Token dumps, AST/translation outputs, diagnostics, successful and rejected programs | Expectations cover selected cases, not all derivations |
| Editor grammars | `etc/vsc-extension/syntaxes/{x2c,x2c-lisp}.tmLanguage.json` | TextMate regular expressions and highlighting contexts | Approximate; cannot decide acceptance or reproduce binding |
| Editor grammar tests | `etc/vsc-extension/test/current-grammar.test.x` | Expected highlighting scopes | Contains syntax-shaped samples that are not accepted programs; not an acceptance corpus |
| Bootstrap copies | `bootstrap/lib/scan.{c,h}`, `bootstrap/lib/tokenizer.{c,h}` | Generated C implementation of lexical rules | Derived copies, not independent owners |
| Executable examples | `examples/manifest.txt` and its programs | Working uses of the language with recorded checks | Demonstrations, not exhaustive syntax rules |

## Status and boundaries

The extraction has three layers:

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
