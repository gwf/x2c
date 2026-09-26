# Greenfield design: the compiler front half

Key: front. Area: map 2.1, 2.2, 2.13 (lib/tokenizer.x, src/parse.x,
collect.x, deps.x, frontend.x, sourceview.x, statements.x, expressions.x,
literals.x, ast.x, type.x, type-ledger.x, protocol.x, compiler.x).

Current: 19,451 lines (wc -l over the 14 files; 17,116 code, 1,160
comment, 1,175 blank). Greenfield estimate: about 15,300 lines (range
14,800-15,800), a 21% reduction. The front half is close to its floor:
its size is the C declaration grammar plus x2c's typed resolution rules
plus the documented hard cases (raw header collection, preprocessor arms,
packages, protocols, initializers). The reduction comes from four
structural choices, not from a different parsing technique: templates as
unresolved syntax, environment frames instead of copied transactions, one
top-level classifier for both passes, and one declarator installer.

Answers to the four questions posed, in one line each; section 2 has the
reasoning. Pratt: no, the expression parser proper is 520 of 4,388 lines
and a Pratt loop saves about 35 of them. One parser with skip-body mode:
yes, saves about 130 lines and removes a drift risk. One persistent
environment: yes for Sym/SymTxn/overlay (frames), partly for freeze/thaw
and the process cache (they stay as one data normalization and one store).
Protocol resolution as a ranked table: yes, the doc table already is the
algorithm; it saves about 80 lines and mostly buys readability.

## 1. Feature and contract inventory

Section 4 rows this area implements, wholly or in part:

- C foundation, expression-bodied functions (parse.x:1570-1650); scalar
  declarations, literals, arithmetic (type.x:292-500, expressions.x:1247-
  1330); collection, string, symbol, atom literals (literals.x); string
  interpolation parse side (literals.x:786-835); indexing and slicing
  (expressions.x:105-183); method-style calls, postfix chains, unary,
  sizeof, offsetof, _Generic, va_arg, casts, designated initializers,
  compound literals, generic selection (expressions.x:620-1010, 3076-4053);
  mixed declaration rows (parse.x:1266-1275, 1352-1420); C initializers
  and static assertions (parse.x:566-591); exact Var-tag tests
  (expressions.x:2299-2350); membership `in` (expressions.x:1134-1192);
  flat destructuring (parse.x:1276-1330, expressions.x:2525-2548); Var
  boxing and conversion, compile-time half (expressions.x:4053-4388,
  compiler.x:3743-3780, type.x:520-620); protocol-backed direct updates
  (protocol.x:1740-1890); lambdas parse and capture binding
  (literals.x:837-1180); control flow, with, match, raise/catch/finally/
  defer parse (statements.x); reference parameters (type.x, compiler.x:
  545-620); delegate fields (expressions.x:410-512, compiler.x:3849-3870);
  protocols (protocol.x); checked foreign aliases (parse.x:2266-2342);
  type-owned initialization and shutdown (parse.x:1422-1570); named types
  and declaration production (parse.x:1085-1133, compiler.x:1345-1650);
  package imports and `name__` (parse.x:1700-1772, compiler.x:3047-3186,
  collect.x:610-780); source files, pragmas, script units (frontend.x,
  parse.x:1773-1802, compiler.x:2115-2230); indentation syntax
  (tokenizer.x:630-790); host preprocessing (frontend.x:165-236,
  compiler.x:669-920); two-pass compilation, `.xi`, dependency files
  (collect.x, deps.x); editor overlays and one-shot queries (sourceview.x,
  compiler.x:479-560, expressions.x:513-608); Null/void as values
  (literals.x:1218-1253).

Contracts the design must keep, with the statement and the pin:

1. Tokens are pointer-stable after scan; EOF idempotent; the layout rewrite
   is indistinguishable from braces (tokenizer.x:9-11, 826-829, 624-629;
   test-tokenizer.x 13 tests; indent-* and token-modes fixtures).
