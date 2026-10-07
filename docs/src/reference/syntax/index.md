# Syntax specifications

x2c's syntax is specified here as a token grammar plus lexical transition
rules. This first extraction describes the implementation at revision
`48715bde0d16f1a22c5a19a00e5568080a92367c` on `dev`. It introduces no language
change. The [language reference](../language.md) supplies the meaning and
constraints of the forms.

- [Source grammar](grammar.md): EBNF, precedence, contextual decisions, and
  macro extension contracts. The [EBNF file](x2c.ebnf) is the same grammar
  included in that chapter, available separately for tools.
- [Lexical specification](lexical.md): byte classes, ordered recognition,
  numeric and escape rules, nested modes, token reclassification, layout,
  and failure behavior.

The grammar describes source after tokenization and indentation rewriting.
It is not a claim that a context-free recognizer can decide whether an x2c
program is valid. Names, types, macro signatures, and preprocessor state
participate in parsing. The grammar names these dependencies explicitly.
Constructed macro ASTs also enter binding without passing through source
text; source productions do not restrict their provenance.

## Catalog of existing material

This catalog records what existed before this extraction. Paths below are
repository-relative. Function names locate the rules even when lines move.

| Material | Location | What it specifies | Limits |
| --- | --- | --- | --- |
| Language reference | `docs/src/reference/language.md` | User-facing forms, examples, semantic constraints; a small protocol grammar under Protocols | No complete grammar or lexical rule inventory |
| Syntax guides | `docs/src/guide/{from-c,indentation,macros,match,collections,symbols,protocols}.md` | Explanations and examples of individual forms | Examples do not define all accepted token sequences |
| Declaration parser | `src/parse.x` | Recursive-descent rules for units, imports, types, declarations, declarators, parameters, fields, enumerators | Mixes recognition with name binding, collection, and semantic work |
| Expression parser and precedence ledger | `src/expressions.x`, `src/operator-ledger.x` | Expression productions, ambiguity decisions, complete binary operator precedence rows | Depends on type and macro state |
| Statement parser | `src/statements.x` | Statements, blocks, match/catch arms, directive-aware governed statements | Macro-produced statements also enter binding |
| Literal and lambda parsers | `src/literals.x`, `src/lambdas.x` | Quoted data, interpolation, patterns, lambdas and captures | Token modes determine which spellings reach them |
| Macro parser and built-ins | `src/macros.x`, `etc/builtin-macros.x` | Category table, definitions, invocations, quotations, typed holes, keyword aliases; built-in `class` and `foreach` | Grammar is extended by visible definitions; libraries such as `lib/system-macros.x` add more |
| Protocol parser | `src/protocol.x` | Protocol definitions, associated types, members, adoptions | Witness resolution and type constraints are separate |
| AST source patterns | `src/grammar.x` | Executable source-shaped macro patterns and AST accessors used by lowering | Despite the filename, not a complete source grammar |
| Character scanners | `lib/scan.x` | Allocation-free byte recognizers, keywords, longest operator prefix, literal escapes, failure statuses | A scanner in isolation does not specify tokenizer dispatch or context |
| Tokenizer and layout | `lib/tokenizer.x` | Ordered scanning, mode stack, operand context, keyword reclassification, indentation rewrite, positions | Contextual and stateful, not a single token regex table |
| Preprocessor handling | `src/preprocess.x`, `src/frontend.x` | Directive handling, conditional groups, configured units and host-preprocessed imports | Host C preprocessing has its own language and target configuration |
| Compiler token preparation | `src/compiler.x` (`Compiler.tokenize`, `_retag_keywords`) | Phase ordering and contextual `in`/`match` token types | Runs after raw tokenization and conditional scanning |
| Lisp reader | `lib/lisp.x` (`LispReader`) | Lists, reader prefixes and atomic forms over Lisp-mode tokens | Evaluation and compile-time operations are not source grammar |
| Generated API pages | `docs/src/internals/compiler-api/`, notably `parse.md` and `grammar.md` | Public signatures and source doc comments | Derived API documentation, not an independent grammar |
| Architecture and ownership map | `docs/src/internals/{architecture,implementation-map}.md` | Phase order and syntax owners | Describes organization, not acceptance rules |
| Scanner/tokenizer tests | `unittest/test-scan.x`, `unittest/test-tokenizer.x` | Executable recognition, boundary, mode and layout cases | Finite observations, not a formal definition |
| Compiler fixtures | `unittest/compiler-fixtures/` | Token dumps, AST/translation outputs, diagnostics, successful and rejected programs | Expectations cover selected cases, not all derivations |
| Editor grammars | `etc/vsc-extension/syntaxes/{x2c,x2c-lisp}.tmLanguage.json` | TextMate regular expressions and highlighting contexts | Approximate; cannot decide acceptance or reproduce binding |
| Editor grammar tests | `etc/vsc-extension/test/current-grammar.test.x` | Expected highlighting scopes | Contains syntax-shaped samples that are not accepted programs; not an acceptance corpus |
| Historical designs | `plans/archive/indentation-syntax.md`, `plans/archive/macro-function-style-syntax.md` | Design rationale and earlier syntax decisions | Historical; current implementation and book take precedence |
| Bootstrap copies | `bootstrap/lib/scan.{c,h}`, `bootstrap/lib/tokenizer.{c,h}` | Generated C implementation of lexical rules | Derived copies, not independent owners |
| Executable examples | `examples/manifest.txt` and its programs | Working uses of the language with recorded checks | Demonstrations, not exhaustive syntax rules |

No standalone BNF, EBNF, PEG, yacc/lex, or tree-sitter source grammar was
found in the tracked tree at the extraction revision. The parser and
scanners were the closest executable specifications; the book was the
principal prose specification.

## Status and boundaries

The extraction has three layers:

1. Byte recognition and token transitions in the lexical specification.
2. Token productions in `x2c.ebnf` with explicit external recognizers.
3. Context and semantic constraints in the grammar chapter and language
   reference.

This is a manually reviewed descriptive specification, not a generated
parser, a proof of equivalence, or a replacement implementation. Named
external recognizers cover the deliberately extensible macro surface and
host-specific syntax. The lexical chapter identifies observed implementation
edges separately from the supported spelling described by the book.

C translation constraints, preprocessing expressions, type checking,
ownership, overload/protocol resolution, macro evaluation, AST lowering,
and emitted C are outside the source grammar. The host compiler still
checks the generated C. Resource limits and diagnostic wording are not
productions.

## Possible later uses

These are possible consumers, not work implemented by this extraction:

- Generate positive and negative source cases, with environments for typedefs,
  macro signatures, and imports rather than only random terminal strings.
- Compare token streams across scanner implementations and test each mode
  transition, numeric boundary, and indentation rewrite.
- Check documentation and editor highlighting against shared terminal and
  precedence inventories.
- Prototype a parser or code generator for a selected syntax category, then
  compare it with the existing compiler on the same corpus.
- State proof obligations for recognition, normalization, or AST round trips,
  keeping lexical, syntactic, and semantic claims separate.

There is no new recurring check or generation pipeline. Future consumers
must choose their own executable representation and demonstrate agreement
with the compiler before relying on this extraction as an oracle.
