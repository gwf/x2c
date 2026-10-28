# AST grammar

This chapter describes the compiler's canonical List structures. Use it to read
a literal AST construction, a structural pattern, or an AST dump. The
[source grammar](../reference/syntax/grammar.md) describes tokens; this
chapter describes the values those tokens become.

The reference was reconciled against revision
`ff3aba2aac3d58a31db6fd53b5cfaeeef230b695`. Source links select that revision.
The structures describe current implementation contracts, not a promise that
internal representations remain compatible between compiler versions. Language
meaning remains in the [language reference](../reference/language.md).

## Representation and notation

An AST is an immutable `List`. Most nodes start with a Symbol discriminant,
such as `expr`, `op`, or `declare`. Some intermediate forms have String heads,
such as `"x2c.quoted"`. Quotes in the grammar distinguish Strings from Symbols.
`0` is an integer. Upper-case words name fields or productions; they are not
literal leaves.

Inside the `text` grammar blocks, `|` selects alternatives, `[...]` marks an
optional field, and `X*` repeats a field zero or more times. Parentheses always
describe an actual List. Thus `(args EXPR*)` contains an `args` head followed
by expression children; `(ROW*)` is an untagged List of rows. These repetition
marks are grammar notation, not Match pattern syntax.

`()` is the empty List, represented by `NULL`. Depending on its field, it means
absence, an empty sequence, an unspecified type, or an empty operand. It is
distinct from `(nil)`, the AST content that produces a null List value, and
from a `Var` holding `void`. Do not assign one meaning to every empty List
without reading its enclosing production.

`EXPR` means a typed expression shell. `TYPE` means a semantic Type List;
`BASE` means declaration specifier syntax. `NODE` means syntax appropriate to
its position and stage. `VALUE` means an ordinary Var value; it need not be
syntax. A `BINDING` is the identity record defined below. Source-location,
macro-context, and registry data are named separately from program syntax.

A field corresponding to source syntax may already contain derived types,
converted operands, generated declarations, and binding identities. Its source
origin does not make every descendant source-written. Conversely, constructed
Lists use the same structural contracts as parsed source.

### Stages and positions

- **Parsing/template:** nodes can contain unresolved names, holes, deferred
  types, or pending applications.
- **Bound:** names and expression types have been resolved in compiler state.
  `--dump-ast` shows this stage after expansion, not an untouched parse tree.
- **Lowering/generation:** transforms replace extensions and add helper,
  initialization, and cleanup forms. `--dump-transforms` shows lowered code.
- **Emission:** the emitter consumes normalized forms, native fragments,
  and output decorations, then produces flat C tokens.