2. `in` and `match` are keywords only in their x2c positions
   (language.md:3341-3344; compiler.x:858-878; keyword-identifier fixture).
3. The active preprocessed stream is shallow-parsed only; never-active arms
   are trivia; a function defined in two arms is one definition; arms
   inside statements and initializers stay where written (language.md:
   3281-3320; compiler.x:669-833; c-*-arm, conditional-* fixtures).
4. A collected header may prefix declarations with macros collection never
   sees; the body decides what a name contributes (language.md:3322-3345;
   parse.x:251-335; c-prefix-macros, c-unseen-prefix-macro,
   header-aggregate-attributes).
5. First cold walk fixes a file's cache contribution; `.xi` replay is
   byte-identical to a cold walk with deterministic binding renumbering;
   stale, foreign, malformed interfaces are misses (collect.x:523-533,
   963-973, 845-950; run-header-cache.sh, proof-cold-collection,
   run-symbol-snapshot.sh).
6. `#pragma private` publishes only external functions and source-node rows
   across an include; a static function is private above and below it and
   the reference is reported with its file (language.md:20-31;
   collect.x:282-325; private-*, unit-static-call fixtures).
7. Package prefix applies only under the package root; `with` names never
   rename C symbols; one imported method is callable, two are an error
   (language.md:214-306; collect.x:227-236, 644-680; import-*, package-*,
   with-* fixtures).
8. A script unit either defines `main` or hoists its statements; collection
   and full parse agree (language.md:54-110; parse.x:1773-1802,
   compiler.x:1999-2110; script-* fixtures).
9. Method lookup: direct, imported, protocol, typedef ancestors, then
   delegate fields in source order with ambiguity and cycle rules
   (language.md:320-345, 445-510; expressions.x:350-512; method-*,
   delegate-field-*, import-method-* fixtures).
10. Member resolution: participant, nearest inherited, ordinary base
    default; `Var(T)` exact except `as R`; two ordinary defaults are an
    error naming both; mixed linkage is an error (protocols.md:231-283,
    371-378; protocol.x:901-993, 1563-1652; protocol-generated-*,
    relative-adoption, protocol-static-* probes).
11. Conversion rules in their order: reference and optional reference,
    raw string, Var to scalar/Symbol/pointer, T to Var by converter or tag,
    converter through the typedef chain stopping at the target, numeric,
    integer-to-pointer, unrelated pointers, sibling typedefs, qualifier
    discard, conditional and generic arms (language.md:3164-3273;
    expressions.x:4053-4388; var-*, sibling-typedef-assignment,
    qualifier-void-pointer, pointer-unrelated-argument fixtures).
12. Initializers: chained designators, brace elision, per-slot conversion,
    conditional arms, deferred native assignment (language.md:665-687;
    expressions.x:3076-4053; initializer-*, conditional-type-initializer*).
13. Deep flat chains parse under a 256 KiB stack (flat-*-stack fixtures
    with .stack-kb; expressions.x:1009-1055 worklist).
14. Semantic transactions snapshot exactly the fields their doc comment
    lists and nothing else (compiler.x:2538-2543); macro trial and
    comptime lowering rely on parser position surviving rollback.
15. No origin-authenticating validator for constructed syntax; bind_syntax
    accepts forms by structure and position (language.md:1863-1882;
    parse.x:2343-2560).
16. Binding identities are opaque and validated against `known` facts
    (expressions.x:1356-1366; binding-identity, macro-binding-identity-
    forged fixtures); `TagId` order matches the ledger (type-ledger.x).
17. `SymbolSet` literals are a compile-time perfect hash in static bytes
    (language.md:2171-2180; literals.x:330-455; symbol-set-* fixtures).
18. REPL submissions, completion rows, and editor source facts are the
    consumer surface of commands/repl and src/editor.x (map 2.12;
    parse.x:2040-2058, compiler.x:940-964, expressions.x:581-608).

## 2. The design, component by component

