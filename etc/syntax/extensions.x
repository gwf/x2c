/*  extensions.x -- x2c syntax additions grouped for documentation

    References identify affected productions, not whole non-C productions.
    Notes select the added alternatives within those productions.
*/

#pragma once

#include "x2c.x"

List syntax_extensions(void) => %(
  extensions
  (baseline "C11")
  (features
    (feature source-organization
      (title "Source organization")
      (summary "Import packages, assemble module members, and run script statements.")
      (grammar import-declaration import-member module-block script-unit type-reference identifier)
      (lexical c-tokens)
      (grammar-note "`import` a package, optionally `as` an alias or `with` chosen members, and name its contents as `alias.Type`. A `module` block gathers members from several files, and a script can run statements outside `main`.")
      (lexical-note "`import` is a keyword only where an import can start. A leading `#!` line is skipped before tokenizing.")
      (spellings "import" "as" "with" "module" "#!")
      (reference "../reference/language.md#source-files-and-visibility"))
    (feature layout
      (title "Optional indentation")
      (summary "Write blocks and statement endings through indentation.")
      (grammar block governed statement)
      (lexical layout)
      (grammar-note "Indentation opens and closes blocks and ends statements. The parser still receives ordinary `{`, `}`, and `;`.")
      (lexical-note "In a `.xp` file or after `#pragma indent`, indentation and a trailing `:` become braces and semicolons.")
      (spellings ".xp" "#pragma indent" ":")
      (reference "../reference/language.md#indentation-syntax"))
    (feature declarations
      (title "Declarations and references")
      (summary "Name methods, borrow parameters, and unpack List values.")
      (grammar declaration-row declaration-group pointer-part method-name
               type-reference storage field destructuring-targets
               typed-destructuring class-declaration named-type assignment
               init-declarator)
      (lexical c-tokens)
      (grammar-note "Declare owned values with `auto`, mix types in one row (`int i, float x`), and unpack a List with `Var (a, b) = values`. Name methods `T.method`, take `&` and `&?` reference parameters, and declare `class` types, `delegate` fields, and file-private `static typedef` names.")
      (lexical-note "`delegate`, `threaded`, and `Self` are keywords only in declarations. Existing punctuation such as `&` and `.` takes new roles there.")
      (spellings "auto T a = x, b = y" "T a = auto x" "T.method"
                 "&" "&?" "delegate" "threaded" "Self"
                 "class" "static typedef" "int i, float x"
                 "Var (a, b) = values")
      (reference "../reference/language.md#c-foundation"))
    (feature aliases
      (title "Expression aliases")
      (summary "Name an expression for the rest of a scope or for one body.")
      (grammar unit-alias block-item statement field enumerator-list
               alias-head alias-name alias-to named-alias alias-wrapper
               alias-statement field-alias enumerator-alias unalias)
      (lexical c-tokens)
      (grammar-note "`alias name to e;` and `alias e as name;` name an expression for the rest of a scope, or for one braced body where `_` is the default name. `unalias name;` removes an alias.")
      (lexical-note "`alias`, `unalias`, `as`, and `to` are keywords only in these forms. Inside an `enum`, an alias needs no comma.")
      (spellings "alias name to e;" "alias name to e { ... }"
                 "alias e as name;" "alias e as name { ... }"
                 "alias e { ... _ ... }" "static alias e as name;"
                 "unalias name;")
      (reference "../reference/language.md#expression-aliases-with-alias"))
    (feature protocols
      (title "Protocols")
      (summary "Declare a method contract and adopt it for a type.")
      (grammar protocol-form associated-type protocol-member)
      (lexical c-tokens)
      (grammar-note "`protocol` declares the methods a type must provide, with `associated` types and member aliases. An adoption makes a type satisfy a protocol, and `as` or `tag` chooses its `Var` tag.")
      (lexical-note "`protocol`, `associated`, `as`, and `tag` are keywords only in these forms.")
      (spellings "protocol" "associated" "as" "tag")
      (reference "../reference/language.md#protocols"))
    (feature functions
      (title "Short functions and lambdas")
      (summary "Return an expression directly or construct a closure.")
      (grammar function-body lambda bare-parameters capture-list)
      (lexical percent-forms)
      (grammar-note "`int f(int x) => x + 1;` returns an expression directly. `%!(int x) => x + 1` builds a lambda; its parameters may omit types, and `using` names captured variables.")
      (lexical-note "`%!` opens a lambda. `=>` is `=` followed by `>`, not a new token, and `using` is a keyword only in a lambda.")
      (spellings "=>" "%!" "using")
      (reference "../reference/language.md#lambdas"))
    (feature collections
      (title "Evaluated collections")
      (summary "Build Arrays and Maps from expressions.")
      (grammar primary array map map-entry initializer atomic arguments)
      (lexical c-tokens)
      (grammar-note "`[a, b]` builds an Array and `{key: value}` builds a Map; a brace list such as `return {a, b};` takes the destination's type. `void` is a value, and a call may end with a comma, as in `f(a,)`.")
      (lexical-note "No new tokens: `[]`, `{}`, `,`, `:`, and `void` take new roles in expressions.")
      (spellings "[a, b]" "{key: value}" "return {a, b};" "void"
                 "f(a,)")
      (reference "../reference/language.md#array-and-map-literals"))
    (feature quoted-data
      (title "Quoted data and text")
      (summary "Read structured data, interpolate values, and spell Symbols.")
      (grammar quoted-list quoted-array quoted-map percent-string symbol-set
               list-element insertion splice reader-prefix typed-capture
               symbol atom integer)
      (lexical percent-forms data-prefix data-punctuation symbol string-segment
               x2c-escape byte-escape list-atom collection-atom set-atom signed-number
               octal-integer)
      (grammar-note "`%(...)` reads List data, and `%\"...\"` puts `\$name` and `\$(expr)` values into text. `@items` splices a sequence, `<name>` spells a Symbol, `%<...>` a SymbolSet, and `?(Type name)` a typed pattern capture.")
      (lexical-note "Each `%` opener reads data until its closing bracket, and `\$(...)` and `@(...)` return to code inside it. Data also accepts signed numbers, byte escapes, and `0o17` octal.")
      (spellings "%(...)" "%[...]" "%{...}" "%\"...\"" "%<...>"
                 "<name>" "\$name" "\$(expr)" "@items" "@(expr)"
                 "?(Type name)" "'" "`" ",@" "0o17")
      (reference "../reference/language.md#percent-literals-quote-and-unquote"))
    (feature operators
      (title "Operators and slices")
      (summary "Test identity, membership, or type; slice a sequence.")
      (grammar equality relational type-selector postfix-part)
      (lexical c-tokens keyword-retag)
      (grammar-note "`===` and `!==` test identity, `x ~= pattern` tests a match, `x in xs` tests membership, and `x is T` and `x is not T` test a type. `xs[start:stop:step]` slices a sequence.")
      (lexical-note "`===`, `!==`, and `~=` are new operator tokens. `in`, `is`, and `not` are keywords only in these expressions.")
      (spellings "===" "!==" "~=" "in" "is" "is not"
                 "[start:stop:step]")
      (reference "../reference/language.md#membership-with-in"))
    (feature iteration-matching
      (title "Iteration and matching")
      (summary "Iterate values and select structured patterns.")
      (grammar foreach-statement declaration-argument match-statement
               match-row pattern)
      (lexical keyword-retag list-atom)
      (grammar-note "`foreach (T x in xs)` loops over a sequence. `match` selects the first `case pattern:` that fits, with an optional `if (test)` guard; other `case` and `default` labels keep their C meaning.")
      (lexical-note "`match` is a keyword only where a statement starts, and `foreach` is a `keyword` macro that ships with x2c. In a pattern, `?name` binds one value and `*rest` binds the remaining elements.")
      (spellings "foreach" "match" "case pattern if (test):"
                 "?name" "*rest")
      (reference "../reference/language.md#statements"))
    (feature cleanup-errors
      (title "Cleanup and errors")
      (summary "Scope resources, defer work, and handle structured errors.")
      (grammar auto-region-prefix auto-region-function auto-region-statement
               with-statement with-entry statement try-statement catch-arm catch-payload
               catch-detail raise-statement raise-detail)
      (lexical c-tokens percent-forms list-atom)
      (grammar-note "`auto { ... }` frees what a block allocates, `with (place = value)` sets places and restores them, and `defer` runs work at scope exit. `try`, `catch`, `finally`, and `raise` handle structured errors.")
      (lexical-note "`defer` is reserved; `try`, `catch`, `finally`, and `raise` are keywords only in these statements. `catch %(...)` and `raise %(...)` describe an error as quoted data.")
      (spellings "auto { ... }" "auto (destination)"
                 "with (place = value, ...)"
                 "defer" "try" "catch" "finally" "raise")
      (reference "../reference/language.md#errors-and-cleanup"))
    (feature macros-meta
      (title "Syntax-producing code")
      (summary "Define macros, quote source, and run compile-time code.")
      (grammar macro-definition local-macro-definition anonymous-macro
               keyword-definition macro-signature hole-parameter macro-body
               macro-expression macro-arguments quotation quotation-items
               decorator declaration-definition
               expression-slot argument-slot declarator-row-slot
               named-type-slot type-slot name-slot parameter-slot
               captures-slot catch-slot match-row-slot unit-macro
               block-extension statement-macro field-extension
               enumerator-extension entry-extension)
      (lexical code-reference named-reference data-prefix)
      (grammar-note "`macro` and `keyword` define new syntax with typed holes, `@` parameters accept sequences, and quotations and decorators build source. `meta` functions run at compile time, and `meta native` lets compile-time code call the native copy of a function the compiler links.")
      (lexical-note "`\$name` inserts one result and `@items` splices a sequence; `\$!` is `\$` followed by `!`. `macro`, `keyword`, `meta`, and `native` are keywords only where a definition starts.")
      (spellings "macro" "keyword" "\$name(...)" "\$!{...}"
                 "@items" "@name(...)" "@(expression)"
                 "meta" "native")
      (reference "../reference/language.md#compile-time-macros")))
  (inherited
    (item c11
      (summary "C declarations/control flow, designated initializers, compound literals, _Static_assert, _Generic, _Thread_local, _Alignas, _Atomic, and _Complex are baseline syntax."))
    (item native
      (summary "GNU statement expressions/attributes, linkage strings/groups, and native annotation macros are interoperability forms, not x2c inventions. Vendor ^ block declarators are read only in collected C headers; x2c source rejects them."))
    (item later-c
      (summary "0b binary integers, thread_local, and native empty initializers overlap C23; x2c Map/Array meaning for {} remains additional.")))
  (differences
    (item lexical-coverage
      (summary "The extracted lexer uses ASCII identifiers, does not combine wide/UTF literal prefixes, and differs in numeric and escape edge cases."))
    (item parser-coverage
      (summary "The grammar requires (void) for ordinary no-argument declarations and a field in ordinary aggregate bodies; it is not a C conformance claim."))
    (item parser-permissiveness
      (summary "Labels are independent block items; do/while does not consume a semicolon; token recognition can exceed valid native C."))
    (item semantic-only
      (summary "Runtime types, boxing/conversions, method-call resolution, pointer-dot access, operator protocols, ownership, and truthiness cannot be recovered by grammar subtraction alone.")))
);
