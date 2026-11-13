# What x2c Adds to C Syntax

For a C reader, x2c adds twelve useful syntax families. Most declarations,
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
| [Source organization](../reference/language.md#source-files-and-visibility) | `import` a package, optionally `as` an alias or `with` chosen members, and name its contents as `alias.Type`. A `module` block gathers members from several files, and a script can run statements outside `main`. | `import` is a keyword only where an import can start. A leading `#!` line is skipped before tokenizing. |
| [Optional indentation](../reference/language.md#indentation-syntax) | Indentation opens and closes blocks and ends statements. The parser still receives ordinary `{`, `}`, and `;`. | In a `.xp` file or after `#pragma indent`, indentation and a trailing `:` become braces and semicolons. |
| [Declarations and references](../reference/language.md#c-foundation) | Declare owned values with `auto`, mix types in one row (`int i, float x`), and unpack a List with `Var (a, b) = values`. Name methods `T.method`, take `&` and `&?` reference parameters, and declare `class` types, `delegate` fields, and file-private `static typedef` names. | `delegate`, `threaded`, and `Self` are keywords only in declarations. Existing punctuation such as `&` and `.` takes new roles there. |
| [Expression aliases](../reference/language.md#expression-aliases-with-alias) | `alias name to e;` and `alias e as name;` name an expression for the rest of a scope, or for one braced body where `_` is the default name. `unalias name;` removes an alias. | `alias`, `unalias`, `as`, and `to` are keywords only in these forms. Inside an `enum`, an alias needs no comma. |
| [Protocols](../reference/language.md#protocols) | `protocol` declares the methods a type must provide, with `associated` types and member aliases. An adoption makes a type satisfy a protocol, and `as` or `tag` chooses its `Var` tag. | `protocol`, `associated`, `as`, and `tag` are keywords only in these forms. |
| [Short functions and lambdas](../reference/language.md#lambdas) | `int f(int x) => x + 1;` returns an expression directly. `%!(int x) => x + 1` builds a lambda; its parameters may omit types, and `using` names captured variables. | `%!` opens a lambda. `=>` is `=` followed by `>`, not a new token, and `using` is a keyword only in a lambda. |
| [Evaluated collections](../reference/language.md#array-and-map-literals) | `[a, b]` builds an Array and `{key: value}` builds a Map; a brace list such as `return {a, b};` takes the destination's type. `void` is a value, and a call may end with a comma, as in `f(a,)`. | No new tokens: `[]`, `{}`, `,`, `:`, and `void` take new roles in expressions. |
| [Quoted data and text](../reference/language.md#percent-literals-quote-and-unquote) | `%(...)` reads List data, and `%"..."` puts `$name` and `$(expr)` values into text. `@items` splices a sequence, `<name>` spells a Symbol, `%<...>` a SymbolSet, and `?(Type name)` a typed pattern capture. | Each `%` opener reads data until its closing bracket, and `$(...)` and `@(...)` return to code inside it. Data also accepts signed numbers, byte escapes, and `0o17` octal. |
| [Operators and slices](../reference/language.md#membership-with-in) | `===` and `!==` test identity, `x ~= pattern` tests a match, `x in xs` tests membership, and `x is T` and `x is not T` test a type. `xs[start:stop:step]` slices a sequence. | `===`, `!==`, and `~=` are new operator tokens. `in`, `is`, and `not` are keywords only in these expressions. |
| [Iteration and matching](../reference/language.md#statements) | `foreach (T x in xs)` loops over a sequence. `match` selects the first `case pattern:` that fits, with an optional `if (test)` guard; other `case` and `default` labels keep their C meaning. | `match` is a keyword only where a statement starts, and `foreach` is a `keyword` macro that ships with x2c. In a pattern, `?name` binds one value and `*rest` binds the remaining elements. |
| [Cleanup and errors](../reference/language.md#errors-and-cleanup) | `auto { ... }` frees what a block allocates, `with (place = value)` sets places and restores them, and `defer` runs work at scope exit. `try`, `catch`, `finally`, and `raise` handle structured errors. | `defer` is reserved; `try`, `catch`, `finally`, and `raise` are keywords only in these statements. `catch %(...)` and `raise %(...)` describe an error as quoted data. |
| [Syntax-producing code](../reference/language.md#compile-time-macros) | `macro` and `keyword` define new syntax with typed holes, `@` parameters accept sequences, and quotations and decorators build source. `meta` functions run at compile time, and `meta native` lets compile-time code call the native copy of a function the compiler links. | `$name` inserts one result and `@items` splices a sequence; `$!` is `$` followed by `!`. `macro`, `keyword`, `meta`, and `native` are keywords only where a definition starts. |

<!-- syntax-extensions:end -->

The grammar column identifies added alternatives or contexts. It does not
classify an entire shared production as non-C. For example, `==` remains C;
`===` is an addition within the same equality production. An `&` before a
parameter name is new reference syntax; unary `&value` is ordinary C.

Grammar changes need not introduce tokens. Bare `[a, b]` Arrays and
`{key: value}` Maps reuse C punctuation in new expression positions.
Conversely, percent literals change how their contents are tokenized.
`=>` is a grammar spelling composed of two tokens, not a new lexer token.

## What the list leaves out

The comparison baseline is C11, using its lexical clauses and syntax
summary: [WG14 N1570, sections 6.4 and Annex A](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf).
Ordinary C declarations, pointer declarators, expressions, control flow,
designated initializers, compound literals, `_Static_assert`, `_Generic`,
and `_Thread_local` are therefore absent from the short list.

Three boundaries keep the map useful:

- Existing native extensions: GNU statement expressions `({ ... })`,
  GNU attributes, linkage strings/groups, and native annotation macros
  support interoperability. They are not x2c inventions. Vendor `^` block
  declarators are read only in collected C headers; x2c source rejects them.
- Later C overlap: C23 includes binary `0b` integers, the `thread_local`
  keyword, and empty initializers. These are outside the C11 baseline but
  are not uniquely x2c. See [WG14 N3096, sections 6.4.4.1, 6.7.1, and
  6.7.10](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n3096.pdf).
  x2c's `threaded` is another spelling of C thread storage. Its `{}` can
  construct an Array or Map according to the destination, which adds meaning.
- Implementation differences: ASCII identifier scanning, separate
  wide/UTF string-prefix tokens, numeric and escape edge cases, required
  `(void)` in ordinary no-argument declarations, and aggregate-body limits
  belong in the specifications' compatibility notes. They are not onboarding
  features or evidence of complete C conformance.

## What syntax alone cannot show

Names such as `String`, `Var`, and `List` use ordinary type-name syntax.
Boxing, conversion, lifetime, truthiness, pointer-dot access, method-call
resolution, and operators backed by protocols add behavior without always
adding syntax. `(a, b) = values` also needs its assignment interpretation to
explain destructuring.

`class` and `foreach` are shipped aliases built on x2c's macro system.
User macros can add further source forms through the same typed positions.
Consequently, the short list describes the built-in and shipped language
surface; it cannot enumerate every future alias or macro invocation.

## Where to go next

- [Values and Var](values.md) introduces the value type behind most of these
  forms.