Representation stays: Token (struct in Tokenizer-owned Bytes), Ast and
Type as canonical List, symbol rows as `(key type)` Lists in Maps. Every
component below is a kernel operation in the brief's sense; nothing here
is a macro or meta function, because each needs binding, types, or
emission-order facts.

K1 Tokens (1,020). Tokenizer with mode stack and `_operator` dispatch
(tokenizer.x:153-209) unchanged; layout rewrite unchanged; the
preprocessor facts pass (never-active arms, layout-attribute marks, `in`/
`match` retag, compiler.x:669-920) moves beside it as one pass over the
scanned stream. The only change is folding `_scan_conditionals` and
`_retag_contextual_keywords` into one loop (-30).

K2 Units (530). Frontend: read, script text, package configure, tokenize,
collect, optional host-preprocessor path, meta preload; SourceView; deps.
Shrinks by dropping `collect_forget_preload_entries` glue and `_start`'s
duplicated field setup once K12's constructor takes the request (-60).

K3 Environment: frames (1,080). One `Env` type replaces Sym, SymScope,
SymTxn, and `_reset_overlay`. A frame is (symbols, bindings, enumerators,
macros, statics-delta, facts-delta, deleted). Scopes are frames; the
collection overlay (compiler.x:2663-2687) is frame 1 over base frame 0; a
transaction is a frame flagged `merge-on-pop`. begin = push an empty
frame (O(1)); lookup walks frames as `Sym.get_exact` already does
(compiler.x:2916-2927); commit = merge the frame's maps into its parent
(O(changes)) and keep the parent's map identity, which is what
`commit_transient` exists to preserve (compiler.x:2605-2628); rollback =
pop. Deletions (`sym.statics.del`, compiler.x:3211) become tombstones in
`deleted`. `declared_typetags` (type.x:526) becomes a frame delta too,
closing map 2.13's open question. The rest of Sym stays: lookup and
package retry (compiler.x:2930-3000), package spelling (3047-3186),
declare/bind_identity with the two duplicated fact blocks folded into one
helper (-20), one typedef walker with a stop predicate replacing the four
(3557-3780, -35), function completion contracts and static-object facts
(3267-3548), field order and delegates (3808-3870).

K4 Collection and the persistent cache (1,190). The file walk splits
segments at include and visibility directives and feeds each to the
declaration parser in skip-body mode with a fresh overlay frame
(collect.x:239-345, 408-537); the process cache keeps the same entry
shape `(parts hash definitions dependencies)`; `.xi` reads through
`Lisp.read` and writes through `List.repr` after binding renumbering
(collect.x:963-1036; `_write_datum` goes, -20). Freeze/thaw stays as the
one normalization from tokens and origins to portable data (compiler.x:
1274-1343); it is layered under the `.xi` writer, not parallel to it, so
"one primitive" is already the case and the map's note (2) does not buy
lines. Declaration bundles, defaults, and forwards (compiler.x:1345-1650)
stay with the pending/default/forward rows unified as one row kind with a
`stage` field (-40). The shallow loop (compiler.x:1669-1744) is deleted:
`parse_top_level` takes a `skip_bodies` mode whose continuations are
`_shallow_block` for `{`, `_skip_shallow_expression` for `=>`, macro-
invocation skipping, and held diagnostics (-130 net after adding the
mode branches). Both passes then share one classification, which closes
map 7's drift question (skip_linkage_brace and script statements appear
in both today only because the predicates are shared, parse.x:1850-1899).

K5 Declarations (2,250). Recursive descent for C declarations with the
lexer hack in `_test_declaration_start` (parse.x:1216-1264) kept: a
typedef-name lookup is the only symbol fact parsing needs. Two changes.
First, parse-then-bind: the token path builds the same `(declare base
(bindings ...))` syntax bind_syntax accepts and calls bind_syntax per row,
so `_install_declarator_node`, `_finish_type`, `_finish_declarator_
parameters` (parse.x:2059-2265) are the only installer and the token
path's own declare calls in `_declarator`/`_declarator_init` go (-150).
Binding order within a row is unchanged because bind_syntax installs
declarators in visitation order (parse.x:2371-2377). Second, macro-hole
name parsing in `_direct_declarator` (parse.x:1009-1060) becomes one
`_parse_name_slot` shared with `_parse_field_name` (-40). Everything else
is grammar: prefix macros and attributes (251-335), storage and
qualifiers, aggregates and enumerators (441-810), pointers, arrays,
bitfields, function parameters, mixed rows, destructuring, managed
initializers and lifecycle (1422-1570), function definitions and `=>`,
import, foreign alias, top-level dispatch shared with K4.

