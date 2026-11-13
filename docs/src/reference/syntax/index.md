# Syntax Specifications

x2c's syntax is specified here as a token grammar plus lexical transition
rules that describe the parser. The specification data in `etc/syntax/` is
written by hand, so it may lag behind the parser; the compiler is
authoritative. The [language reference](../language.md) supplies the
meaning and constraints of the forms.

- [Source grammar](grammar.md): EBNF, precedence, contextual decisions, and
  macro extension contracts. The [EBNF file](x2c.ebnf) is the same grammar
  included in that chapter, generated from `etc/syntax/grammar.x`.
- [Lexical specification](lexical.md): byte classes, ordered recognition,
  numeric and escape rules, nested modes, token reclassification, layout,
  and failure behavior.
- [x2c syntax map](../../guide/x2c-syntax-map.md): the additions beyond C11,
  grouped for onboarding and linked to the specification data.

The grammar describes source after tokenization and indentation rewriting.
It is not a claim that a context-free recognizer can decide whether an x2c
program is valid. Names, types, macro signatures, and preprocessor state
participate in parsing. The grammar marks these dependencies as external
recognizers.

The [AST grammar](../../internals/ast-grammar.md) separately documents the
canonical List forms, their fields, and their compiler stages.

[Syntax as data](data.md), under Compiler internals, describes the data
behind these pages and the other sources of syntax rules in the repository.
