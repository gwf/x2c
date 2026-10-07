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
      (summary "Import packages and run statements in script units.")
      (grammar import-declaration import-member script-unit type-reference identifier)
      (lexical c-tokens)
      (grammar-note "import with aliases/member selection, package-qualified alias.Type/alias.member names, and script statements outside an explicit main.")
      (lexical-note "import is a keyword; a leading shebang is handled before lexing.")
      (spellings "import" "as" "with" "#!")
      (reference "../reference/language.md#source-files-and-visibility"))
    (feature layout
      (title "Optional indentation")
      (summary "Write blocks and statement endings through indentation.")
      (grammar block governed statement)
      (lexical layout)
      (grammar-note "The parser receives ordinary braces, parentheses, and semicolons.")
      (lexical-note "In .xp or after #pragma indent, a token pass rewrites layout and colons.")
      (spellings ".xp" "#pragma indent" ":")
      (reference "../reference/language.md#indentation-syntax"))
    (feature declarations
      (title "Declarations and references")
      (summary "Name methods, borrow parameters, and unpack List values.")
      (grammar declaration-row declaration-group pointer-part method-name
               type-reference storage field destructuring-targets
               typed-destructuring class-declaration named-type assignment)
      (lexical c-tokens)
      (grammar-note "Mixed-type rows, T.method names, & and &? parameters, delegate fields, destructuring, class/NamedType forms, and static type visibility.")
      (lexical-note "delegate and threaded are keywords; Self is contextual. Existing punctuation gains declaration roles.")
      (spellings "T.method" "&" "&?" "delegate" "threaded" "Self"
                 "class" "static typedef" "int i, float x"
                 "Var (a, b) = values")
      (reference "../reference/language.md#c-foundation"))
    (feature protocols
      (title "Protocols")
      (summary "Declare a method contract and adopt it for a type.")
      (grammar protocol-form associated-type protocol-member)
      (lexical c-tokens)
      (grammar-note "Protocol definitions/adoptions, associated types, member aliases, and as/tag adoption modifiers.")
      (lexical-note "protocol and associated are keywords; as and tag are contextual words.")
      (spellings "protocol" "associated" "as" "tag")
      (reference "../reference/language.md#protocols"))
    (feature functions
      (title "Short functions and lambdas")
      (summary "Return an expression directly or construct a closure.")
      (grammar function-body lambda bare-parameters capture-list)
      (lexical percent-forms)
      (grammar-note "Expression bodies use =>; lambdas permit typed or bare parameters and using captures.")
      (lexical-note "%! is a lambda opener; => remains two tokens; using is contextual.")
      (spellings "=>" "%!" "using")
      (reference "../reference/language.md#lambdas"))
    (feature collections
      (title "Evaluated collections")
      (summary "Build Arrays and Maps from expressions.")
      (grammar primary array map map-entry initializer atomic arguments)
      (lexical c-tokens)
      (grammar-note "Bare Array/Map literals, destination-typed brace expressions, void as a value, and trailing ordinary call-argument commas.")
      (lexical-note "No new delimiter tokens: [], {}, commas, colons, and void acquire expression roles.")
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
      (grammar-note "List/data readers, interpolation, splicing, reader prefixes, typed pattern captures, Symbols, and SymbolSets.")
      (lexical-note "Percent openers select reader modes; braced interpolation/splicing re-enters code; angle Symbols, atom boundaries, byte escapes, signed data numbers, and explicit 0o octal extend scanning.")
      (spellings "%(...)" "%[...]" "%{...}" "%\"...\"" "%<<...>>"
                 "<name>" "\$name" "\${expr}" "@items" "@{expr}"
                 "?(Type name)" "'" "`" ",@" "0o17")
      (reference "../reference/language.md#percent-literals-quote-and-unquote"))
    (feature operators
      (title "Operators and slices")
      (summary "Test identity, membership, or type; slice a sequence.")
      (grammar assignment-op equality relational type-selector
               multiplicative postfix-part)
      (lexical c-tokens keyword-retag)
      (grammar-note "=== and !==, in, is/is not, @ and @=, and [start:stop:step] extend the C expression ladder.")
      (lexical-note "===, !==, @, and @= are operator tokens; in is contextually retagged; is and not remain contextual words.")
      (spellings "===" "!==" "in" "is" "is not" "@" "@="
                 "[start:stop:step]")
      (reference "../reference/language.md#membership-with-in"))
    (feature iteration-matching
      (title "Iteration and matching")
      (summary "Iterate values and select structured patterns.")
      (grammar foreach-statement declaration-argument match-statement
               match-row pattern)
      (lexical keyword-retag list-atom)
      (grammar-note "foreach binders and match cases with patterns and optional guards; case/default otherwise remain C forms.")
      (lexical-note "match is contextually retagged; foreach is a shipped keyword alias; pattern sigils are data-mode atom spellings.")
      (spellings "foreach" "match" "case pattern if (test):"
                 "?name" "*rest")
      (reference "../reference/language.md#statements"))
    (feature cleanup-errors
      (title "Cleanup and errors")
      (summary "Scope resources, defer work, and handle structured errors.")
      (grammar with-statement statement try-statement catch-arm catch-payload
               catch-detail raise-statement raise-detail)
      (lexical c-tokens percent-forms list-atom)
      (grammar-note "with/as blocks, defer statements, try/catch/finally, and raise with structured details.")
      (lexical-note "defer, try, catch, finally, and raise are keywords; with/as are contextual; error patterns reuse List mode.")
      (spellings "with" "as" "defer" "try" "catch" "finally" "raise")
      (reference "../reference/language.md#errors-and-cleanup"))
    (feature macros-meta
      (title "Syntax-producing code")
      (summary "Define macros, quote source, and run compile-time code.")
      (grammar macro-definition local-macro-definition anonymous-macro
               keyword-definition macro-signature hole-parameter macro-body
               macro-expression macro-arguments quotation quotation-items
               decorator lisp-escape lisp-form declaration-definition
               expression-slot argument-slot declarator-row-slot
               named-type-slot type-slot name-slot parameter-slot
               captures-slot catch-slot match-row-slot unit-macro
               block-extension statement-macro field-extension
               enumerator-extension entry-extension)
      (lexical code-reference named-reference lisp-reference data-prefix)
      (grammar-note "Typed macro holes/results, sequence holes, aliases, decorators, source quotations, Lisp escapes, and meta/native functions.")
      (lexical-note "\$ references and \$( switch into compile-time forms; \$! uses ordinary ! after \$; macro/keyword/meta/native are contextual.")
      (spellings "macro" "keyword" "\$name(...)" "\$!{...}" "\$(...)"
                 "\$hole..." "meta" "native")
      (reference "../reference/language.md#compile-time-macros")))
  (inherited
    (item c11
      (summary "C declarations/control flow, designated initializers, compound literals, _Static_assert, _Generic, and _Thread_local are baseline syntax."))
    (item native
      (summary "GNU statement expressions/attributes, vendor ^ declarators, linkage strings/groups, and native annotation macros are interoperability forms, not x2c inventions."))
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