K6 Statements (620). As today. Governed statements with directive
placement (statements.x:36-100), match arms with typed captures and the
default-after-directive rule (326-413), filtered catches, `with`. The
`with` alias bookkeeping (564-620) shrinks by storing the alias row on the
scope frame instead of three binding-facts keys (-30).

K7 Expressions (3,000): four parts.

- Parser (350). A Pratt loop replaces `_precedence` plus the two level
  functions (expressions.x:952-970, 2470-2523, 75 lines) with a 40-line
  loop over the same table; `is` stays a relational-level special case.
  Postfix, unary, cast, primary, composite, comma, and the parenthesized
  statement entry stay recursive descent. `_parse_postfix_dot` and
  `_parse_postfix_arrow` fold over `_parse_field_name` (-20). Left-
  associative chains iterate, so contract 13 holds as it does today.
- Resolver (1,450). `_resolve_content` (2041-2434) is already a table: a
  match over node heads. It keeps that shape and loses every `<macro-expr>`
  branch under trade T2 (33 sites in expressions.x, 4 in literals.x, 1 in
  parse.x): templates are unresolved syntax, so no node is ever "typed
  but deferred". Identifier resolution, calls, method binding, dynamic
  Func calls, delegate search, imported ambiguity, discard helpers,
  operator members, binary typing, `is` tests, printf formats, iter chain
  completion, and completions stay (-450 in all: deferral -150,
  postfix/cons/box idioms shared with literals -40, `_resolve_call`
  method/delegate arms folded over one `(binding signature receiver)`
  triple -60, `_binary_op_type` families as one widest/promote table
  -40, and smaller folds).
- Conversion (400). `convert_expression` becomes an ordered rule list,
  each rule a predicate and an action, in the order contract 11 states.
  Same decisions, same order; the six families the map says may be
  load-bearing keep their sequence. Converter lookup through the typedef
  chain uses K3's one walker (-175 with 2834-3076).
- Initializers (650). One subobject cursor over (owner kind selector
  type rest) frames as today (3088-3100), with `_initializer_next`,
  `_initializer_merge`, and `_initializer_designated` kept for conditional
  arms, and the scalar-row, layout, ordinal, and adapter helpers
  (3419-3823) folded into the cursor's advance and convert steps (-330).

K8 Literals (1,050). List literal reader with reader prefixes, typed
captures, splices; quoted and unquoted Array and Map readers unified over
a `quoted` flag (-60); raise and catch pattern literals; string segments;
the SymbolSet perfect hash unchanged (contract 17); lambda parsing and
capture binding (837-1180) with `capture_lambda_identifier`'s three
capture kinds as one table (-40); atomic literals.

K9 AST contracts (260). Binding identity, preproc helpers,
`Ast.rewrite_children`, `never_returns`, `initializer_cases`. Survivor.

K10 Types (890). Type as List; declaration AST round trip; predicates;
`Type.scalar` and numeric literal typing; canonicalize and qualifiers;
promote and widest; `type_from_ast` as a match table (-30); the three
`_scalar_row` accessors as one (-15); Var tag registration moved onto K3
frames (-30). type-ledger.x unchanged.

