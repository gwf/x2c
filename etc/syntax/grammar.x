/*  grammar.x -- source grammar as ordinary List data

    External leaves describe contextual or lexical recognition boundaries.
    The companion reference explains their contracts.
*/

#pragma once

#include "x2c.x"

/** Returns the descriptive source grammar, including external recognition
    boundaries whose contracts appear in the syntax reference.
*/
List syntax_grammar(void) => %(grammar
  (start source-unit)
  (rules
    (rule source-unit (choice (ref translation-unit) (ref script-unit)))

    (rule script-unit
      (external "script partition described in grammar.md entry points"))

    (rule translation-unit (repeat 0 (ref unit-item)))

    (rule unit-item
      (choice
        (ref directive)
        (ref static-assert)
        (ref import-declaration)
        (ref protocol-form)
        (ref macro-definition)
        (ref keyword-definition)
        (seq (optional (token "static")) (ref lisp-escape))
        (ref linkage-group)
        (ref declaration-definition)
        (ref unit-extension)))

    (rule linkage-group
      (seq
        (token "extern")
        (ref c-string)
        (token "{")
        (repeat 0 (ref unit-item))
        (token "}")))

    (rule declaration-definition
      (seq
        (optional (seq (token "meta") (optional (token "native"))))
        (ref declaration-row)
        (choice (token ";") (ref function-body))))

    (rule function-body
      (choice
        (ref block)
        (seq (token "=") (token ">") (ref expression) (token ";"))))

    (rule import-declaration
      (seq
        (token "import")
        (ref c-string)
        (optional (seq (token "as") (ref identifier)))
        (optional
          (seq
            (token "with")
            (ref import-member)
            (repeat 0 (seq (token ",") (ref import-member)))))
        (token ";")))

    (rule import-member
      (seq (ref identifier) (optional (seq (token "as") (ref identifier)))))

    (rule static-assert
      (seq
        (token "_Static_assert")
        (token "(")
        (ref assignment)
        (token ",")
        (ref assignment)
        (token ")")
        (token ";")))

    (rule declaration-row
      (seq
        (ref declaration-group)
        (repeat 0 (seq (token ",") (ref declaration-group)))))

    (rule declaration-group
      (choice
        (seq (ref specifiers) (ref declarator-list))
        (seq
          (ref specifiers)
          (ref destructuring-targets)
          (token "=")
          (ref assignment))))

    (rule specifiers
      (seq
        (repeat 0 (ref declaration-prefix))
        (repeat 0 (ref qualifier))
        (ref type-specifier)
        (repeat 0 (ref trailing-storage))))

    (rule declaration-prefix
      (choice
        (ref storage)
        (token "inline")
        (token "_Noreturn")
        (ref attribute)
        (ref prefix-macro)))

    (rule trailing-storage
      (choice (ref storage) (token "inline") (ref prefix-macro)))

    (rule storage
      (choice
        (token "typedef")
        (seq (token "extern") (optional (ref c-string)))
        (token "static")
        (token "auto")
        (token "register")
        (token "threaded")))

    (rule qualifier
      (choice (token "const") (token "restrict") (token "volatile")))

    (rule type-specifier
      (choice
        (ref scalar-specifiers)
        (ref aggregate)
        (ref enumeration)
        (ref type-reference)
        (ref type-slot)))

    (rule scalar-specifiers
      (seq (ref scalar-word) (repeat 0 (ref scalar-word))))

    (rule scalar-word
      (choice
        (token "void")
        (token "char")
        (token "short")
        (token "int")
        (token "long")
        (token "float")
        (token "double")
        (token "signed")
        (token "unsigned")))

    (rule type-reference
      (seq (ref identifier) (optional (seq (token ".") (ref identifier)))))

    (rule type-name
      (seq
        (repeat 0 (ref qualifier))
        (ref type-specifier)
        (repeat 0 (ref pointer-part))))

    (rule type-operand (ref declaration-group))

    (rule declarator-list
      (seq
        (ref init-declarator)
        (repeat 0 (seq (token ",") (ref init-declarator)))))

    (rule init-declarator
      (seq
        (choice (ref declarator) (ref declarator-row-slot))
        (optional (seq (token "=") (ref assignment)))))

    (rule declarator
      (seq
        (repeat 0 (ref pointer-part))
        (optional (ref direct-declarator))
        (repeat 0 (ref declarator-suffix))))

    (rule pointer-part
      (choice
        (token "*")
        (token "^")
        (seq (token "&") (optional (token "?")))
        (ref qualifier)
        (ref qualifier-macro)))

    (rule direct-declarator
      (choice
        (ref declaration-name)
        (seq (token "(") (ref declarator) (token ")"))))

    (rule declaration-name
      (choice (ref identifier) (ref method-name) (ref name-slot)))

    (rule method-name
      (seq (ref method-owner) (token ".") (ref identifier)))

    (rule method-owner (external "contextual type owner under D1"))

    (rule declarator-suffix
      (choice
        (seq (token "[") (optional (ref expression)) (token "]"))
        (seq (token "(") (ref parameter-list) (token ")"))
        (seq (token ":") (ref primary))
        (ref attribute)))

    (rule parameter-list
      (seq (ref parameter) (repeat 0 (seq (token ",") (ref parameter)))))

    (rule parameter
      (choice
        (seq
          (repeat 0 (ref qualifier))
          (ref type-specifier)
          (ref declarator))
        (token "...")
        (ref parameter-slot)))

    (rule destructuring-targets
      (seq
        (token "(")
        (ref identifier)
        (token ",")
        (ref identifier)
        (repeat 0 (seq (token ",") (ref identifier)))
        (token ")")))

    (rule typed-destructuring
      (seq
        (token "(")
        (ref parameter-list)
        (token ")")
        (token "=")
        (ref assignment)
        (token ";")))

    (rule aggregate
      (seq
        (choice (token "struct") (token "union"))
        (repeat 0 (ref attribute))
        (optional (ref declaration-name))
        (optional
          (seq
            (token "{")
            (ref field)
            (repeat 0 (ref field))
            (token "}")
            (repeat 0 (ref attribute))))))

    (rule field
      (choice
        (seq
          (optional (token "delegate"))
          (ref declaration-row)
          (token ";"))
        (ref static-assert)
        (ref field-extension)))

    (rule enumeration
      (seq
        (token "enum")
        (repeat 0 (ref attribute))
        (optional (ref declaration-name))
        (optional
          (seq
            (token "{")
            (optional
              (seq
                (ref enumerator)
                (repeat 0 (seq (token ",") (ref enumerator)))
                (optional (token ","))))
            (token "}")
            (repeat 0 (ref attribute))))))

    (rule enumerator
      (choice
        (seq
          (ref declaration-name)
          (optional (seq (token "=") (ref conditional))))
        (ref enumerator-extension)))

    (rule named-type
      (choice
        (seq
          (ref identifier)
          (choice
            (token ";")
            (seq
              (repeat 0 (ref qualifier))
              (choice
                (ref type-specifier)
                (seq
                  (optional (choice (token "struct") (token "union")))
                  (token "{")
                  (repeat 0 (ref field))
                  (token "}")))
              (ref abstract-declarator)
              (token ";"))))
        (ref named-type-slot)))

    (rule abstract-declarator
      (external "declarator with no declared name"))

    (rule attribute
      (external
        "balanced GNU attribute or known annotation-macro invocation"))

    (rule prefix-macro
      (external "known native declaration-prefix macro; contract D3"))

    (rule qualifier-macro
      (external "known native macro supplying qualifiers"))

    (rule protocol-form
      (choice
        (seq
          (token "protocol")
          (ref type-name)
          (token "(")
          (ref identifier)
          (token ")")
          (token "{")
          (repeat 0 (ref associated-type))
          (repeat 0 (ref protocol-member))
          (token "}"))
        (seq
          (optional (token "meta"))
          (optional (token "static"))
          (token "protocol")
          (ref type-name)
          (token "(")
          (ref type-name)
          (token ")")
          (optional
            (choice
              (seq (token "as") (ref type-name))
              (seq
                (token "tag")
                (choice (ref atomic) (ref expression-slot)))))
          (token ";"))))

    (rule associated-type
      (seq
        (token "associated")
        (ref identifier)
        (token "=")
        (ref type-name)
        (token ";")))

    (rule protocol-member
      (seq
        (ref specifiers)
        (ref declarator)
        (optional (seq (token "=") (ref identifier)))
        (token ";")))

    (rule block (seq (token "{") (repeat 0 (ref block-item)) (token "}")))

    (rule block-item
      (choice
        (ref directive)
        (ref static-assert)
        (seq (ref declaration-row) (token ";"))
        (ref local-macro-definition)
        (ref statement)
        (ref block-extension)))

    (rule statement
      (choice
        (ref block)
        (token ";")
        (seq (ref expression) (token ";"))
        (ref typed-destructuring)
        (seq (choice (ref identifier) (ref name-slot)) (token ":"))
        (seq (token "case") (ref expression) (token ":"))
        (seq (token "default") (token ":"))
        (seq
          (token "if")
          (token "(")
          (ref expression)
          (token ")")
          (ref governed)
          (optional (seq (token "else") (ref governed))))
        (seq
          (token "while")
          (token "(")
          (ref expression)
          (token ")")
          (ref governed))
        (seq
          (token "do")
          (ref governed)
          (token "while")
          (token "(")
          (ref expression)
          (token ")"))
        (seq
          (token "for")
          (token "(")
          (optional (ref for-init))
          (token ";")
          (optional (ref expression))
          (token ";")
          (optional (ref expression))
          (token ")")
          (ref governed))
        (seq
          (token "switch")
          (token "(")
          (ref expression)
          (token ")")
          (ref governed))
        (seq (token "return") (optional (ref expression)) (token ";"))
        (seq (choice (token "break") (token "continue")) (token ";"))
        (seq (token "goto") (ref declaration-name) (token ";"))
        (seq (token "defer") (ref governed))
        (ref with-statement)
        (ref match-statement)
        (ref try-statement)
        (ref raise-statement)
        (ref statement-extension)))

    (rule for-init (choice (ref type-operand) (ref expression)))

    (rule governed (external "one statement, with directive handling G1"))

    (rule with-statement
      (seq
        (token "with")
        (ref expression)
        (optional (seq (token "as") (ref identifier)))
        (ref block)))

    (rule match-statement
      (seq
        (token "match")
        (token "(")
        (ref expression)
        (token ")")
        (choice
          (seq
            (token "{")
            (repeat 0 (choice (ref directive) (ref match-row)))
            (token "}"))
          (ref match-row))))

    (rule match-row
      (choice
        (seq
          (choice (seq (token "case") (ref pattern)) (token "default"))
          (optional
            (seq (token "if") (token "(") (ref expression) (token ")")))
          (token ":")
          (ref governed))
        (ref match-row-slot)))

    (rule pattern
      (external
        "expression yielding a static List pattern, or macro pattern P1"))

    (rule try-statement
      (seq
        (token "try")
        (ref governed)
        (choice
          (seq
            (ref catch-arm)
            (repeat 0 (ref catch-arm))
            (optional (seq (token "finally") (ref governed))))
          (seq (token "finally") (ref governed)))))

    (rule catch-arm
      (seq
        (token "catch")
        (choice
          (seq (optional (ref catch-payload)) (token ":") (ref governed))
          (ref catch-slot))))

    (rule catch-payload
      (seq
        (token "%(")
        (ref list-element)
        (repeat 0 (ref catch-detail))
        (token ")")))

    (rule catch-detail
      (choice
        (ref sequence-pattern)
        (seq (token "(") (ref bare-symbol) (ref list-element) (token ")"))))

    (rule sequence-pattern (external "list-mode atom beginning with '*'"))

    (rule raise-statement
      (seq
        (token "raise")
        (token "%(")
        (choice (ref bare-symbol) (ref insertion) (ref expression-slot))
        (repeat 0 (choice (ref raise-detail) (ref argument-slot)))
        (token ")")
        (token ";")))

    (rule raise-detail
      (seq
        (token "(")
        (choice (ref bare-symbol) (ref expression-slot))
        (ref list-element)
        (token ")")))

    (rule bare-symbol
      (external "bare lit-atom whose decoded spelling is an exact Symbol"))

    (rule expression
      (seq (ref assignment) (repeat 0 (seq (token ",") (ref assignment)))))

    (rule assignment
      (seq
        (ref conditional)
        (optional (seq (ref assignment-op) (ref assignment)))))

    (rule assignment-op
      (choice
        (token "=")
        (token "+=")
        (token "-=")
        (token "*=")
        (token "/=")
        (token "%=")
        (token "<<=")
        (token ">>=")
        (token "&=")
        (token "^=")
        (token "|=")))

    (rule conditional
      (seq
        (ref logical-or)
        (optional
          (seq (token "?") (ref expression) (token ":") (ref conditional)))))

    (rule logical-or
      (seq
        (ref logical-and)
        (repeat 0 (seq (token "||") (ref logical-and)))))

    (rule logical-and
      (seq (ref bitwise-or) (repeat 0 (seq (token "&&") (ref bitwise-or)))))

    (rule bitwise-or
      (seq
        (ref bitwise-xor)
        (repeat 0 (seq (token "|") (ref bitwise-xor)))))

    (rule bitwise-xor
      (seq
        (ref bitwise-and)
        (repeat 0 (seq (token "^") (ref bitwise-and)))))

    (rule bitwise-and
      (seq (ref equality) (repeat 0 (seq (token "&") (ref equality)))))

    (rule equality
      (seq
        (ref relational)
        (repeat 0
          (seq
            (choice (token "==") (token "!=") (token "===") (token "!=="))
            (ref relational)))))

    (rule relational
      (seq
        (ref shift)
        (repeat 0
          (choice
            (seq
              (choice
                (token "<")
                (token "<=")
                (token ">")
                (token ">=")
                (token "in"))
              (ref shift))
            (seq (token "is") (optional (token "not")) (ref type-selector))))))

    (rule type-selector
      (choice
        (ref type-name)
        (seq (token "(") (ref type-name) (token ")"))
        (ref cast)))

    (rule shift
      (seq
        (ref additive)
        (repeat 0 (seq (choice (token "<<") (token ">>")) (ref additive)))))

    (rule additive
      (seq
        (ref multiplicative)
        (repeat 0
          (seq (choice (token "+") (token "-")) (ref multiplicative)))))

    (rule multiplicative
      (seq
        (ref cast)
        (repeat 0
          (seq
            (choice (token "*") (token "/") (token "%"))
            (ref cast)))))

    (rule cast
      (choice
        (seq (token "(") (ref type-operand) (token ")") (ref cast))
        (ref unary)))

    (rule unary
      (choice
        (seq (choice (token "++") (token "--")) (ref unary))
        (seq
          (choice
            (token "&")
            (token "*")
            (token "+")
            (token "-")
            (token "~")
            (token "!"))
          (ref cast))
        (seq
          (token "sizeof")
          (choice
            (seq
              (token "(")
              (choice (ref type-operand) (ref expression))
              (token ")"))
            (ref type-operand)
            (ref unary)))
        (ref postfix)))

    (rule postfix (seq (ref primary) (repeat 0 (ref postfix-part))))

    (rule postfix-part
      (choice
        (seq (token "[") (ref expression) (token "]"))
        (seq
          (token "[")
          (optional (ref expression))
          (token ":")
          (optional (ref expression))
          (optional (seq (token ":") (optional (ref expression))))
          (token "]"))
        (seq (token "(") (optional (ref arguments)) (token ")"))
        (seq (choice (token ".") (token "->")) (ref member-name))
        (token "++")
        (token "--")))

    (rule arguments
      (seq
        (ref argument)
        (repeat 0 (seq (token ",") (ref argument)))
        (optional (token ","))))

    (rule argument (choice (ref assignment) (ref argument-slot)))

    (rule member-name (choice (ref identifier) (ref name-slot)))

    (rule primary
      (choice
        (ref atomic)
        (ref c-string-run)
        (ref identifier)
        (seq (token "(") (ref expression) (token ")"))
        (ref statement-expression)
        (ref initializer)
        (ref array)
        (ref map)
        (ref quoted-list)
        (ref quoted-array)
        (ref quoted-map)
        (ref percent-string)
        (ref symbol-set)
        (ref lambda)
        (ref generic)
        (ref va-arg)
        (ref offsetof)
        (ref lisp-escape)
        (ref macro-expression)
        (ref quotation)
        (ref expression-slot)))

    (rule atomic
      (choice
        (ref integer)
        (ref floating)
        (ref character)
        (ref c-string)
        (ref symbol)
        (ref atom)
        (token "void")))

    (rule c-string-run
      (seq
        (ref c-string)
        (repeat 0 (choice (ref c-string) (ref native-string-word)))))

    (rule native-string-word
      (external "adjacent native macro or unbound word accepted by E3"))

    (rule statement-expression (seq (token "(") (ref block) (token ")")))

    (rule initializer
      (seq
        (token "{")
        (optional
          (seq
            (ref initializer-item)
            (repeat 0 (seq (token ",") (ref initializer-item)))
            (optional (token ","))))
        (token "}")))

    (rule initializer-item
      (choice
        (ref assignment)
        (ref argument-slot)
        (seq
          (ref designator)
          (repeat 0 (ref designator))
          (token "=")
          (ref assignment))))

    (rule designator
      (choice
        (seq (token ".") (ref identifier))
        (seq (token "[") (ref assignment) (token "]"))))

    (rule array
      (seq
        (token "[")
        (optional
          (seq
            (ref assignment)
            (repeat 0 (seq (token ",") (ref assignment)))
            (optional (token ","))))
        (token "]")))

    (rule map
      (seq
        (token "{")
        (optional
          (seq
            (ref map-entry)
            (repeat 0 (seq (token ",") (ref map-entry)))
            (optional (token ","))))
        (token "}")))

    (rule map-entry
      (choice
        (seq
          (choice (ref identifier) (ref assignment))
          (token ":")
          (ref assignment))
        (ref entry-extension)))

    (rule generic
      (seq
        (token "_Generic")
        (token "(")
        (ref assignment)
        (repeat 0
          (seq
            (token ",")
            (choice (ref type-name) (token "default"))
            (token ":")
            (ref assignment)))
        (token ")")))

    (rule va-arg
      (seq
        (token "va_arg")
        (token "(")
        (ref assignment)
        (token ",")
        (ref type-operand)
        (token ")")))

    (rule offsetof
      (seq
        (token "offsetof")
        (token "(")
        (ref type-name)
        (token ",")
        (ref identifier)
        (repeat 0
          (choice
            (seq (token ".") (ref identifier))
            (seq (token "[") (ref expression) (token "]"))))
        (token ")")))

    (rule lambda
      (seq
        (token "%!")
        (token "(")
        (optional (choice (ref parameter-list) (ref bare-parameters)))
        (token ")")
        (optional (seq (token "using") (ref capture-list)))
        (token "=")
        (token ">")
        (choice (ref block) (ref assignment))))

    (rule bare-parameters
      (seq (ref identifier) (repeat 0 (seq (token ",") (ref identifier)))))

    (rule capture-list
      (choice
        (seq
          (token "&")
          (ref declaration-name)
          (repeat 0 (seq (token ",") (token "&") (ref declaration-name))))
        (ref captures-slot)))

    (rule quoted-list
      (seq (token "%(") (repeat 0 (ref list-element)) (token ")")))

    (rule nested-list
      (seq (token "(") (repeat 0 (ref list-element)) (token ")")))

    (rule list-element
      (choice
        (ref literal-element)
        (ref insertion)
        (ref splice)
        (seq (ref reader-prefix) (ref list-element))))

    (rule literal-element
      (choice
        (ref atomic)
        (ref nested-list)
        (ref quoted-array)
        (ref quoted-map)
        (ref percent-string)
        (ref typed-capture)))

    (rule insertion
      (choice
        (seq (token "\$") (ref identifier))
        (seq (token "\${") (ref expression) (token "}"))))

    (rule splice
      (choice
        (seq (token "@") (ref identifier))
        (seq (token "@{") (ref expression) (token "}"))))

    (rule reader-prefix
      (choice (token "'") (token "`") (token ",") (token ",@")))

    (rule typed-capture
      (seq (token "?(") (ref type-name) (ref identifier) (token ")")))

    (rule quoted-array
      (seq
        (token "%[")
        (optional
          (seq
            (ref quoted-array-item)
            (repeat 0 (seq (token ",") (ref quoted-array-item)))
            (optional (token ","))))
        (token "]")))

    (rule quoted-array-item
      (choice (ref data-element) (ref argument-slot)))

    (rule data-element (choice (ref literal-element) (ref insertion)))

    (rule quoted-map
      (seq
        (token "%{")
        (optional
          (seq
            (ref quoted-entry)
            (repeat 0 (seq (token ",") (ref quoted-entry)))
            (optional (token ","))))
        (token "}")))

    (rule quoted-entry
      (choice
        (seq (ref data-element) (token ":") (ref data-element))
        (ref quoted-entry-extension)))

    (rule quoted-entry-extension
      (seq (token "\${") (ref entry-extension) (token "}")))

    (rule percent-string
      (seq
        (token "%\"")
        (repeat 0 (choice (ref string-segment) (ref insertion)))
        (token "\"")))

    (rule symbol-set
      (seq (token "%<<") (repeat 0 (ref symbol-set-member)) (token ">>")))

    (rule symbol-set-member
      (external "symbol-set-mode lit-atom or lit-symbol"))

    (rule unit-extension
      (choice (ref class-declaration) (ref unit-macro) (ref decorator)))

    (rule class-declaration
      (seq (optional (token "static")) (token "class") (ref named-type)))

    (rule statement-extension
      (choice
        (ref foreach-statement)
        (ref statement-macro)
        (ref decorator)))

    (rule foreach-statement
      (seq
        (token "foreach")
        (token "(")
        (ref declaration-argument)
        (choice (token "in") (token ","))
        (ref assignment)
        (token ")")
        (ref governed)))

    (rule declaration-argument
      (seq
        (ref specifiers)
        (choice (ref init-declarator) (ref destructuring-targets))))

    (rule keyword-definition
      (seq
        (optional (token "static"))
        (token "keyword")
        (ref identifier)
        (ref macro-name)
        (token ";")))

    (rule macro-name
      (seq
        (token "\$")
        (ref identifier)
        (repeat 0 (seq (token ".") (ref identifier)))))

    (rule macro-definition
      (seq
        (optional (token "static"))
        (token "macro")
        (ref result-kind)
        (ref macro-name)
        (ref macro-signature)
        (ref macro-body)))

    (rule local-macro-definition
      (seq
        (token "macro")
        (ref result-kind)
        (ref identifier)
        (ref macro-signature)
        (ref macro-body)))

    (rule anonymous-macro
      (seq
        (token "macro")
        (ref result-kind)
        (ref macro-signature)
        (ref macro-body)))

    (rule macro-expression
      (choice
        (ref macro-call)
        (ref local-macro-call)
        (ref anonymous-macro)
        (ref meta-call)
        (ref macro-name)))

    (rule macro-signature
      (seq
        (token "(")
        (optional
          (seq
            (ref hole-parameter)
            (repeat 0 (seq (token ",") (ref hole-parameter)))))
        (token ")")
        (optional (seq (token "using") (ref using-list)))))

    (rule hole-parameter
      (seq
        (optional (ref hole-kind))
        (choice (token "\$") (token "@"))
        (ref identifier)))

    (rule using-list
      (choice
        (seq
          (token "\$")
          (ref identifier)
          (repeat 0 (seq (token ",") (token "\$") (ref identifier))))
        (seq
          (ref identifier)
          (repeat 0 (seq (token ",") (ref identifier))))))

    (rule macro-body
      (external "body selected by result/target kind; contract M2"))

    (rule macro-call
      (seq (ref macro-name) (token "(") (ref macro-arguments) (token ")")))

    (rule local-macro-call
      (seq (ref identifier) (token "(") (ref macro-arguments) (token ")")))

    (rule meta-call
      (seq
        (ref macro-name)
        (token "(")
        (optional
          (seq
            (ref meta-argument)
            (repeat 0 (seq (token ",") (ref meta-argument)))))
        (token ")")))

    (rule meta-argument (choice (ref assignment) (ref meta-value-hole)))

    (rule meta-value-hole
      (external "whole template hole passed as a value, under M5"))

    (rule macro-arguments
      (external "signature-directed argument sequence; contract M1"))

    (rule decorator
      (external "visible decorator invocation followed by its target; M3"))

    (rule quotation
      (seq
        (token "\$")
        (token "!")
        (choice
          (seq (token "(") (ref expression) (token ")"))
          (seq
            (optional (ref quotation-kind))
            (token "{")
            (ref quotation-items)
            (token "}"))
          (seq
            (ref quotation-type)
            (token "{")
            (ref expression)
            (token "}")))))

    (rule quotation-kind
      (choice (ref result-kind) (token "Type") (token "Param")))

    (rule quotation-type
      (external "type operand or computed type under M4"))

    (rule quotation-items
      (external "contents selected by quotation kind, with \${expr} and @{expr} holes; M4"))

    (rule result-kind
      (choice
        (token "Expr")
        (token "Expression")
        (token "Stmt")
        (token "Field")
        (token "Entry")
        (token "Enumerator")
        (token "Unit")
        (token "Declaration")
        (token "Decorator")))

    (rule hole-kind
      (choice
        (token "Expr")
        (token "Expression")
        (token "Stmt")
        (token "Field")
        (token "Entry")
        (token "Enumerator")
        (token "Unit")
        (token "Function")
        (token "NamedType")
        (token "Type")
        (token "Decl")
        (token "DeclaratorRow")
        (token "Name")
        (token "Literal")
        (token "Param")
        (token "Catch")
        (token "Captures")
        (token "MatchRow")))

    (rule expression-slot (external "expression slot under M5"))

    (rule argument-slot
      (external "argument sequence slot: @name, @call(...), or @(form); M5"))

    (rule declarator-row-slot (external "declarator row slot under M5"))

    (rule named-type-slot (external "named type slot under M5"))

    (rule type-slot (external "type slot under M5"))

    (rule name-slot (external "name slot under M5"))

    (rule parameter-slot (external "parameter slot under M5"))

    (rule captures-slot (external "capture slot under M5"))

    (rule catch-slot (external "catch-arm slot under M5"))

    (rule match-row-slot (external "match-row slot under M5"))

    (rule unit-macro (external "unit-position macro/slot under M1-M5"))

    (rule block-extension
      (external "block-position macro/slot under M1-M5"))

    (rule statement-macro
      (external "statement-position macro/slot under M1-M5"))

    (rule field-extension
      (external "field-position macro/slot under M1-M5"))

    (rule enumerator-extension
      (external "enumerator-position macro/slot under M1-M5"))

    (rule entry-extension
      (external "map-entry-position macro/slot under M1-M5"))

    (rule lisp-escape
      (seq (token "\$(") (repeat 0 (ref lisp-form)) (token ")")))

    (rule lisp-form
      (choice
        (ref lisp-atom)
        (seq (token "(") (repeat 0 (ref lisp-form)) (token ")"))
        (seq (ref reader-prefix) (ref lisp-form))
        (ref lisp-hole)))

    (rule lisp-atom
      (choice
        (ref integer)
        (ref floating)
        (ref c-string)
        (ref symbol)
        (ref lisp-identifier)))

    (rule lisp-hole (external "template hole in compiler Lisp; M5"))

    (rule lisp-identifier (external "ident token in Lisp mode"))

    (rule identifier
      (external "identifier accepted in the current name position; D1"))

    (rule integer (external "lit-int"))

    (rule floating (external "lit-float"))

    (rule character (external "lit-char"))

    (rule c-string (external "lit-char*"))

    (rule symbol (external "lit-symbol"))

    (rule atom (external "lit-atom"))

    (rule string-segment (external "segment"))

    (rule directive
      (external "preproc token retained/selected by preprocessing; G1"))));
