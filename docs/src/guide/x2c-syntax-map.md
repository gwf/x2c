# What x2c adds to C syntax

For a C reader, x2c adds eleven useful syntax families. Most declarations,
expressions, and control flow keep their familiar shapes. Start with the
families needed by your program; macros and compile-time code can wait.

This map groups additions from the [source grammar and lexical
specification](../reference/syntax/index.md). It is onboarding material,
not a second language specification. The [language
reference](../reference/language.md) owns each construct's meaning.

## The short list

<!-- syntax-extensions:start -->

| Extension family | Grammar additions | Lexical changes |
| --- | --- | --- |
| [Source organization](../reference/language.md#source-files-and-visibility) | import with aliases/member selection, package-qualified alias.Type/alias.member names, and script statements outside an explicit main. | import is a keyword; a leading shebang is handled before lexing. |
| [Optional indentation](../reference/language.md#indentation-syntax) | The parser receives ordinary braces, parentheses, and semicolons. | In .xp or after #pragma indent, a token pass rewrites layout and colons. |
| [Declarations and references](../reference/language.md#c-foundation) | Mixed-type rows, T.method names, & and &? parameters, delegate fields, destructuring, class/NamedType forms, and static type visibility. | delegate and threaded are keywords; Self is contextual. Existing punctuation gains declaration roles. |
| [Protocols](../reference/language.md#protocols) | Protocol definitions/adoptions, associated types, member aliases, and as/tag adoption modifiers. | protocol and associated are keywords; as and tag are contextual words. |
| [Short functions and lambdas](../reference/language.md#lambdas) | Expression bodies use =>; lambdas permit typed or bare parameters and using captures. | %! is a lambda opener; => remains two tokens; using is contextual. |
| [Evaluated collections](../reference/language.md#array-and-map-literals) | Bare Array/Map literals, destination-typed brace expressions, void as a value, and trailing ordinary call-argument commas. | No new delimiter tokens: [], {}, commas, colons, and void acquire expression roles. |
| [Quoted data and text](../reference/language.md#percent-literals-quote-and-unquote) | List/data readers, interpolation, splicing, reader prefixes, typed pattern captures, Symbols, and SymbolSets. | Percent openers select reader modes; braced interpolation/splicing re-enters code; angle Symbols, atom boundaries, byte escapes, signed data numbers, and explicit 0o octal extend scanning. |
| [Operators and slices](../reference/language.md#membership-with-in) | === and !==, in, is/is not, @ and @=, and [start:stop:step] extend the C expression ladder. | ===, !==, @, and @= are operator tokens; in is contextually retagged; is and not remain contextual words. |
| [Iteration and matching](../reference/language.md#statements) | foreach binders and match cases with patterns and optional guards; case/default otherwise remain C forms. | match is contextually retagged; foreach is a shipped keyword alias; pattern sigils are data-mode atom spellings. |
| [Cleanup and errors](../reference/language.md#errors-and-cleanup) | with/as blocks, defer statements, try/catch/finally, and raise with structured details. | defer, try, catch, finally, and raise are keywords; with/as are contextual; error patterns reuse List mode. |
| [Syntax-producing code](../reference/language.md#compile-time-macros) | Typed macro holes/results, sequence holes, aliases, decorators, source quotations, Lisp escapes, and meta/native functions. | $ references and $( switch into compile-time forms; $! uses ordinary ! after $; macro/keyword/meta/native are contextual. |

<!-- syntax-extensions:end -->

The grammar column identifies added alternatives or contexts. It does not
classify an entire shared production as non-C. For example, `==` remains C;
`===` is an addition within the same equality production. An `&` before a
parameter name is new reference syntax; unary `&value` is ordinary C.

Grammar changes need not introduce tokens. Bare `[a, b]` Arrays and
`{key: value}` Maps reuse C punctuation in new expression positions.
Conversely, percent literals change how their contents are tokenized.
`=>` is a grammar spelling composed of two tokens, not a new lexer token.

## What was subtracted

The comparison baseline is **C11**, using its lexical clauses and syntax
summary: [WG14 N1570, sections 6.4 and Annex A](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf).
Ordinary C declarations, pointer declarators, expressions, control flow,
designated initializers, compound literals, `_Static_assert`, `_Generic`,
and `_Thread_local` are therefore absent from the short list.

This is a reviewed classification of the extracted forms. It is not an
automatically proven difference between the languages accepted by two
complete parsers. Contextual binding, macro signatures, and lexical modes
prevent a simple subtraction of production names from giving that result.

Three boundaries keep the map useful:

- **Existing native extensions:** GNU statement expressions `({ ... })`,
  GNU attributes, vendor `^` declarators, linkage strings/groups, and native
  annotation macros support interoperability. They are not x2c inventions.
- **Later C overlap:** C23 includes binary `0b` integers, the `thread_local`
  keyword, and empty initializers. These are outside the C11 baseline but
  are not uniquely x2c. See [WG14 N3096, sections 6.4.4.1, 6.7.1, and
  6.7.10](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n3096.pdf).
  x2c's `threaded` is another spelling of C thread storage. Its `{}` can
  construct an Array or Map according to the destination, which adds meaning.
- **Implementation differences:** ASCII identifier scanning, separate
  wide/UTF string-prefix tokens, numeric and escape edge cases, required
  `(void)` in ordinary no-argument declarations, and aggregate-body limits
  belong in the specifications' compatibility notes. They are not onboarding
  features or evidence of complete C conformance.

## What syntax alone cannot show

Names such as `String`, `Var`, and `List` use ordinary type-name syntax.
Boxing, conversion, lifetime, truthiness, pointer-dot access, method-call
resolution, and operators backed by protocols add behavior without always
adding syntax. `(a, b) = values` also needs its assignment interpretation to
explain destructuring. A grammar-only diagram must not imply these behaviors
follow from punctuation alone.

`class` and `foreach` are shipped aliases built on x2c's macro system.
User macros can add further source forms through the same typed positions.
Consequently, the short list describes the built-in and shipped language
surface; it cannot enumerate every future alias or macro invocation.

## Use the map to build learning material

The feature records in `etc/syntax/extensions.x` connect each family to
grammar productions, lexical rules, example spellings, and a reference
section. The table above is generated from those records. The grouping and
C comparison are reviewed annotations; grammar and lexer data do not infer
pedagogical categories themselves.

Those links support three concrete kinds of diagram:

- A **literal chooser** can start with the value wanted: evaluated Array or
  Map, quoted List, interpolated String, Symbol, or SymbolSet.
- A **reader-mode diagram** can show percent openers entering data modes
  and `${...}` returning temporarily to expressions.
- A **C-to-x2c syntax tour** can show one new alternative beside the
  familiar C production, such as `=>` beside a function block or `&?`
  beside a pointer parameter.

These are suggested consumers of the map. Their construction does not
require replacing the compiler's parser or treating the map as a grammar.