K11 Protocols (2,050). Adoption rows carry their own visibility so the
two-shaped key and `_adoption_visibility` go (protocol.x:177-220, -60).
`_resolve_members` becomes a ranked clause list over (participant member,
inherited member, base default) producing the five statuses of
protocols.md:233-241 (-25). `_resolve_protocol_member`'s four searches
(1654-1720) become one ordered source list (-30). Adapter, thunk, and
native alias generation share one signature-substitution template
parameterized by direction (1927-1971, 2176-2287; -100). Requirement
checks, unification, native protocols, generated-owner collision reports,
update and discard helpers, descriptor registration, parse, and
`dump_conformance` stay (-300 more from the folds above and smaller
duplicate spellings such as `_type_spelling`/`_member_spelling`/
`_base_name` used at 40 sites).

K12 Compiler state, driver, literal cache (1,330). The struct regrouped
into Unit, Parser, Env, Meta, Out, SourceFacts sub-structs (-60);
lifecycle and child compilers; token navigation and completion; origins;
full_parse with script hoisting and the checks after it; literal cache
and match-pattern helpers (compiler.x:2243-2459), which belong beside
cache.x but are counted here.

Language changes: none.

## 3. Line ledger

Current by file: tokenizer 843, parse 2,830, collect 1,053, deps 139,
frontend 400, sourceview 76, statements 700, expressions 4,388, literals
1,253, ast 277, type 987, type-ledger 42, protocol 2,558, compiler 3,905;
total 19,451.