The constructed-syntax positions are `unit`, `block`, `field`, `enumerator`,
`map-entry`, `statement`, and `expression`. A block position permits block-item
declarations; a governed statement position requires one statement. A node's
layout alone does not establish valid placement, binding, or type.
[Compiler.bind_syntax][binding] and its `_bind_form` dispatch own placement;
ordinary declaration, expression, and statement operations own meaning.
Existing types and bindings are trusted, not reconstructed by a second
validator. See [Macro-visible
syntax](../reference/language.md#macro-visible-syntax).

During source control-flow parsing only, `Compiler.source_clause` supplies
Token values for deferred clauses: `test`, `then`, `else`, `body`, `do`,
`init`, `cond`, `next`, `arms`, `arm`, `try`, `catches`, `catch`, and
`finally`. These are addresses into a private parser table. They are transient
leaves consumed during binding, not List productions or constructible holes.

## Roots, wrappers, and identities

```text
UNIT        ::= (UNIT-ITEM*)
ORIGIN      ::= (at ORIGIN-ID NODE) | (at m-origin NODE)
SOURCE      ::= (src (source FILE BEGIN-OFFSET END-OFFSET) NODE)
API-SOURCE  ::= (api-source LINE DOC NODE)
BINDING     ::= (binding POSITIVE-ID SPELLING)
NAME        ::= SPELLING | (SPELLING) | BINDING
              | (binding-name SPELLING) | (binding-global SPELLING)
              | ("x2c.ident" SPELLING) | NAME-SLOT
METHOD-NAME ::= ((METHOD-OWNER) METHOD-MEMBER)
              | (SOURCE METHOD-MEMBER) | ((construct SOURCE) METHOD-MEMBER)
METHOD-OWNER ::= SPELLING | TYPE-WORD | (SPELLING) | TYPE-SLOT
METHOD-MEMBER ::= SPELLING | NAME-SLOT
CONSTRUCTION-NAME ::= ((construct SOURCE) SPELLING)
TAG-NAME    ::= NAME | () | (gensym ROLE GENERATED-SPELLING)
```

`SPELLING`, file paths, and documentation are Strings. `POSITIVE-ID` is a
compiler-issued integer, not an argument number or a source name. Equal
spellings in different scopes can have different identities. Generated names
can replace the spelling; compiler facts retain a separate source spelling. Do
not forge identities. `Code.binding_spelling` reads their text.

`binding-name` retains a reference by spelling in a Macro value so it resolves
where applied. `binding-global` retains an explicitly selected file-scope
reference. `"x2c.ident"` requests a spelling that binds where syntax lands. A
member name is normally `(SPELLING)`, not a variable BINDING. A Unit-target
construction can temporarily attach `(construct SOURCE)` to a requested name;
the declarator owner interprets that requirement rather than treating the
captured source as a concrete method owner. Method names have the separate
owner/member shape before declaration binding.

`at` retains a compiler-owned origin index; `m-origin` is an unresolved anchor
in template syntax. `src` retains exact capture offsets. `api-source` attaches
declaration line/documentation at unit position. The origin table uses `(source
FILE LINE COLUMN LENGTH OFFSET)` records with five payload fields. These are
metadata, distinct from the three-payload-field `src` source record.

Owners: [Ast.binding, Ast.without_origin, Ast.rewrap_origin][ast];
[_resolve_identifier and _identifier_binding][identifiers];
[_macro_value_names][macro-values]; [Compiler.bind_syntax][binding];
[_bind_api_source][units];
[x2c_ident and Code.binding_spelling][sdk-syntax];
[_method_spelling][declarators].
Consumers preserve identity across expressions, declarations, transformations,
and emission. The [AST API](compiler-api/ast.md) documents shared operations.

## Expressions

### Shells, identifiers, and atomic values

```text
EXPR       ::= (expr TYPE CONTENT)
             | (expr () CONTENT)
             | (expr (<macro-expr>) CONTENT)
CONTENT    ::= IDENT | LITERAL | OPERATOR | CALL | ACCESS | GROUPING
             | SELECTION | COLLECTION | INITIALIZER | STRING-CONTENT
             | LIST-CONTENT | LAMBDA | ADAPTATION | PENDING
             | BINDING | EXPR | ORIGIN | SOURCE | NATIVE-CONTENT
IDENT      ::= (ident NAME)
LITERAL    ::= (literal TYPE TEXT) | (literal TYPE TEXT ATOM-VALUE)
             | (literal ("Atom") TEXT (!quote BINDER-ATOM))
```

`()` means unresolved or native/unknown type in an expression shell;
`(<macro-expr>)` means resolution must wait for template substitution. Neither
is the void type `(void)`. A resolved shell retains a semantic TYPE. Nested
`expr` shells and bare BINDING content are accepted intermediate structures;
the resolver can unwrap or resolve them.

`TEXT` is a String. Numeric and C string literal text retains its spelling;
percent String text is decoded. Symbol and Atom literals can also retain an
actual Symbol/Atom value in the third field. Generated literals use the same
layout. `Var` absence uses `(literal ("Var") "void")`.

Owners: [Compiler.parse_atomic_literal, _symbol_literal, _atom_literal][atoms]
produce literals; [Compiler.parse_variable][expression-syntax] produces names;
[Compiler.resolve_expression, _content][resolution] resolve shells and content;
[_literal][emit-expressions] emits values. The contents below are children of
`expr` unless a containing production explicitly accepts bare content.

### Operators, calls, and access

```text
OPERATOR   ::= (op UNARY-OP EXPR)
             | (op BINARY-OP EXPR EXPR)
             | (op ? CONDITION TRUE-EXPR FALSE-EXPR)
             | (op . EXPR MEMBER) | (op -> EXPR MEMBER)
             | (postfix ++ EXPR) | (postfix -- EXPR)
MEMBER     ::= (SPELLING) | (MEMBER-SLOT)
CALL       ::= (call EXPR ARGUMENTS) | (call C-CALLEE ARGUMENTS)
ARGUMENTS  ::= (args CALL-ARG*)
CALL-ARG   ::= EXPR | DECL | ARGUMENT-SLOT
ACCESS     ::= (index EXPR EXPR) | (getindex EXPR EXPR)
             | (slice EXPR BOUND BOUND BOUND)
BOUND      ::= EXPR | ()
```

`C-CALLEE` is a raw String naming a generated/native callee. The source
argument order remains the order of `args`. A source call with no arguments
initially has `(args (expr (void) ()))`; generated calls can use `(args)`. The
empty void expression is a call convention, not a general absent argument.

`index` is parsed bracket access. `getindex` is the resolver's ordinary
indexing form after receiver-specific selection. Slice fields are receiver,
start, stop, and step; each omitted bound remains `()`.

The `op` field is an operator Symbol, not a separate node type for each
punctuation spelling. Member operators put a name List in the final field, not
a typed variable reference. The ternary `?` is literal punctuation here; in a
Match pattern it must be treated according to Match's quoting rules. The
[source grammar](../reference/syntax/grammar.md#e2-precedence) and
[operator ledger][operators] own the operator inventory and precedence.

Owners: [_parse_postfix_apply, _parse_postfix_index,
_parse_slice][expression-syntax];
[_operator][resolution]; [_getindex and _slice][access];
[_resolve_indexed, _getindex_expression][access]; [_call][calls].
The [bracket-access component][bracket-component] selects receiver policy;
[_emit][emit-dispatch] dispatches to
[_binary, _unary, _call][emit-expressions] for normalized forms.

### Grouping, type operands, and selection

```text
GROUPING   ::= (parens EXPR) | (parens BLOCK)
             | (sizeof SIZE-OPERAND)
             | (cast DECL EXPR) | (cast TYPE EXPR)
SIZE-OPERAND ::= EXPR | DECL | (parens EXPR) | (parens DECL)
               | NATIVE-SEQUENCE
SELECTION  ::= (generic EXPR ASSOCIATION*)
             | (va-arg EXPR DECL)
             | (offsetof TYPE MEMBER-TOKENS)
             | (is-type EXPR TYPE-SYNTAX)
             | (is-symbol EXPR EXPR) | (type-tag TYPE-SYNTAX)
ASSOCIATION ::= (association TYPE EXPR) | (association default EXPR)
MEMBER-TOKENS ::= (C-TOKEN-OR-EXPR*)
```

A statement expression retains `(parens (block ...))`; its final expression
statement supplies its type, otherwise it is void. A cast's first child is a
`decl` during binding and a semantic Type after normalization. Parentheses do
not permit a consumer to discard casts when extracting the original operand.

`offsetof` can retain a member designator such as `("field" "." "nested" "["
EXPR "]")`. `_Alignof` has no dedicated AST head: it uses `(expr ("size_t")
(call "_Alignof" (args OPERAND)))`, where OPERAND is a declaration or
expression.

Owners: [_parse_sizeof, _parse_generic, _parse_va_arg, _parse_offsetof,
_parse_type_test][expression-syntax]; [_statement_expression, _cast, _sizeof,
_generic, _va_arg, _is_type, _is_symbol][resolution];
[Compiler.var_tag_expression][resolution]. Normalized casts, generic
rows, type operands, and member tokens pass to [emission][emit-dispatch]. See
[types and conversions](../reference/language.md#types-and-conversions).

### Collections, List construction, and String segments

```text
COLLECTION ::= (array EXPR*) | (map MAP-ROW*)
MAP-ROW    ::= (map-entry EXPR EXPR) | MAP-ENTRY-SLOT
LIST-CONTENT ::= (nil) | (cons EXPR EXPR) | (append EXPR EXPR)
               | (splice EXPR) | (var EXPR) | (cache CACHE-ID)
STRING-CONTENT ::= (segments SEGMENT*) | (0)
SEGMENT    ::= (segvar EXPR) | (segexp EXPR) | (cache CACHE-ID)
             | (segraw TEXT)
```

A call-site rest splice uses `(expr ("List") (splice EXPR))`. Ordinary
List-valued arguments retain their expression form and contribute one value.
Dynamic-call extraction represents a splice as `(func-splice EXPR)` alongside
ordinary `(func-arg VALUE ADDRESS SOURCE)` rows.

Map rows contain key then value; they are not argument Lists. `splice` retains
a value that contributes a sequence. `cons` and `append` express runtime List
construction; immutable portions can instead become cache references. `var` is
boxing/cache support, not a source keyword.

An empty percent String is `(expr ("String") (0))`, whose content has an
integer head. Ordinary String segments are `segvar` for `$name`, `segexp` for a
braced expression, and cached text. The interpolation component also accepts
`segraw` text; no current parser producer emits that form.

Owners: [Compiler.parse_list_literal, Compiler.literal_cell][quotation-reader];
[collection literal parsing][collection-reader];
[Compiler.parse_string_literal, _parse_text_segment][string-reader];
[_array_value, _map_value, Compiler.resolve_map_entry, _segments][resolution];
[collection lowering][collection-component] and
[interpolation lowering][interpolation-component].
[Compiler.cache_cons_cell and Compiler.cache_literal_var][literal-cache]
produce cache references. Cache payloads are documented below separately.

### Initializers and destructuring

```text
INITIALIZER ::= (composite (commas INIT-ITEM*))
              | (dotinit MEMBER INIT-ITEM) | (indexinit EXPR INIT-ITEM)
              | (commas EXPR*)
              | (dstrasgn (targets EXPR*) EXPR)
INIT-ITEM  ::= EXPR | INITIALIZER
```

Designators can nest, preserving the selected field/index at each step.
`composite` remains an initializer until destination conversion determines its
meaning. A destructuring assignment has its targets first and source expression
second. The declaration variants are defined under declarations.

Owners: [_parse_composite, _parse_designated_init,
_parse_assignment_tail][expression-syntax];
[_resolve_initializer, _composite, _destructure][resolution];
[Compiler.convert_initializer][initializer-conversion] and the
[destructuring component][destructuring-component]. Native-dependent
`initval` alternatives are internal conversion forms, defined below.

### Lambdas and typed adaptation

```text
LAMBDA     ::= (lambda (params LAMBDA-PARAM*) LAMBDA-BODY)
             | (lambda (params LAMBDA-PARAM*)
                 (captures CAPTURE*) LAMBDA-BODY)
LAMBDA-PARAM ::= BINDING | PARAM
LAMBDA-BODY ::= EXPR | BLOCK | BODY-SLOT
CAPTURE    ::= (capture CAPTURE-TARGET TYPE EXPR)
CAPTURE-TARGET ::= BINDING | SPELLING | NAME-SLOT
ADAPTATION ::= (tadapt TARGET-EXPR SOURCE-EXPR)
             | (tadapt ORIGIN-ID SOURCE-EXPR)
```

Bare lambda parameters initially contain just bindings; lambda binding supplies
their types. Empty lambdas can have `(params)`. Capture rows retain the target
binding, stored type, and value expression. Reference captures store the
address expression and its reference type. Supplied template capture targets
can still be spellings or slots before binding.

The two `tadapt` layouts belong to different stages. Resolution consumes a
target typedef expression and produces `(expr TARGET (tadapt ORIGIN SOURCE))`.
The callback lowerer consumes that resolved form. A memo key with the same head
is not an adaptation expression.

Owners: [Compiler.parse_lambda_literal, Compiler.bind_lambda_expression,
_prescribe][lambdas]; [lambda lowering][lambda-component];
[_tadapt][resolution]; [Compiler.lower_typed_adapter_expr][callbacks].
See [lambdas](../reference/language.md#lambdas).

## Declarations, declarators, and types

### Declaration forms

```text
DECLARATION ::= (declare BASE BINDINGS) | (typedef BASE BINDINGS)
              | DECL | FUNCTION | (falias DECLARATION NAME)
              | (named-type SPELLING TYPE-SYNTAX)
              | (named-type SPELLING ())
DECL        ::= (decl BASE BINDINGS)
BINDINGS    ::= (bindings DECLARATOR-ROW*)
DECLARATOR-ROW ::= DECLARATOR | (op = DECLARATOR EXPR)
                 | DECLARATOR-ROW-SLOT | (op = DECLARATOR-ROW-SLOT EXPR)
DECLARATOR  ::= (bind DECLARATOR-NAME MODIFIERS)
DECLARATOR-NAME ::= NAME | METHOD-NAME | ()
FUNCTION    ::= (function BASE DECLARATOR FUNCTION-BODY)
FUNCTION-BODY ::= BLOCK | (seq) | BODY-SLOT
DSTR-DECL   ::= (dstrdecl BASE (targets NAME*) EXPR)
              | (dstrdecl (params PARAM*) EXPR)
```

Unit and block declarations, aggregate fields, and expression type operands
share declarator syntax but have different placement rules. Functions and
foreign aliases bind at unit position. Destructuring declarations bind at block
position. `decl` is an abstract/type or header declaration without a statement
semicolon; it is not interchangeable with `declare` in every position.
`named-type` is a unit form consumed into ordinary type declarations. An empty
name in `bind` retains an abstract or unnamed declarator.

`falias` couples an ordinary declaration with its native target binding;
emission writes the native alias using the existing type contract. Generation
can also produce `(declare BASE DECLARATOR)` for one prototype, without the
usual `bindings` wrapper. That is an emission form, not an additional
constructed-source declaration shape.

Owners: [_bind_declaration, _finish_declaration, _bind_targets,
_bind_typed_targets][declarations];
[_bind_function and function-body parsing][functions];
[named-type binding][type-parser]; [_prototype][generation-projection];
[_declare, _function, _foreign_alias][emit-declarations];
[Compiler.enclosing and _ancestor_code][placement-owner].

### Modifiers and parameters

```text
MODIFIERS  ::= (MODIFIER-PART*)
MODIFIER-PART ::= MODIFIER | FUNCTION-SUFFIX
FUNCTION-SUFFIX ::= fnmod PARAMETERS MODIFIERS
MODIFIER   ::= * | & | opt-ref | ^ | QUALIFIER
             | (dim) | (dim EXPR) | (bitfield EXPR)
             | (fnmod PARAMETERS) | (fnmod PARAMETERS MODIFIERS)
             | (ATTRIBUTE-TEXT)
PARAMETERS ::= (params PARAM*)
PARAM      ::= (param BASE DECLARATOR) | (...) | PARAM-SLOT
QUALIFIER  ::= const | volatile | restrict
```

Modifier order states declarator nesting. A function suffix following other
suffixes can splice `fnmod PARAMETERS MODIFIERS` into the enclosing modifier
sequence without an extra List shell. Therefore a modifier sequence is not
always a flat List of individually tagged modifier entries. The attribute form
contains a String of native attribute text. `dim` without an operand retains an
unspecified array bound. `^` is consumed by the pointer parser as well as
internal Type operations; that acceptance alone does not promise native
compiler compatibility for a caret declarator.

A C no-argument parameter list is explicitly `(params (param (void) (bind ()
())))`. Do not replace it with `(params)` solely because lambdas and calls
permit empty parameter/argument sequences.

A rest parameter `List @NAME` or `Map @NAME` uses
`(param (.... CONTAINER) (bind NAME ()))`, where CONTAINER is `"List"` or
`"Map"`. Its semantic parameter Type `(.... CONTAINER)` is one marker, not a
modifier on CONTAINER, and is distinct from `(CONTAINER)`; its bound local and
emitted native parameter are ordinary CONTAINER values. A `key: value` call
argument is `(expr ("Map") (map-entry KEY VALUE))`. The final position in the
parameter sequence owns the rest convention.

Owners: [_declarator, _declarator_suffix, _array_suffix,
Compiler.parse_parameter][declarators]; [List.type_from_ast][compiler-type];
[_declarator and _parameters][emit-declarations]. Runtime
[Type operations][runtime-type] interpret semantic modifier order.

### Source types and semantic Types

```text
TYPE-SYNTAX ::= BASE
BASE       ::= (SOURCE-PREFIX* SOURCE-TAIL)
SOURCE-PREFIX ::= QUALIFIER | STORAGE | inline | meta | MODIFIER
                 | (NATIVE-TEXT)
SOURCE-TAIL ::= TYPE-WORD+ | SPELLING | TYPE-SLOT
               | struct TAG-NAME [FIELDS] | union TAG-NAME [FIELDS]
               | struct FIELDS | union FIELDS
               | enum TAG-NAME [ENUMERATORS] | enum ENUMERATORS
FIELDS     ::= (fields FIELD-ITEM*)
ENUMERATORS ::= (ENUMERATOR*)
ENUMERATOR ::= NAME | DECLARATOR | (op = NAME EXPR)
             | (op = DECLARATOR EXPR) | ENUMERATOR-SLOT
TYPE       ::= (SEMANTIC-PREFIX* SEMANTIC-TAIL) | UNQUAL-TYPE
             | (<macro-expr>) | (.... "List") | (.... "Map")
SEMANTIC-PREFIX ::= QUALIFIER | STORAGE | inline | meta
                   | SEMANTIC-MODIFIER | (NATIVE-TEXT)
SEMANTIC-TAIL ::= TYPE-WORD+ | SPELLING | struct TAG-NAME
                 | union TAG-NAME | struct (TYPE*) | union (TYPE*)
                 | enum TAG-NAME [ENUMERATORS] | enum ENUMERATORS
                 | NATIVE-TEXT (parens NODE)
SEMANTIC-MODIFIER ::= * | & | opt-ref | ^ | (dim) | (dim EXPR)
                    | (bitfield EXPR) | (func (TYPE*))
UNQUAL-TYPE ::= (unqual SEMANTIC-PREFIX* SEMANTIC-TAIL)
```

A tail expands in place, without adding a List shell. For example, `(static
struct "Pair" (fields ...))` and `(* struct "Pair")` have `struct` in the
containing type List, not inside an extra aggregate child. `X+` means one or
more occurrences.

`TYPE-WORD` covers the existing scalar specifiers, including `void`, `char`,
`short`, `int`, `long`, `signed`, `unsigned`, `float`, and `double`. `STORAGE`
covers `typedef`, `static`, `auto`, `extern`, `register`, and `threaded`. These
are components, not independent tagged program nodes. Fields can include
declarations, static assertions, and category expansions at the ordinary field
parser's positions. Preprocessor groups retain their existing governed
structure.

There is no `(type ...)` wrapper. Semantic Types flatten declaration base and
declarator modifiers. A semantic function type such as `((func ((int) (*
char))) void)` has two parameter Types and a void result; source `fnmod`
retains parameter declarations instead. Named aggregate conversion retains tag
identity, while anonymous semantic bodies contain Types rather than source
`fields` declarations.

Generated native fragments can occur as a complete type sequence, for example
`("__typeof__" (parens TARGET))`. `unqual` projects an unqualified value type
for inferred declarations and is also recognized by emission. Native fragments
do not introduce new language type syntax.

Owners: [_tagged_type, _finish_type, enumerator binding][type-parser];
[List.type_from_ast, Type.parts, Type.declaration_ast,
Type.parameter_ast][compiler-type];
[type_declaration_parts][declaration-parts];
[Type.function_parts and structural Type operations][runtime-type];
[Compiler.convert_initializer][initializer-conversion];
[_semantic_type, _aggregate, _enum][emit-declarations].
Use these owners for conversion rather than reconstructing type precedence.

## Statements and control flow

### Ordinary statements and sequences

```text
BLOCK      ::= (block BLOCK-ITEM*)
BLOCK-ITEM ::= DECLARATION | DSTR-DECL | STATEMENT | ORIGIN | PENDING
              | PREPROCESSOR
STATEMENT  ::= BLOCK | ORIGIN | SOURCE | PENDING | (stmnt EXPR) | (empty)
             | (group NODE*) | (seq NODE*)
             | (return) | (return TYPE EXPR) | (return EXPR)
             | (if EXPR STATEMENT) | (if EXPR STATEMENT STATEMENT)
             | (while EXPR STATEMENT) | (do STATEMENT EXPR)
             | (for FOR-INIT OPTIONAL-EXPR OPTIONAL-EXPR STATEMENT)
             | (switch EXPR STATEMENT) | (case EXPR) | (default)
             | (break) | (continue) | (goto NAME) | (label NAME)
             | (defer STATEMENT) | RAISE | TRY | MATCH
FOR-INIT   ::= DECL | DECLARATION | EXPR | ()
OPTIONAL-EXPR ::= EXPR | ()
PREPROCESSOR ::= (preproc TEXT)
```

`block` introduces braces/scope; `group` retains governed preprocessor
structure without adding braces. `seq` splices syntax items at unit/block
boundaries. It is consumed there during binding/lowering, not emitted as a
special C statement. A sequence is not automatically legal as one governed
statement.

`(return)` has no value. Bound value returns retain the function's target TYPE,
as `(return TYPE EXPR)`; lowering converts the operand and removes that field,
yielding `(return EXPR)`. The same head therefore has three legal layouts. At
emission only, `stmnt` may also wrap lowered statement content, such as `(stmnt
(return EXPR))` from a generated callable helper; the emitter appends a
semicolon.

Owners: [Compiler.finish_return_statement, Compiler.parse_governed,
_block_items, _goto_statement][statements]; [_bind_form and control
binders][binding];
[_return][transform-expressions]; [_sequence_tail][transform-traversal];
[_rewrite and transfer lowering][cleanup-transfers];
[_emit and _leaf][emit-dispatch]. The [source-form helpers][grammar-owner]
name selected layouts for construction and recognition, not the whole grammar.

### Match, raise, and catch rows

```text
RAISE      ::= (raise EXPR (args DETAIL-EXPR*))
TRY        ::= (try STATEMENT CATCHES-OR-EMPTY FINALIZER-OR-EMPTY)
CATCHES-OR-EMPTY ::= () | (catchcases (CATCH-ROW*) BINDING)
CATCH-ROW  ::= (PATTERN-EXPR STATEMENT) | (() STATEMENT) | CATCH-SLOT
FINALIZER-OR-EMPTY ::= STATEMENT | ()
MATCH      ::= (match EXPR (MATCH-ROW*))
MATCH-ROW  ::= (PATTERN-EXPR ARM-BODY) | ((*) ARM-BODY)
             | PREPROCESSOR | MATCH-ROW-SLOT
ARM-BODY   ::= STATEMENT | (guarded STATEMENT)
PATTERN-TEST ::= (expr () (matches EXPR PATTERN-EXPR TYPED-CAPTURES))
              | (expr (int) (matches EXPR PATTERN-EXPR BLOCK VISIBLE-BINDINGS))
MATCH-IF   ::= (match-if EXPR (PATTERN-EXPR STATEMENT))
```

Raise arguments alternate detail-key expressions and value expressions. A
catch's default pattern is `()`; a match default is the raw List `(*)`. Other
patterns are expressions producing Match data. Pattern operators and capture
binders inside that data are not additional AST node kinds.

`catchcases` retains the generated handler binding after its ordered arm List.
Match rows can interleave preprocessor directives. Guards initially become an
`if` whose successful block ends with `break`; typed captures can wrap this
with declarations before `(guarded STATEMENT)` is applied. Therefore `guarded`
does not require an immediate `if` child. Match and catch bodies can already
contain generated capture declarations at the bound stage.

`~=` parses as `matches` expression content. Binding replaces its typed
capture descriptions with capture declarations and `(BINDING TYPE)` rows.
The rows expose the existing identities only to successful continuations.
Positive `&&` and `if` lower to nested conditions. Their internal `match-if`
uses ordinary match tests without a switch or implicit break. A predicate
used as a value wraps those conditions in a statement expression returning
an `int`. Constructed `(expr () (op ~= EXPR PATTERN-EXPR))` also enters the
same pattern binder.

Owners: [_raise_statement, _catch_cases, _match_cases,
Compiler.parse_case_body][statements]; [_bind_catchcases, _bind_try,
_bind_match][binding]; [try lowering][try-component];
[match lowering][match-component]; [raise lowering][raise-component].
Cleanup consumes landing/defer forms below; the emitter handles surviving
`raise` nodes. See [Match](../reference/language.md#match) and
[Errors and cleanup](../reference/language.md#errors-and-cleanup).

## Compile-time and intermediate forms

These values explain literal Lists in compiler and runtime source. Their
presence here does not make every carrier available at source unit position.

### Pending applications and captures

```text
PENDING    ::= (macro-invoke DEFINITION-REF INVOCATION-INPUT SITE)
             | (macro-slot SPLICE-FLAG META-EXPR)
             | (macro-slot SPLICE-FLAG META-EXPR SLOT-CONTEXT*)
             | (macro-bind PROJECTION-ATOM)
             | (meta-call EXPR ARGUMENTS)
             | (meta-cap PROJECTION-ATOM) | (meta-cap (PROJECTION-ATOM))
             | (tpl-call DEFINITION-OR-EXPR ARGUMENTS)
             | (macro-value MACRO-DEFINITION)
DEFINITION-REF ::= MACRO-DEFINITION | NAME-ATOM
                 | (!quote MACRO-DEFINITION) | (local-macro NAME-ATOM)
INVOCATION-INPUT ::= (args INVOCATION-CAPTURE* [FRESH-INPUT])
                   | (target (args INVOCATION-CAPTURE*)
                       INVOCATION-CAPTURE [FRESH-INPUT])
FRESH-INPUT ::= (fresh INVOCATION-CAPTURE*)
INVOCATION-CAPTURE ::= (capture (source VALUE) (value VALUE)
                         (expression VALUE) (splice VALUE*) REQUIREMENT*)
                     | (capture (source VALUE*) (value VALUE*) REQUIREMENT*)
SITE       ::= TOKEN | m-invoke
SLOT-CONTEXT ::= (construct VALUE) | (target VALUE)
```

The first capture alternative is scalar; the second is a sequence capture.
These assoc-row capture records differ from lambda captures. `META-EXPR` is
a meta-expression List. `SPLICE-FLAG` states scalar versus sequence insertion.
The parser produces the three-element slot without trailing context rows.
The consumer also accepts the displayed SLOT-CONTEXT rows in constructed
slots; no current slot parser produces those rows.

`REQUIREMENT` is a construction-projection binder or `(construct SOURCE)`
record attached to Unit-target capture rows, not another operand of the
source expression. Unit invocation captures still produce these requirements.

Projection atoms identify a hole and one of its source/value/expression/splice
views. `meta-cap` can hold the atom directly or inside a List, depending on
whether the containing List itself is the required value. A template call can
name a stored definition or carry a callee expression. Within a template, a
pending invocation can retain its descriptor as `(!quote MACRO-DEFINITION)`;
that quotes the descriptor data, not its resulting program syntax. These forms are consumed
or retained according to template stage, not emitted as C calls.

Owners: [_invocation_node and _stored_reference][invocation-targets];
[_parse_meta_call, _meta_argument, _expression_invocation,
_template_call][invocation-expressions];
[_scalar_row, _sequence_row, _forwarded_capture][invocation-captures];
[Compiler.try_parse_macro_slot][macro-slots];
[Compiler.expand_macro_invocation_node and _bind_expansion][expansion];
[expression resolution][resolution] and
[Compiler.meta_argument][stage-owner] consume meta projections and calls.

### String-headed syntax values and quotation

```text
APPLICATION ::= ("x2c.template" MACRO-DEFINITION (VALUE*))
QUOTED      ::= ("x2c.quoted" . NODE)
              | ("x2c.quoted" (QUOTED-FRESH-ROW*) NODE)
QUOTED-HOLE ::= ("x2c.hole" REDUCED-HOLE PROJECTION VALUE)
REDUCED-HOLE ::= (macro-param (kind HOLE-KIND) (sequence FLAG))
QUOTED-ANCHOR ::= ("x2c.at" NODE)
IDENTIFIER-VALUE ::= ("x2c.ident" SPELLING)
QUOTED-FRESH-ROW ::= (BINDER SPELLING FILE-LINKAGE-FLAG)
PROJECTION ::= source | value | expression | splice | member | shell
```

In the completed form, `. NODE` denotes the tail itself: cons the String tag
onto the canonical node. Constant quotations can share the literal cache's
node and carrier. The three-field form retains supplied values whose
projections, private names, or source information still use placement. Its
hole records do not represent arguments waiting to be supplied.

A NAME-SLOT, TYPE-SLOT, MEMBER-SLOT, BODY-SLOT, or category row slot in the
preceding productions is a `macro-bind` or `macro-slot` in that parser
position. A sequence projection can occupy a complete row/child sequence; it
does not change the enclosing production after expansion.

The application contains one grouped value per formal hole; a sequence formal's
remaining values occupy one List. A quotation holds its fresh-name rows and
syntax. A quotation fresh row marks whether a file-scope row declares the name
with linkage. Each reduced hole records kind and sequence status, without its
descriptor's `binder` row. `shell` denotes expression-shell insertion. Quoted
anchors acquire the landing context's origin as required; they are not verbatim
C text despite their String heads.

Owners: [Macro_apply and _group][macro-construction];
[_construction, _built_item, _built_hole][macro-quotations];
[Compiler.land_quotation, _fill_syntax, _splices, _project_hole,
_helper_result][macro-templates]. Runtime
[recognition][macro-recognition] and [pattern projection][macro-patterns]
handle these structures as well as bound AST names and expression shells.
See [quotation semantics](../reference/language.md#macro-visible-syntax).

### Macro definitions

```text
MACRO-DEFINITION ::= (macrodef DESCRIPTOR-ROW*)
DESCRIPTOR-ROW ::= (name NAME-ATOM) | (kind RESULT-KIND)
                 | (target TARGET-KIND-OR-ZERO) | (targetp HOLE-OR-EMPTY)
                 | (parameters (HOLE*)) | (fresh (TEMPLATE-FRESH-ROW*))
                 | (captures (BINDING*)) | (pattern MATCH-PATTERN)
                 | (template NODE) | (rebuild REBUILD-OR-EMPTY)
                 | (leaf FLAG) | (origin LOCATION) | (file PATH)
                 | (builtin FLAG) | (local FLAG) | (static FLAG)
                 | (env (ENV-ROW*))
HOLE       ::= (macro-param (binder BINDER) (kind HOLE-KIND) (sequence FLAG))
TEMPLATE-FRESH-ROW ::= (BINDER SPELLING META-READ-FLAG)
REBUILD-OR-EMPTY ::= () | (REBUILD-SYNTAX (REBUILD-KEY-ROW*))
REBUILD-KEY-ROW ::= (SOURCE-KEY VALUE-KEY EXPRESSION-KEY SPLICE-KEY
                    RETURN-KEY DECLARATOR-KEY)
ENV-ROW    ::= (IDENTITY VALUE)
```

The definition producer writes one of each descriptor row except `env`;
`Macro_close` can append the captured environment. Consumers use assoc lookup,
not the physical row order. Kind and target categories select ordinary
parser/binder positions. `FLAG` is an integer flag. A full fresh row's flag
marks meta-call name use; quotation construction derives the fresh rows
it needs for landing. Each rebuild key is a projection binder or the Symbol `?`
for an unused projection. Parameter rows precede the decorator target row.
Environment identities normally use `(binding-name SPELLING)`, preserving
references across translation contexts. Rebuild and environment rows are
descriptor data, not another program production.

Global definitions bind at unit position; local definitions bind in blocks.
`imported` is not a current produced descriptor row. The macro registry instead
has a separate `(imported-macro FROZEN-DEFINITION)` wrapper.

Owners: [_definition_node, _fresh_rows, _rebuild_template,
_rebuild_keys][macro-definitions]; [definition reading][macro-reading];
[Macro_close][macro-construction]; [_bind_macrodef][units].
The [source grammar](../reference/syntax/grammar.md#m1-arguments-and-positions)
owns category spellings; this chapter documents their stored forms.

### Code values and effects

```text
CODE-VALUE ::= (code-value STAGE CODE (EFFECT*))
STAGE      ::= "source" | "bound" | "lowered"
EFFECT     ::= (rewrite POINT KIND NAME SHAPE HOLES)
             | (new-name TOKEN ROLE-STRING) | (cleanup TOKEN PLACED-CODE)
```

Compile-time scalar results enter ordinary syntax through
[Compiler.lift_meta_expression and Compiler.bind_meta_statement][macro-templates].
A source carrier requires ordinary binding. A bound or lowered carrier retains
completed work. Effects apply in order within the macro application's
transaction; new-name and cleanup tokens are replaced in CODE. Effects are not
executable statements. A lowered carrier is not sent through a new binder
merely to establish a fact its producer already supplies.

Owners: [Code.bound and Code.lowered][sdk-syntax];
[Compiler.take_code_value, _code_effects, Compiler.bind_code_value][macro-values];
[Code constructors][meta-library]. These carriers are also consumed by the
REPL's compiler calls; they are not a separate REPL AST grammar.

### Retained declaration production

```text
DECLARATION-PRODUCTION ::= (declaration-bundle (rows NODE*))
                         | (syntax-recipe CALLBACK ARGUMENTS-VALUE)
                         | (declaration-recipe CALLBACK ARGUMENTS-VALUE)
                         | (default FUNCTION)
                         | (default-forward CHILD PARENT MEMBER FALLBACK*)
                         | (declaration-pending CALLBACK ARGUMENTS-VALUE
                             MACRO-STACK PRIVACY)
                         | (declaration-forward CHILD PARENT MEMBER
                             (FALLBACK*) PRIVACY)
                         | (declaration-default FUNCTION MACRO-STACK PRIVACY)
                         | (declaration-function DECLARATION BODY MACRO-STACK)
                         | (declaration-initialized DECLARATION MACRO-STACK)
```

Bundles, declaration recipes/defaults, and collected function/initializer
carriers are unit forms. `syntax-recipe` instead uses the caller's position.
Collected functions retain one declared function, its body, and the macro
context needed to bind it later. Collected initialized declarations likewise
retain that context. Defaults and forwarding candidates are selected by the
existing declaration owner before binding the selected bodies.
`ARGUMENTS-VALUE` is callback data, not necessarily an AST `args` node.

Owners: [_construct][expansion]; [_bind_bundle, _bind_recipe,
_bind_decl_recipe, _bind_default][units];
[collected function production][functions];
[collected initializer production][declarations];
[Compiler.select_declaration_defaults, _produce_rows, _select,
_forward][declaration-defaults];
[_retain_bundle and Compiler.replay_declaration_source][declaration-production].
See [named types and declaration
production](../reference/language.md#named-types-and-declaration-production).

### Imports, protocols, and static assertions

```text
IMPORT     ::= (import PACKAGE-STRING ALIAS-STRING)
ASSERTION  ::= (c-assert) | (c-assert EXPR EXPR)
PROTOCOL   ::= (protocol PROTOCOL-RECORD STORAGE-MODE LOCATION)
PROTOCOL-RECORD ::= ("protocol-record" BASE PARTICIPANT-STRING
                     (associated ASSOCIATED-ROW*) (members MEMBER-ROW*))
ASSOCIATED-ROW ::= (SPELLING TYPE)
MEMBER-ROW ::= (SPELLING SIGNATURE-TYPE NATIVE-NAME-OR-EMPTY)
ADOPTION   ::= (adopt BASE TYPE STORAGE-MODE LOCATION)
             | (adopt BASE TYPE STORAGE-MODE TYPE LOCATION)
             | (adopt BASE TYPE STORAGE-MODE (tag EXPR) LOCATION)
META-PROTOCOL ::= (meta-protocol ADOPTION) | (meta-protocol BASE TYPE)
STORAGE-MODE ::= external | static
```

Imports are parser-retained unit items; the alias defaults to the package name.
The constructed-syntax binder does not directly accept an `import` node; import
replay uses its owning effect path. Imported member selection is retained
separately, without extending the `import` node. `c-assert` with operands is
legal at unit, block, or field position; the empty form is a shallow-collection
marker without the discarded operands. Protocol and adoption forms are unit
items, with associated types and members held in ordered record rows. The
extended adoption adds a representation or a tag expression; the existing
protocol rules determine which applies.

Owners: [_parse_import_declaration][units]; [static assertions][declarations];
[_body, _parse_associated, _parse_member, _adoption][protocol-declarations];
[_adoption_node, Compiler.publish_protocol_node,
_retain_meta_protocol][protocol-registry]. See
[protocols](../guide/protocols.md).

## Lowered forms and emission

### Native-dependent initializer alternatives

```text
INITVAL    ::= (initval [(input INPUT-ROW*)] INITIALIZER-CHOICE*)
INPUT-ROW  ::= (FORMAL EXPR)
INITIALIZER-CHOICE ::= (CONDITION PATH DESTINATION-TYPE VALUE-EXPR)
CONDITION  ::= EXPR | ()
DESTINATION-TYPE ::= TYPE | ()
PATH       ::= (PATH-FRAME*)
PATH-FRAME ::= (OWNER-TYPE field FIELD-NAME SELECTED-TYPE FOLLOWING-FIELDS)
             | (OWNER-TYPE index INDEX-EXPR SELECTED-TYPE ())
FOLLOWING-FIELDS ::= (FIELD-FACT*)
FIELD-FACT ::= (FIELD-NAME FIELD-TYPE)
```

An `initval` is conversion content under an expression shell. Its optional
input header captures the source operands once for native alternatives. A
FORMAL can occur as a bare String expression content placeholder. An empty
condition is unconditional; an empty destination is an excess initializer
alternative. PATH is a stack of untagged frames, newest first; slot
construction visits it in reverse. Empty field names retain anonymous aggregate
members. These frames are not `(dotinit ...)`/`(indexinit ...)` selector ASTs.

Owners: [Compiler.initializer_rows, _field_path, _first_path, _designated_path,
Compiler.initializer_slot][initializer-subobjects];
[_materialize_mixed_row and Compiler.convert_initializer][initializer-conversion];
[_initval][resolution]; [Ast.initializer_cases and
Ast.initializer_functions][ast]; [_initializer_value][emit-initialization]. The
ordinary initializer owner supplies the destination choices. Consumers must not
infer a different path grammar from designator syntax.

### Cleanup, initialization, and generated markers

```text
LOWERED-NODE ::= (localinit STATIC-DECL BLOCK) | (sourceinit FUNCTION)
               | (initcode (input INPUT-ROW*) (NODE*))
               | (staticinit BINDING INITIALIZER-VALUE)
               | (defer STATEMENT ENVIRONMENT CALLBACK
                   (CAPTURE-RECORD*) (BINDING*))
               | (landing CODE (LANDING-ROW*))
               | (function BASE DECLARATOR BODY kernel)
               | (try STATEMENT () STATEMENT kernel)
STATIC-DECL ::= DECLARATION | (at ORIGIN-ID STATIC-DECL)
ENVIRONMENT ::= BINDING | ()
CALLBACK    ::= BINDING
CAPTURE-RECORD ::= (BINDING STORAGE-TYPE FIELD-BINDING)
LANDING-ROW ::= (new-name BINDER ROLE-STRING) | (outer BINDER NODE)
              | (exits BINDER CODE) | (region BINDER NODE)
```

The extended `defer` holds its callback environment, capture records, and
written bindings until cleanup places its calls on exits. The simple source
`defer` has only one body child. `localinit` owns a local static declaration
and the remaining block; `staticinit` wraps its initializer with a cleanup
binding. `sourceinit` retains a generated unit-initializer function. `initcode`
packages initializer input with its untagged statement sequence for a native
macro body. The declaration in `localinit` can retain origin wrappers, which
its emitter removes before reading the declarators.

A landing executes rows in order. `new-name` introduces a binding; `outer`
lowers in the enclosing context; `exits` supplies cleanup for subsequent
regions; `region` lowers its body within that cleanup context. Binder atoms are
temporary substitution keys, distinct from positive binding IDs. CODE can be
pending quotation/application syntax before cleanup binds it.

The literal `kernel` marker selects shipped rules for a generated function or a
fallback try region. The transform removes the marker before emission. It is
neither another body child nor a new source keyword.

Owners: [Compiler.rewrite_defer_list, Compiler.lower_defer_region,
_callable_defer, _landing_region][cleanup-defer];
[_static_regions, _static_initializers][cleanup-statics];
[_lower_defer, _lower_landing, _inside, Compiler.lower_cleanup][cleanup-transfers];
[_try_landing][try-component]; [_written_function][transform-traversal];
[source initialization and initializer assembly][cache-owner];
[_local_static, _static_binding, _source_initializer,
_initializer_macro][emit-initialization].

### Cache payloads and compatibility content

```text
CACHE-PAYLOAD ::= (string EXPR) | (var EXPR)
                | (cons CACHE-VALUE CACHE-VALUE) | (nil)
CACHE-VALUE   ::= (cache CACHE-ID) | CACHE-PAYLOAD | EXPR
COMPATIBILITY-CONTENT ::= (varray EXPR*) | (vmap MAP-ROW*)
```

`(cache ID)` is an AST reference into the current translation's literal cache.
Payloads are data owned by that cache; `string` is not a generic emitter
expression head. Cache keys can also retain expression forms and converted
values. Their meaning depends on the existing cache operation.

The transform still consumes `varray` and `vmap` as array/map compatibility
heads with unchanged children. There are no current literal constructors in the
surveyed compiler/runtime/tooling sources. In particular, `vmap` does not
establish a separate `vpair` row grammar.

Owners: [Compiler.cache, Compiler.cache_literal_var,
Compiler.cache_cons_cell][literal-cache]; [cache
assignment/materialization][cache-owner];
[_collection_literal][transform-literals] and
[_step_tag][transform-traversal].

### Native sequences, decorations, and output tokens

```text
NATIVE-CONTENT ::= NATIVE-TEXT | NATIVE-SEQUENCE | ()
NATIVE-SEQUENCE ::= (NATIVE-ELEMENT*)
NATIVE-ELEMENT ::= C-TOKEN | NODE
DECORATION ::= (comment TEXT*) | (space TEXT*)
SOURCE-MAP-OUTPUT ::= src-at ORIGIN-ID C-TOKEN* src-at PREVIOUS-ORIGIN-ID
```

Generated forms can mix raw String C text and typed nodes, rather than add an
AST tag for each C fragment. `_emit` handles these structures as follows:

1. An empty List emits nothing.
2. A List with a non-Symbol head enters `_sequence`. Each non-Symbol element
   is visited in order; List elements recurse and other leaves pass through.
   If the remaining tail begins with a Symbol, that tail is one node.
3. Storage, qualifier, and `inline` prefixes are emitted before the rest,
   except `typedef`, which has dedicated declaration handling. `threaded`
   becomes `_Thread_local`.
4. Known heads dispatch to their node operations. Unknown Symbol heads use
   `_leaf`'s generic rule: emit the head followed by its recursively emitted
   tail. This permits existing C-shaped generated fragments.

This fallback is part of the representation contract. A finite inventory of
named heads alone cannot describe every emitted fragment. It also does not make
an arbitrary List valid at a constructed-source position: the binder has its
own position contracts.

`comment` and `space` are presentation nodes. `preproc` retains source-order
text and rewrites x2c include targets during emission. `src-at` belongs to the
flat output token stream consumed by formatting, not source AST input. Match
lowering constructs ordinary blocks, switches, and native sequences; there is
no current `matchcases` production.

Owners: [_emit, _sequence, _prefix, _leaf][emit-dispatch];
[_banner, _header_guard, _source_unit, _vertical_spacing][generation-output];
[_match_lowered][match-component]; [source mapping and formatting][format-owner].

## Reading concrete layouts

The [type initializer fixture][initializer-fixture] contains this bound return,
shown with compact whitespace:

```text
(return (int) (expr (int) (literal (int) "42")))
```

Its first payload field is the return context, not the value. Lowering converts
the expression to that context and leaves:

```text
(return (expr (int) (literal (int) "42")))
```

The same fixture contains a no-argument call's `(args (expr (void) ()))`. The
[AST leaf fixture][leaf-fixture] contains a pointer-to-function declarator:

```text
(bind (binding 4 "ast_phase1_UnaryPointer")
  (* (fnmod (params (param (int) (bind () ()))))))
```

The pointer mark and function modifier are siblings in MODIFIERS. The function
parameter retains its base type and unnamed declarator; it is not yet the
semantic function modifier `(func ((int)))`.

The [captured lambda fixture][lambda-fixture] shows typed parameter rows,
capture storage types, and reference capture expressions. The
[catch fixture][catch-fixture] shows that catch patterns are typed List
expressions and that the handler follows the complete row List. These children
cannot be interpreted by looking only at a `capture` or `args` head.

## Reconciliation and coverage

The archived [canonical grammar appendix][historical-appendix] was the starting
inventory. Every family below was checked against current producers and
consumers. Searches covered literal constructions and structural matches
through `src/`, plus runtime, built-in, command, and tool users in `lib/`,
`etc/`, `commands/`, and `tools/`. Dynamic heads, helper constructors,
String-headed forms, and untagged rows were checked separately. This is a
source reconciliation, not a machine proof of a closed semantic grammar.

| Family | Current owners | Reconciliation |
| --- | --- | --- |
| Roots, names, origins | [ast][ast], [binding][binding], [identifiers][identifiers], [Code][sdk-syntax] | Retained; added spelling/global carriers and distinguished source records. |
| Expressions, operators, access | [syntax][expression-syntax], [resolution][resolution], [access][access], [calls][calls], [operators][operators] | Retained; clarified void call operand, raw callees, nested shells, `_Alignof`, and offsetof tokens. |
| Literals and interpolation | [atoms][atoms], [Lists][quotation-reader], [collections][collection-reader], [Strings][string-reader], [interpolation][interpolation-component] | Added numeric-zero String content and consumer-only `segraw`. |
| Declarations and Types | [declarations][declarations], [declarators][declarators], [types][type-parser], [Type conversion][compiler-type], [runtime Type][runtime-type] | Retained; distinguished semantic aggregate bodies, modifier chains, generated prototype variant, and `unqual`. |
| Lambdas and callbacks | [lambdas][lambdas], [lambda lowering][lambda-component], [callbacks][callbacks] | Added bare lambda parameters and pre-binding capture targets; distinguished adaptation stages. |
| Statements, match, catch, raise | [statements][statements], [binding][binding], [match][match-component], [try][try-component], [raise][raise-component] | Retained; corrected default/guard rows and documented three return layouts. |
| Macro/template values | [definitions][macro-definitions], [captures][invocation-captures], [quotations][macro-quotations], [templates][macro-templates], [runtime Macro][macro-construction] | Added String-headed syntax, descriptor rebuild/leaf/static/env rows, scalar/sequence captures, and code values. |
| Retained declarations | [units][units], [production][declaration-production], [defaults][declaration-defaults], [portable syntax][portable-syntax] | Added retained initializers; separated replay and transport metadata. |
| Protocols and imports | [protocol declarations][protocol-declarations], [registry][protocol-registry], [units][units] | Retained; distinguished protocol String head and package-import metadata. |
| Initializer alternatives | [subobjects][initializer-subobjects], [conversion][initializer-conversion], [emission][emit-initialization] | Corrected paths to untagged stack frames; kept native operand placeholders. |
| Cleanup and generation | [defer][cleanup-defer], [statics][cleanup-statics], [transfers][cleanup-transfers], [generation][generation-projection], [cache][cache-owner] | Added landing/staticinit/kernel forms and ordered substitution rows. |
| Emission and cache | [dispatch][emit-dispatch], [initializers][emit-initialization], [cache values][literal-cache], [output][generation-output] | Distinguished payloads/output; retained generic C fragments and compatibility consumers. |
| Historical-only forms | Current source search and the owners above | `matchcases`, `managed-init`, `vpair`, Lisp String slots, and Lisp/import replay events removed from the current inventory; their historical layouts are not current contracts. |

### Adjacent data is not program syntax

A literal head search also finds patterns, metadata, errors, and arbitrary
application data. The following classifications prevent those records from
being mistaken for additional program nodes.

| Data family | Representative heads and layouts | Owner and boundary |
| --- | --- | --- |
| Initializer and lambda facts | `enum-value`, `first`, `next`, `lambda-capture`, `lambda-depth`, `lambda-order`, `lambda-param`, `lambda-scope`, `lambda-snapshot`, `parameter`, `reference-param`, `optional-reference-param` | [type parser][type-parser], [lambdas][lambdas], binding facts; not accepted expression heads. |
| Binding and source facts | `aggfact`, `alias`, `automatic`, `class-tag`, `defer-ownr`, `definition-span`, `ntype`, `present-references`, `source-spelling`, `src-key`, `type`, `using` | [symbol bindings][symbol-bindings] and [binding facts][binding-facts]; keyed compiler state. |
| Member and callable results | `field`, `method`, `delegate`, `step`, `ambiguous`, `func-arg`, `func-splice`, `indirect-adapter`, `inherited`, `thunk`, `no-value` | [access][access], [calls][calls], [callable adapters][callable-adapters]; lookup/extraction results. |
| Memo and resolution keys | `fadapt`, `fgetter`, `fhandle`, `findirect`, `fpointer-factory`, memo-key `tadapt`, `iadapt`, `string-switch`, `unit-support`, `unit-init` | [callable values][callable-values], [callbacks][callbacks], components and placement; not expression productions despite repeated heads. |
| Region analysis | `alloc`, `close`, `destroy`, `exit`, `free`, `move`, `open`, `pool`, `store`, `summary`, `wrap` | [region analysis][regions-owner]; describes effects, not executable AST nodes. |
| Declaration replay | `(declaration-source END BUNDLE FACTS)`, `(package-import PACKAGE ALIAS MEMBERS)`, `("source-node" ...)`, `(imported-macro DEFINITION)` | [declaration production][declaration-production], [portable syntax][portable-syntax], macro registry; retains source-order effects outside binder syntax. |
| Frozen syntax transport | `declaration-void`, `declaration-empty-symbol`, `declaration-atom`, `declaration-token`, `declaration-origin`, `declaration-list`, `declaration-cache`, `declaration-cache-binding`, `declaration-binding` | [freeze/thaw][portable-syntax]; serialized values described below. |
| Compile-time replay | `(compile-time effects EFFECT*)`, plus macrodef/keyword/alias/unalias/rewrite rows; `project-meta` | [effect installation][invocation-recognition]; replay events, not `_bind_form` alternatives. |
| Placement requests | `(after-statement)`, `(block-exit)`, `(function-entry)`, `(unit-support [KEY])`, `(unit-init [AREA])` | [Compiler.place][macro-values]; API requests whose code later enters the ordinary binder. |
| Macro implementation data | `("x2c.slot" TYPE SHAPE)`, `("x2c.slot" INDEX)`, `provisional`, `tag-local`, `name-argument`, `quotation`, `quoted`, `constant`, `dynamic`, `locals`, `any` | [rewrite projection][rewrites], definition reading and quotation construction; skeletons and capture state. |
| Protocol registry | `conformance`, `protocol-conformance`, `proto-file`, `"parsed-protocol-adoption"`, `"recorded-conformance"`, owner/linkage/conflict rows | [protocol registry][protocol-registry] and lookup; separate from `protocol`/`adopt` syntax. |
| Generation and interface records | `pending`, `completed`, `completion`, `conditional`, `interface`, `interface-types`, `meta-hashes`, `native`, `native-object`, `native-meta`, `api-definition`, `attributes`, path rows `home`/`absolute`/`relative` | [generation projection][generation-projection], collection and compiler definitions; scheduling, interfaces, or binding facts. |
| Dumps and operational messages | `unit`, `module`, `function-contract`, definition-display rows, `answer`, `query`, `dependency`, `failure`, `warning`, `missing`, `quit`, `reset`, `replcomp`, error causes, graph/REPL reports | [definition dumps][definition-output], meta helper protocol and command consumers; output or application data. A `function` dump record is not automatically the AST `function` production. |
| Match and Lisp data | `!or`, `!set`, `!quote`, `!is`, capture atoms, operator Lists such as `(&& ...)`, quoted Lists, arbitrary runtime reader forms | [Match](../guide/match.md) and literal readers; data/pattern grammar, not additional program nodes. |

### Frozen syntax transport layouts

These transport records are included to explain serialized Lists beside ASTs.
They do not expand the constructed-source grammar.

```text
FROZEN ::= (declaration-void) | (declaration-empty-symbol)
         | (declaration-atom SPELLING)
         | (declaration-token TYPE-STRING TEXT LINE COLUMN LENGTH OFFSET)
         | (declaration-origin LOCATION FROZEN)
         | (declaration-list FROZEN*) | (declaration-cache FROZEN-KEY)
         | (declaration-cache-binding SPELLING)
         | (declaration-binding BINDING SOURCE-SPELLING)
```

[Compiler.freeze_declaration_syntax and
Compiler.thaw_declaration_syntax][portable-syntax] own these records.
Marker-headed user Lists are escaped with `declaration-list`, so arbitrary data
is preserved rather than mistaken for transport instructions. Locations, paths,
and cache keys are translated into the importing compiler's context.

## Index by head

The index includes program nodes, syntax carriers, and the explicitly
classified cache/transport records. Descriptor row keys are indexed through
`macrodef`; they are fields rather than standalone program nodes.

| Head | Production or role |
| --- | --- |
| `!quote` | [Shells, identifiers, and atomic values](#shells-identifiers-and-atomic-values); [Pending applications and captures](#pending-applications-and-captures) |
| `"Atom"` | [Shells, identifiers, and atomic values](#shells-identifiers-and-atomic-values) |
| `"__typeof__"` | [Source types and semantic Types](#source-types-and-semantic-types) |
| `"protocol-record"` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `"x2c.at"` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation) |
| `"x2c.hole"` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation) |
| `"x2c.ident"` | [Roots, wrappers, and identities](#roots-wrappers-and-identities); [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation) |
| `"x2c.quoted"` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation) |
| `"x2c.template"` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation) |
| `*` | [Match, raise, and catch rows](#match-raise-and-catch-rows); [Reading concrete layouts](#reading-concrete-layouts) |
| `...` | [Modifiers and parameters](#modifiers-and-parameters) |
| `0` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `<macro-expr>` | [Shells, identifiers, and atomic values](#shells-identifiers-and-atomic-values); [Source types and semantic Types](#source-types-and-semantic-types) |
| `adopt` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `api-source` | [Roots, wrappers, and identities](#roots-wrappers-and-identities) |
| `append` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `args` | [Operators, calls, and access](#operators-calls-and-access); [Match, raise, and catch rows](#match-raise-and-catch-rows); [Pending applications and captures](#pending-applications-and-captures) |
| `array` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `associated` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `association` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `at` | [Roots, wrappers, and identities](#roots-wrappers-and-identities); [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `bind` | [Declaration forms](#declaration-forms); [Reading concrete layouts](#reading-concrete-layouts) |
| `binder` | [Macro definitions](#macro-definitions) |
| `binding` | [Roots, wrappers, and identities](#roots-wrappers-and-identities); [Reading concrete layouts](#reading-concrete-layouts) |
| `binding-global` | [Roots, wrappers, and identities](#roots-wrappers-and-identities) |
| `binding-name` | [Roots, wrappers, and identities](#roots-wrappers-and-identities) |
| `bindings` | [Declaration forms](#declaration-forms) |
| `bitfield` | [Modifiers and parameters](#modifiers-and-parameters); [Source types and semantic Types](#source-types-and-semantic-types) |
| `block` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `break` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `builtin` | [Macro definitions](#macro-definitions) |
| `c-assert` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `cache` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments); [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `call` | [Operators, calls, and access](#operators-calls-and-access) |
| `capture` | [Lambdas and typed adaptation](#lambdas-and-typed-adaptation); [Pending applications and captures](#pending-applications-and-captures) |
| `captures` | [Lambdas and typed adaptation](#lambdas-and-typed-adaptation); [Macro definitions](#macro-definitions) |
| `case` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `cast` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `catchcases` | [Match, raise, and catch rows](#match-raise-and-catch-rows) |
| `cleanup` | [Code values and effects](#code-values-and-effects) |
| `code-value` | [Code values and effects](#code-values-and-effects) |
| `commas` | [Initializers and destructuring](#initializers-and-destructuring) |
| `comment` | [Native sequences, decorations, and output tokens](#native-sequences-decorations-and-output-tokens) |
| `composite` | [Initializers and destructuring](#initializers-and-destructuring) |
| `cons` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments); [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `construct` | [Roots, wrappers, and identities](#roots-wrappers-and-identities); [Pending applications and captures](#pending-applications-and-captures) |
| `continue` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `decl` | [Declaration forms](#declaration-forms) |
| `declaration-atom` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-binding` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-bundle` | [Retained declaration production](#retained-declaration-production) |
| `declaration-cache` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-cache-binding` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-default` | [Retained declaration production](#retained-declaration-production) |
| `declaration-empty-symbol` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-forward` | [Retained declaration production](#retained-declaration-production) |
| `declaration-function` | [Retained declaration production](#retained-declaration-production) |
| `declaration-initialized` | [Retained declaration production](#retained-declaration-production) |
| `declaration-list` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-origin` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-pending` | [Retained declaration production](#retained-declaration-production) |
| `declaration-recipe` | [Retained declaration production](#retained-declaration-production) |
| `declaration-token` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declaration-void` | [Frozen syntax transport layouts](#frozen-syntax-transport-layouts) |
| `declare` | [Declaration forms](#declaration-forms) |
| `default` | [Ordinary statements and sequences](#ordinary-statements-and-sequences); [Retained declaration production](#retained-declaration-production) |
| `default-forward` | [Retained declaration production](#retained-declaration-production) |
| `defer` | [Ordinary statements and sequences](#ordinary-statements-and-sequences); [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `dim` | [Modifiers and parameters](#modifiers-and-parameters); [Source types and semantic Types](#source-types-and-semantic-types) |
| `do` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `dotinit` | [Initializers and destructuring](#initializers-and-destructuring) |
| `dstrasgn` | [Initializers and destructuring](#initializers-and-destructuring) |
| `dstrdecl` | [Declaration forms](#declaration-forms) |
| `empty` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `env` | [Macro definitions](#macro-definitions) |
| `exits` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `expr` | [Shells, identifiers, and atomic values](#shells-identifiers-and-atomic-values); [Reading concrete layouts](#reading-concrete-layouts) |
| `expression` | [Pending applications and captures](#pending-applications-and-captures) |
| `falias` | [Declaration forms](#declaration-forms) |
| `fields` | [Source types and semantic Types](#source-types-and-semantic-types) |
| `file` | [Macro definitions](#macro-definitions) |
| `fnmod` | [Modifiers and parameters](#modifiers-and-parameters); [Reading concrete layouts](#reading-concrete-layouts) |
| `for` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `fresh` | [Pending applications and captures](#pending-applications-and-captures); [Macro definitions](#macro-definitions) |
| `func` | [Source types and semantic Types](#source-types-and-semantic-types) |
| `function` | [Declaration forms](#declaration-forms); [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `generic` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `gensym` | [Roots, wrappers, and identities](#roots-wrappers-and-identities) |
| `getindex` | [Operators, calls, and access](#operators-calls-and-access) |
| `goto` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `group` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `guarded` | [Match, raise, and catch rows](#match-raise-and-catch-rows) |
| `ident` | [Shells, identifiers, and atomic values](#shells-identifiers-and-atomic-values) |
| `if` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `import` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `index` | [Operators, calls, and access](#operators-calls-and-access) |
| `indexinit` | [Initializers and destructuring](#initializers-and-destructuring) |
| `initcode` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `initval` | [Native-dependent initializer alternatives](#native-dependent-initializer-alternatives) |
| `input` | [Native-dependent initializer alternatives](#native-dependent-initializer-alternatives); [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `int` | [Reading concrete layouts](#reading-concrete-layouts) |
| `is-symbol` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `is-type` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `kind` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation); [Macro definitions](#macro-definitions) |
| `label` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `lambda` | [Lambdas and typed adaptation](#lambdas-and-typed-adaptation) |
| `landing` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `leaf` | [Macro definitions](#macro-definitions) |
| `literal` | [Shells, identifiers, and atomic values](#shells-identifiers-and-atomic-values); [Reading concrete layouts](#reading-concrete-layouts) |
| `local` | [Macro definitions](#macro-definitions) |
| `local-macro` | [Pending applications and captures](#pending-applications-and-captures) |
| `localinit` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `macro-bind` | [Pending applications and captures](#pending-applications-and-captures) |
| `macro-invoke` | [Pending applications and captures](#pending-applications-and-captures) |
| `macro-param` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation); [Macro definitions](#macro-definitions) |
| `macro-slot` | [Pending applications and captures](#pending-applications-and-captures) |
| `macro-value` | [Pending applications and captures](#pending-applications-and-captures) |
| `macrodef` | [Macro definitions](#macro-definitions) |
| `map` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `map-entry` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `match` | [Match, raise, and catch rows](#match-raise-and-catch-rows) |
| `match-if`, `matches` | [Match, raise, and catch rows](#match-raise-and-catch-rows) |
| `members` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `meta-call` | [Pending applications and captures](#pending-applications-and-captures) |
| `meta-cap` | [Pending applications and captures](#pending-applications-and-captures) |
| `meta-protocol` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `name` | [Macro definitions](#macro-definitions) |
| `named-type` | [Declaration forms](#declaration-forms) |
| `new-name` | [Code values and effects](#code-values-and-effects); [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `nil` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments); [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `offsetof` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `op` | [Operators, calls, and access](#operators-calls-and-access); [Declaration forms](#declaration-forms); [Source types and semantic Types](#source-types-and-semantic-types) |
| `origin` | [Macro definitions](#macro-definitions) |
| `outer` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `param` | [Modifiers and parameters](#modifiers-and-parameters); [Reading concrete layouts](#reading-concrete-layouts) |
| `parameters` | [Macro definitions](#macro-definitions) |
| `params` | [Lambdas and typed adaptation](#lambdas-and-typed-adaptation); [Declaration forms](#declaration-forms); [Modifiers and parameters](#modifiers-and-parameters); [Reading concrete layouts](#reading-concrete-layouts) |
| `parens` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection); [Source types and semantic Types](#source-types-and-semantic-types) |
| `pattern` | [Macro definitions](#macro-definitions) |
| `postfix` | [Operators, calls, and access](#operators-calls-and-access) |
| `preproc` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `protocol` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `raise` | [Match, raise, and catch rows](#match-raise-and-catch-rows) |
| `rebuild` | [Macro definitions](#macro-definitions) |
| `region` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `return` | [Ordinary statements and sequences](#ordinary-statements-and-sequences); [Reading concrete layouts](#reading-concrete-layouts) |
| `rewrite` | [Code values and effects](#code-values-and-effects) |
| `rows` | [Retained declaration production](#retained-declaration-production) |
| `segexp` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `segments` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `segraw` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `segvar` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments) |
| `seq` | [Declaration forms](#declaration-forms); [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `sequence` | [String-headed syntax values and quotation](#string-headed-syntax-values-and-quotation); [Macro definitions](#macro-definitions) |
| `sizeof` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `slice` | [Operators, calls, and access](#operators-calls-and-access) |
| `source` | [Roots, wrappers, and identities](#roots-wrappers-and-identities); [Pending applications and captures](#pending-applications-and-captures) |
| `sourceinit` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `space` | [Native sequences, decorations, and output tokens](#native-sequences-decorations-and-output-tokens) |
| `splice` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments); [Pending applications and captures](#pending-applications-and-captures) |
| `src` | [Roots, wrappers, and identities](#roots-wrappers-and-identities) |
| `static` | [Macro definitions](#macro-definitions) |
| `staticinit` | [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `stmnt` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `string` | [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `switch` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |
| `syntax-recipe` | [Retained declaration production](#retained-declaration-production) |
| `tadapt` | [Lambdas and typed adaptation](#lambdas-and-typed-adaptation) |
| `tag` | [Imports, protocols, and static assertions](#imports-protocols-and-static-assertions) |
| `target` | [Pending applications and captures](#pending-applications-and-captures); [Macro definitions](#macro-definitions) |
| `targetp` | [Macro definitions](#macro-definitions) |
| `targets` | [Initializers and destructuring](#initializers-and-destructuring); [Declaration forms](#declaration-forms) |
| `template` | [Macro definitions](#macro-definitions) |
| `tpl-call` | [Pending applications and captures](#pending-applications-and-captures) |
| `try` | [Match, raise, and catch rows](#match-raise-and-catch-rows); [Cleanup, initialization, and generated markers](#cleanup-initialization-and-generated-markers) |
| `type-tag` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `typedef` | [Declaration forms](#declaration-forms) |
| `unqual` | [Source types and semantic Types](#source-types-and-semantic-types) |
| `va-arg` | [Grouping, type operands, and selection](#grouping-type-operands-and-selection) |
| `value` | [Pending applications and captures](#pending-applications-and-captures) |
| `var` | [Collections, List construction, and String segments](#collections-list-construction-and-string-segments); [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `varray` | [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `vmap` | [Cache payloads and compatibility content](#cache-payloads-and-compatibility-content) |
| `while` | [Ordinary statements and sequences](#ordinary-statements-and-sequences) |

### Dynamic heads and forms without a head

Operators vary in the `op` field; aggregate kind selects `struct` or `union`;
source/semantic type Lists can start with a type name or modifier. Native
sequences can start with String text, another List, or numeric zero. Argument,
parameter, arm, capture, initializer-choice, environment, and path rows can be
untagged. Their enclosing productions determine how to read them.

For example, a pattern `(expr TYPE (call CALLEE (args ...)))` first establishes
the typed shell, then the call content, then its ordered arguments. A pattern
on `(return TYPE EXPR)` is recognizing the bound return stage; the lowered
stage no longer has that type field. A match on `(capture ...)` must know
whether it is reading a lambda capture or a macro invocation capture. Use this
chapter's production and stage together when reading such patterns.

[binding]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/binding.x
[ast]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/ast.x
[identifiers]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/expressions/identifiers.x
[macro-values]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/values.x
[units]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/units.x
[sdk-syntax]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/meta-sdk/syntax.x
[atoms]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/literals/atoms.x
[expression-syntax]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/expressions/syntax.x
[resolution]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/expressions/resolution.x
[emit-expressions]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/emit/expressions.x
[operators]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/operator-ledger.x
[access]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/expressions/access.x
[calls]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/expressions/calls.x
[bracket-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/bracket-access.x
[emit-dispatch]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/emit/dispatch.x
[quotation-reader]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/literals/quotation.x
[collection-reader]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/literals/collections.x
[string-reader]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/literals/strings.x
[collection-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/collection-literals.x
[interpolation-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/interpolation.x
[literal-cache]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/compiler/literal-cache.x
[initializer-conversion]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/initializers/conversion.x
[destructuring-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/destructuring.x
[lambdas]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/lambdas.x
[lambda-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/lambda-functions.x
[callbacks]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/callables/callbacks.x
[declarations]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/declarations.x
[functions]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/functions.x
[type-parser]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/types.x
[generation-projection]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/generate/projection.x
[emit-declarations]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/emit/declarations.x
[declarators]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/declarators.x
[compiler-type]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/type.x
[runtime-type]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/lib/type.x
[declaration-parts]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/lib/meta.x
[statements]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/statements.x
[transform-expressions]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/transform/expressions.x
[transform-traversal]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/transform/traversal.x
[cleanup-transfers]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/cleanup/transfers.x
[grammar-owner]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/grammar.x
[try-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/try-catch.x
[match-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/pattern-match.x
[raise-component]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/components/raise.x
[invocation-targets]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/invocations/targets.x
[invocation-expressions]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/invocations/expressions.x
[invocation-captures]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/invocations/captures.x
[macro-slots]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/definitions/slots.x
[expansion]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/expansion.x
[macro-construction]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/lib/macrovalue/construction.x
[macro-quotations]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/definitions/quotations.x
[macro-templates]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/templates.x
[macro-recognition]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/lib/macrovalue/recognition.x
[macro-patterns]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/lib/macrovalue/patterns.x
[macro-definitions]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/definitions/templates.x
[macro-reading]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/definitions/reading.x
[meta-library]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/lib/meta.x
[declaration-defaults]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/compiler/declarations/defaults.x
[declaration-production]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/compiler/declarations/production.x
[protocol-declarations]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/protocol/declarations.x
[protocol-registry]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/protocol/registry.x
[initializer-subobjects]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/initializers/subobjects.x
[emit-initialization]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/emit/initialization.x
[cleanup-defer]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/cleanup/defer.x
[cleanup-statics]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/cleanup/statics.x
[cache-owner]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/cache.x
[transform-literals]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/transform/literals.x
[generation-output]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/generate/output.x
[format-owner]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/format.x
[historical-appendix]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/plans/archive/compiler-dual-macro-contract.md#canonical-grammar-appendix
[portable-syntax]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/compiler/declarations/portable-syntax.x
[symbol-bindings]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/symtab/bindings.x
[binding-facts]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/compiler/binding-facts.x
[callable-adapters]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/callables/adapters.x
[callable-values]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/callables/values.x
[regions-owner]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/regions/regions.x
[invocation-recognition]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/invocations/recognition.x
[rewrites]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/macros/rewrites.x
[definition-output]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/generate/definitions.x

[stage-owner]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/stage.x

[initializer-fixture]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/unittest/compiler-fixtures/type-initializer.ast

[leaf-fixture]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/unittest/compiler-fixtures/ast-leaf-contract.ast

[lambda-fixture]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/unittest/compiler-fixtures/captured-lambda-lowering.ast

[catch-fixture]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/unittest/compiler-fixtures/catch-filter-arms.ast

[placement-owner]: https://github.com/gwf/x2c/blob/ff3aba2aac3d58a31db6fd53b5cfaeeef230b695/src/parse/placement.x