| component | current | greenfield | anchor and reasoning |
|---|---:|---:|---|
| K1 tokens | 1,093 | 1,020 | chibicc tokenize.c is about 800 lines for C alone; x2c adds seven scan modes and the 160-line layout rewrite; tokenizer.x 843 -> 800, preproc facts 250 -> 220 |
| K2 units | 615 | 530 | frontend 400 -> 340, sourceview 70, deps 120; deletions listed under K2 |
| K3 environment | 1,435 | 1,080 | compiler.x:2470-3905; frames replace SymTxn and reset (-100), one typedef walker (-35), fact blocks (-20), lookup folds (-30), tag registration +30 moved in |
| K4 collection, cache | 1,708 | 1,190 | collect.x 1,053 -> 870 (lib/json.x at 570 is a full reader-writer; `.xi` needs 170 because Lisp.read and List.repr own the grammar); compiler.x:1128-1782 655 -> 320 (shallow loop deleted -130, bundles -40, freeze/thaw -20) |
| K5 declarations | 2,830 | 2,250 | chibicc's declaration family is about 900 lines for C11; x2c grammar additions listed under K5 are about 1,000; one installer -150, name slots -40, top-level dispatch shared with K4 -60 |
| K6 statements | 700 | 620 | chibicc stmt() is about 300 for C; x2c adds match, try, raise, defer, with, and directive placement; `with` rows -30, smaller folds -50 |
| K7 expressions | 4,388 | 3,000 | parser 520 -> 350 (chibicc's expression family is about 700 with typing inline); resolver 1,900 -> 1,450; conversion 575 -> 400; initializers 977 -> 650 (chibicc initializers about 450 for C11 without conditional arms; arms and deferred native assignment add 200); printf/iter/slices 330 -> 150 |
| K8 literals | 1,253 | 1,050 | literate-lisp.x's reader is about 120 lines; the x2c list reader is 300 because it types elements and folds cache entries; perfect hash 130 kept; readers unified -60, captures -40, cons boxing shared -30, misc -70 |
| K9 ast | 277 | 260 | survivor |
| K10 types | 1,029 | 890 | folds listed under K10 |
| K11 protocols | 2,558 | 2,050 | concrete accounting under K11: -60 rows, -25 members, -30 member search, -100 adapter template, -300 spelling and duplicate folds |
| K12 state, driver | 1,565 | 1,330 | struct regrouping -60, constructor and child plumbing -50, full_parse script paths -60, cache helpers -20, misc -45 |
| total | 19,451 | 15,270 | -4,180 (21%); without trades T2 and T3 about 15,700 |

Estimates are +/-10%; K7's resolver and K11 are the least certain because
their folds are counted from reading, not from a written prototype.

## 4. Rope trades (the brief's 2x)

| trade | expected factor | what it buys | measurement |
|---|---|---|---|
| T1 frames replace copied transactions | < 1.0 (faster): every macro invocation copies the current scope's four maps and the statics, facts, counters, and layouts maps (compiler.x:2565-2572, macros.x:3875, 4050); at unit position that is the globals map | -100 lines and O(1) begin | translation CSV (unittest/benchmarks/run-compiler-translation.sh) and `perf record` share of Map copy in `builds/0/x2c translate lib/typed-array.x` |
| T2 templates as unresolved syntax | up to 1.2x macro expansion time: a body resolves once per expansion instead of once at definition plus a `<macro-expr>` re-resolve; today `_expression_requires_resolution` (expressions.x:1009-1055) already re-resolves any tree holding a hole | -190 lines across K7, K8, K5 and 10 sites in macros.x; removes a second typing state from every consumer | build-cost score (`make bm-build-scaling`) and wall time of `builds/0/x2c translate lib/typed-array.x` (macro heavy) vs `src/emit.x` (macro light) before and after |
| T3 parse-then-bind declarations | up to 1.05x on declaration-heavy units: one more walk per row through bind_syntax | -150 lines, one installer, no drift between token and constructed paths | translation CSV on src/parse.x and lib/x2c.x |
| T4 conversion as an ordered rule list | 1.0x: the same predicates in the same order | -175 lines, order made explicit | generated-C fixtures (c, h phases) unchanged |
| T5 initializer cursor | 1.0x | -330 lines | initializer-* and conditional-type-initializer* fixtures |
| T6 protocol resolution as ranked clauses | 1.0x: results are cached per (participant, member) as today (protocol.x:1475-1483) | -55 lines, reads like protocols.md:233-241 | protocol-* fixtures, probes/protocol, `--dump-conformance` diff over lib/ |
| T7 one classifier with skip-body mode | 1.0x: collection still skips bodies by token stepping | -130 lines | `builds/0/x2c translate --dump-symbols` timing vs full translate, proof-cold-collection |

No trade approaches 2x. Skipping bodies must stay a token skip; parsing
bodies during collection would roughly triple collection cost (every
included file is collected once per process) and is not proposed.

## 5. Survivors

- lib/tokenizer.x `_operator` dispatch, mode stack, and the layout rewrite
  (153-209, 630-790): the map calls the dispatch tight; the rewrite is the
  indentation contract and has no smaller expression.
- src/ast.x and src/type-ledger.x whole.
- The lexer hack `_test_declaration_start` (parse.x:1216-1264) and the
  comma-ambiguity retry (1266-1275): the language reference makes `int i,
  T value;` restart at T (language.md:729-736).
- `_resolve_content` as a match table (expressions.x:2041-2434): a table
  is what a table-driven resolver would be.
- `Type.scalar` and numeric literal typing (type.x:292-500): the
  order-independent specifier rule and literal families are enumerated
  facts.
- SymbolSet perfect hash (literals.x:330-455): documented output shape.
- Script hoisting and the implicit-main agreement (compiler.x:1999-2230).
- Function completion contracts across arms (compiler.x:3267-3410).
- `.xi` validation and binding renumbering (collect.x:845-1036).
- Statement grammar (statements.x:115-245, 425-520).
- Preprocessor facts: never-active arms and layout marks (compiler.x:
  669-833).

## 6. Hard cases and how the design handles each

1. Raw header collection with unseen prefix, wrapper, annotation, and
   layout macros (parse.x:251-335, compiler.x:691-786; c-prefix-macros,
   c-unseen-prefix-macro, c-annotation-macro, header-aggregate-attributes,
   meta-header-packed): K5 keeps the specifier-prefix reader keyed on
   `object_macros` classification; K1 keeps layout marks.
2. Never-active arms, arms inside statements, initializers, and match
   arms (compiler.x:669-690, 787-833; statements.x:36-100, 379-413;
   expressions.x initval): K1 marks trivia; K6 places directives; K7's
   cursor merges arm states.
3. Contextual `in` and `match` (compiler.x:858-878; keyword-identifier):
   K1 retag, 20 lines.
4. Indentation syntax (tokenizer.x:630-790; indent-*): survivor.
5. First-walk-wins cache, cold walk renumbering, `.xi` identical to cold
   (collect.x:399-407, 523-533, 963-973; run-header-cache.sh,
   proof-cold-collection): K4 keeps the entry shape and the counter
   restore in `_walk_apart`; overlays are frames.
6. Private rows across includes and unit-static markers (collect.x:
   282-325; expressions.x:1330-1345; unit-static-call): K4 filters the
   overlay frame before it joins parts, as today.
7. Package prefix under the root only, `with` names, imported ambiguity
   (collect.x:227-236, 644-720; compiler.x:3047-3186; import-*, with-*):
   K3 and K4 unchanged in rule; the retry key stays in lookup.
8. Script units in both passes (parse.x:1773-1802; script-*): the merged
   classifier uses the same `script_statement_starts` predicate in skip
   and parse modes, so agreement is structural.
9. Declaration production across segments and interfaces (compiler.x:
   1345-1650; class-*, meta-capture-definition): K4 keeps bundles,
   defaults, forwards, and freeze/thaw.
10. Macro templates with holes (84 hook sites in parser files; macro-body-
    type-hole*, macro-hole-grouping): K5 and K7 keep hole-kind lookahead
    for cast-vs-paren and name slots; under T2 the resolver never sees a
    hole, so `<macro-expr>` goes.
11. Method lookup order with delegates (expressions.x:350-512; delegate-
    field-*, import-method-*): K7 keeps an ordered source list; the cycle
    rule (delegate-field-cycle) stays as the path set on the search.
12. Member resolution and generated-owner collisions (protocol.x:901-993,
    1563-1652; protocol-generated-*, probes/protocol): K11 ranked clauses
    with the same cache keys.
13. Conversion order (expressions.x:4053-4388; var-*, sibling-typedef-
    assignment, qualifier-void-pointer, nonzero-integer-to-pointer): T4
    keeps the order; generated-C fixtures verify.
14. Initializers with designators, brace elision, conditional arms,
    deferred native assignment (expressions.x:3076-4053; initializer-*):
    T5.
15. Flat chains under 256 KiB (flat-*-stack): Pratt loop and declarator
    lists iterate; the re-resolution scan keeps its worklist.
16. Optional references proven by guards (compiler.x:545-620;
    optional-reference-*): binding facts on frames, K7 reads them.
17. Lambda captures across template and local-macro scopes (literals.x:
    894-1106; lambda-*): K8 unchanged in rule.
18. Prototype and definition contracts, static prototype linkage
    (compiler.x:3267-3410; macro-prototype-*, conditional-redefinition):
    survivor.
19. Explicit converter and unnecessary cast warnings (expressions.x:
    902-950, 1776-1823; explicit-converter-warning, unnecessary-cast-
    warning): K7, unchanged.
20. printf static formats against Var arguments (expressions.x:208-260;
    printf-var-*): K7, unchanged.
21. REPL submission boundary, completion rows, editor source facts
    (parse.x:2040-2058; compiler.x:479-560, 940-964; expressions.x:
    513-608): kept; map 2.12 says the consumer surface survives.
22. Transactions must not snapshot parser position (compiler.x:2538-2543):
    frames hold only environment state, so the property is by
    construction.

## 7. Experiments

1. Transaction copy cost: `perf record -g builds/0/x2c translate --out-dir
   /tmp/t lib/typed-array.x; perf report --stdio | grep -E 'Map_copy|
   begin_semantic_transaction'` gives the share T1 removes.
2. Pratt ceiling: `sed -n '952,970p;2470,2523p' src/expressions.x | wc -l`
   prints the 75 lines a Pratt loop replaces.
3. Expression parser share: `awk 'NR>=620&&NR<=1010||NR>=2470&&NR<=2830'
   src/expressions.x | wc -l` bounds the parser proper near 520 of 4,388.
4. T2 cost: `time builds/0/x2c translate --out-dir /tmp/t lib/typed-array.x`
   vs `src/emit.x` before and after; `grep -c 'macro-expr' src/*.x` counts
   the sites that go (33 expressions, 10 macros, 4 literals, 1 parse).
5. Collection share: `time builds/0/x2c translate --dump-symbols
   src/expressions.x >/dev/null` vs `time builds/0/x2c translate --out-dir
   /tmp/t src/expressions.x` bounds what a merged classifier can cost.
6. Cache and pass agreement: `unittest/probes/run-header-cache.sh` and
   `unittest/probes/run-symbol-snapshot.sh` with `X2C=builds/0/x2c`; both
   must pass unchanged after K3 and K4.
7. Stack: `ulimit -s 256; builds/0/x2c translate --out-dir /tmp/t
   unittest/compiler-fixtures/flat-binary-chain-stack.x`.
8. Protocol table: `builds/0/x2c translate --dump-conformance lib/x2c.x`
   before and after; the dump must be identical.
9. Whole-area acceptance: `make verify-fixtures` (16 tokens, 43 ast, 11
   symbols, about 110 c/h phase fixtures), `make stage-diff-all`, the
   build-cost score `make bm-build-scaling`, and the translation CSV.

## 8. Drops

None recommended. Candidates with their justification and lines, listed
as the brief requires:

- D1 host-preprocessor collection modes (`--cpp-symbols`,
  `--live-symbols`, `--dump-cpp`; frontend.x:165-236 plus shallow-only
  branches such as parse.x:287-300): -100 in this area. Documented as
  advanced modes (language.md:34-38); run-symbol-snapshot.sh uses them as
  the oracle that raw collection matches the C preprocessor's view, which
  nothing else checks. Not recommended.
- D2 `--dump-conformance` (protocol.x:1403-1466): -64. Documented in
  protocols.md:387 as the way to inspect homonyms before adding a member.
  Not recommended.
- D3 SymbolSet compile-time perfect hash replaced by init-time
  construction (literals.x:330-455): -130. Contradicts language.md:2179
  ("no runtime"), so it is a language change and not licensed here.
- D4 `_attribute_since` binary search to a linear scan (parse.x:517-533):
  -10; a simplification, not a feature drop.

## 9. Risks

- Generated-name numbering. T3 and T7 change the order in which
  `next_binding` and `fresh_name` counters advance, so the roughly 110
  fixtures that pin c/h phases need regeneration and review; stage
  comparison is unaffected because it checks the new compiler against
  itself; run-symbol-snapshot.sh's hygiene check only needs run-to-run
  stability.
- T2 reaches macros.x (10 `<macro-expr>` sites and the definition-time
  diagnosis of template bodies, map 2.3). The macros design must agree
  that a body is diagnosed at first expansion, or T2 shrinks to the
  parser-side deferral only (-60 instead of -190).
- Frames and deletions: `_replace_transaction_map` (compiler.x:2605-2614)
  shows deletions matter for statics; tombstones must be honored by every
  lookup, and the overlay frame that collect publishes must contain no
  tombstones (apply them before the frame joins parts).
- K7's resolver estimate assumes the `_resolve_call` method and delegate
  arms fold cleanly over one triple; `_method_bind` and
  `_materialize_delegate_receiver` differ in receiver materialization
  (expressions.x:1470-1489, 609-619) and may keep 30 lines.
- Not read: macros.x and comptime.x's use of `Sym` and `SymTxn` beyond the
  three transaction sites, lambda.x's binding-fact keys, editor.x. The 44
  `sym.introduce` and 34 `sym.resolve_key` calls outside this area (grep)
  keep the Sym surface as an API that K3 must preserve name for name.
- The estimate is from reading, not a prototype; the K11 folds (-300 from
  spelling helpers and duplicate classification in
  `install_generated_protocol_symbols` vs `generate_protocol_adapters`,
  map 2.13 open question 3) are the softest number in the ledger.
