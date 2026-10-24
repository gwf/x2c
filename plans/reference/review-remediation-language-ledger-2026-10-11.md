# Language-study disposition ledger

> Status: reference, 2026-10-11.
> Baseline: fetched `origin/dev` `6529e8689702d98db2754571ef7f3d9b43b0d5b9`.
> Final delta checked at `9004c40b63ad489625d1a19371124f4b4f32978a`.
> Supports [the remediation plan](../review-remediation-2026-10-11.md).

## Reference disposition, 2026-10-24

Retained as dated evidence, not a current defect or task list. The move
preserves the original observations; no historical probe was rerun.
Use the active [writing plan](../review-remediation-2026-10-11.md) and
[review follow-ups](review-followups-2026-10-24.md) for remaining scope.
The language ledger accounts for 181 historical study rows, not 181 tasks.


## Reading this ledger

All 181 main gap IDs are preserved. Most evidence is from the initial baseline;
D15/D17 and the grammar discussion explicitly account for final-tip changes.
The companion finding ledger records the targeted final-tip replay. A checked source contrast is not necessarily
a compiler defect. `Verified` below means the stated source/document contrast
was inspected, or execution is explicitly described. It does not mean every
claim in the supplied row is accepted. `Decision` identifies a semantic or
compatibility choice. `Overstated` and `refuted` narrow or reject the premise.
Any remaining unverified claim is not an implementation requirement.

Assessments refer to this baseline. Evidence pointers inherited from the study
identify the relevant owner but can retain older line numbers; use the named
operation and assessment rather than treating every inherited line as current.
The coordinator independently checked consequential conclusions and replayed
the behavior described in the companion finding ledger. Smaller source-only
documentation claims remain source evidence, without implied runtime coverage.

Batch F owns settled wording and navigation. Batches A-E own the confirmed
repairs identified in the main plan. Batch G owns consequential choices.
No row authorizes a new recurring check, a public API removal, or a new language
feature merely because the study called its absence a gap.

## Lexical rules

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| L1 | verified | `docs/src/reference/syntax/index.md:4-5`, `grammar.md:3-4`, `lexical.md:3-5` | Input claim: Syntax spec freshness: claims `48715bde`; last edited `f5d544ec`; 334 commits since. Review: Revision label is stale. Commit count is not a severity measurement. Update declared coverage revision after reviewing syntax changes. |
| L2 | overstated | `data.md:126-128`; `grammar.md:337-341` | Input claim: No executable link between syntax spec and compiler; no gate runs `tools/syntax-spec check`; compiler ignores `etc/syntax`. Review: No syntax-spec gate found, but absence of a gate is an optional maintenance choice, not a language defect. Do not add a recurring check without Gary approval. |
| L3 | verified | `src/literals.x:887-890`; `lexical-data.md:157-160` vs `etc/syntax/lexical.x:164` | Input claim: Percent-string decoding unescapes before collapsing `$$`, so `%"\$\$"` yields `"$"`; generated data shows it. Review: Fresh runtime probe dollars prints 1:$ for two escaped dollars. src/literals.x:887-890 collapses after unescaping. Repair decoding preserving escaped-dollar identity; grammar data is itself affected. |
| L4 | verified | `docs/src/guide/scripting.md:450`; `language.md:1623` documents `\$` only | Input claim: `$$` escape documented only in a guide. Review: Reference and scripting guide expose different escape sets. Document after L3 semantics are settled. |
| L5 | verified | `lib/scan.x:22-25`; `lib/tokenizer.x:200-213` | Input claim: Character set: ASCII identifiers, no BOM handling, non-ASCII in code is an invalid token. Review: ASCII scanner predicates and no code-mode non-ASCII operator fallback establish implementation boundary; UTF-8/BOM probes not run. |
| L6 | overstated | No "UTF-8" in `language.md` | Input claim: Text encoding of `String` (bytes vs UTF-8). Review: String indexing reference already says a byte represented as int (language.md:3352-3354). Add encoding boundary once; do not invent UTF-8 semantics. |
| L7 | verified | `lib/tokenizer.x:201` | Input claim: Backslash-newline is not a line splice outside directives and literals. Review: Code scanner admits no backslash operator; line-splice claim is source-only, not executed. |
| L8 | overstated | `lib/native-scalar-types.x:56`; `lexical-data.md:407-432` | Input claim: C11 syntax absent: `_Alignas`, `_Alignof(type)`, `_Atomic`, `_Complex`, `typeof`, `asm`, digraphs. Review: Unsupported dedicated parser productions differ from inability to emit a host C call/name. _Alignof internal AST construction deliberately works. Check each spelling separately; no blanket new validator. |
| L9 | verified | `grammar.md:55-56`; `lib/native-scalar-types.x:25-42` | Input claim: `_Bool`/`bool` only through the typedef-name path; no Var row. Review: native_scalar_types has no _Bool/bool row. Public boxing support remains a decision; absence of row alone is not proof all bool aliases fail. |
| L10 | verified | `lexical.md:78-82` lists words only | Input claim: Contextual words and their positions are scattered. Review: Contextual word inventory is distributed; module now adds collection-stage recognition. Small reference table suffices. |
| L11 | verified | `lib/tokenizer.x:162-170`; `src/macros.x:3293-3312` | Input claim: Sigil whitespace (`$ name` accepted; `$ int` is a keyword). Review: _named_reference keyword bypass only for adjacent name; _scan_name skips trivia. $ name and $ int differ. Source-only. |
| L12 | verified | `src/compiler.x:564-565` | Input claim: `=>`, `$!`, `&?` accept trivia between their two tokens. Review: Two-token compounds use trivia-skipping lookahead; document lexical versus parser tokens clearly. |
| L13 | verified | `lib/scan.x:588`; `lib/tokenizer.x:254-279` | Input claim: Bare `@`, `[`, `{` inside `$( )` are lexical errors. Review: scan_atom_status and _lisp_punctuation reject bare @,[,{ in embedded Lisp. Source-only. |
| L14 | verified | `language.md:243-244` vs `lib/tokenizer.x:771-774` (`lexical.md:330` is correct) | Input claim: Layout closer: `language.md` omits `static typedef` exception. Review: Layout code includes static typedef exception; fix reference omission. |
| L15 | overstated | `src/preprocess.x:42-75` (in `language.md:3963-3980`) | Input claim: Conditional-arm hiding rules absent from the syntax spec. Review: Rule already exists in language reference. Syntax chapter may link to preprocessing rather than repeat it. |
| L16 | overstated | `lexical.md:91`; `lib/tokenizer.x:105-109` | Input claim: `@` listed among scanner operators though the sigil rule wins in code mode. Review: Scanner operator inventory can truthfully list @ while code tokenizer handles sigil first. Clarify inventory layer, not remove scanner capability. |

## Syntax

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| S1 | verified | `grammar.md:143`; ledger `src/operator-ledger.x:11-32`; fixture `protocol-operator-matmul-missing` | Input claim: `@` in precedence table (Binary 10). Review: Ledger lacks @ and grammar table still lists it. Existing macro-at-splicing plan records removal; correct the stale table without restoring the removed design. |
| S2 | overstated | `src/macros.x:3271-3312,785-791,2410-2468` | Invocation lookup accepts $/@ in different positions, and member components may be keywords. Definitions and keyword targets require $; scalar primary @one() rejects. Separate definition names, scalar invocations, and sequence invocations in grammar. Nine grammar counterexamples were replayed by the coordinator. |
| S3 | verified | `x2c.ebnf:258` vs `src/literals.x:714-726` | Input claim: Quoted Array `${@seq}` item missing. Review: Quoted Array sequence slot exists in literals.x:714-726; preserve canonical capture construction. |
| S4 | verified | `x2c.ebnf:261-262` vs `src/literals.x:767-768` | Input claim: Quoted Map bare entry slot missing. Review: literals.x:765-768 tries a bare map-entry macro slot before ${...}; x2c.ebnf:261-262 lacks that alternative. Add bare template slot to grammar, preserving context restriction; source evidence sufficient. |
| S5 | verified | `x2c.ebnf:180` vs `src/expressions.x:281-345` | Input claim: Cast follow restriction missing. Review: Cast ambiguity is contextual lookahead, not unrestricted C grammar. Encode a semantic predicate or prose restriction. |
| S6 | overstated | `x2c.ebnf:128` vs `src/statements.x:329-334` | Input claim: `goto` target optional in code. Review: Fresh goto; translation rejects at emit: target label not defined. Parser optional label is permissive intermediate syntax, not accepted language form. Do not broaden EBNF to advertise legal targetless goto. |
| S7 | verified | `x2c.ebnf:248` vs `src/lambdas.x:136-183` | Input claim: Lambda capture `&$name` in templates. Review: Lambda using supports template &$name by prescribed capture rows; source-only. |
| S8 | verified | `x2c.ebnf:194`; `src/expressions.x:590-601`; `src/parse.x:2017` | Input claim: Member and declarator names accept keyword-shaped text. Review: expressions.x:590-601 and parse.x:2017 use spelling is_identifier rather than token kind; method names too at parse.x:2474-2484. Fresh int T.if(T) and t.if() run prints 3. Do not promise raw C keyword variable/field names native compiler accepts. |
| S9 | verified | `x2c.ebnf:32-34` vs `src/parse.x:917-947` | Input claim: `typedef` has its own path, not a storage prefix. Review: parse.x:917-947 routes typedef through _typedef qualifier/specifier/declarator path. Descriptive grammar should preserve actual placement without implying implementation branch is itself semantics. |
| S10 | verified | `x2c.ebnf:57,109` vs `src/expressions.x:242-277` | Input claim: Statement starting `(`: cast and resumed expression forms. Review: expressions.x:242-277 explicitly branches anonymous single-param cast, typed destructuring, and resumed parenthesized expression. Fresh (int)v and (v)+=3 run prints 5; warning reflects unnecessary cast, not failure. Grammar omission confirmed. |
| S11 | verified | `x2c.ebnf` unit-item vs `src/parse.x:313-351` | Input claim: `static` before `typedef`, `$(`, `protocol`, `class`. Review: parse_top_level static source_private recurses for interface items. Broad grammar should express allowed positions. |
| S12 | verified | `x2c.ebnf:36` vs `src/parse.x:1418-1423` | Input claim: `Self` not a terminal in `type-specifier`. Review: Self is special type spelling. Add terminal with context restriction. |
| S13 | verified | `language.md:659-668`; `x2c.ebnf:79-87` vs `src/protocol.x:486-491` | Input claim: Protocol grammar omits `meta`; EBNF omits `static` on adoption. Review: Protocol adoption source admits meta/static; docs and grammar differ. Fix grammar without changing adoption policy. |
| S14 | verified | `src/macros.x:3440-3526` | Input claim: Macro arguments: trailing comma rejected; `in` only after a `Decl` hole; first `Param` opens a scope. Review: _invocation_arguments and _argument_separator enforce scope/trailing comma/Decl in separator. Source-only. |
| S15 | verified | `src/macros.x:3884-3888,4139-4143` | Input claim: `@deco(args);` with a `;` is rejected. Review: Decoration.arguments macros.x:3884 rejects ; and _expression_decorator:4139 rejects ;/EOF. Existing semicolon fixture replay fails decorator application must not end with semicolon. No new supported syntax. |
| S16 | verified | `x2c.ebnf:99` vs `src/statements.x:98` (`grammar.md:174-176` states it) | Input claim: `%{` as a block opener missing from EBNF. Review: Percent brace can begin block; context decides quotation/map/block. Grammar must retain mode distinctions. |
| S17 | verified | `x2c.ebnf:277-283` vs `src/macros.x:1392-1400` | Input claim: Body `using` lines missing from EBNF. Review: _parse_body_using explicitly handles body using lines. Add grammar rule. |
| S18 | decision | `x2c.ebnf:297`; `src/macros.x:1620-1627` | Input claim: `quotation-kind` admits `Decorator`/`Declaration`; behavior unspecified. Review: Accepting result-kind spelling does not prove legal quotation body/placement. Trace binder before public promise. |
| S19 | verified | `grammar.md:177` vs `src/component-match.x:260-269` | Input claim: Pattern grammar P1 says "static List pattern"; runtime `$x` patterns are accepted. Review: _match_test handles transient runtime patterns. Static-only wording is too narrow. |
| S20 | verified | `grammar.md:186-188` vs `language.md:3726-3730` | Input claim: Catch code-position grammar narrower than documented `(!or ...)` codes. Review: literals.x:578-586 _parse_catch_code accepts arbitrary _parse_list_head when not bare atom, so nested (!or ...) code pattern parses. Full runtime matching of these code patterns was not independently replayed. |
| S21 | verified | `src/macros.x:3861-3865,3912-3921` vs `grammar.md:284-294` | Input claim: Decorator targets: a `Stmt` decorator before a file-scope function decorates its body. Review: Decoration.on_body macros.x:3861 selects Stmt/block at AST_UNIT; target:3912 parses function and captures body. Fresh $wrap() before int f adds puts to f body, prints wrapped then 5. Describe this deliberate target adaptation, not arbitrary Unit target acceptance. |
| S22 | verified | `src/expressions.x:407-426` | Input claim: `sizeof (x)[i]` binds differently from C. Review: Fresh sizeof (xs)[0] probe fails parse expected ). Study understates the failure as different binding. A native C control prints 4 for an int element. Batch C restores ordinary sizeof operand parsing through the existing expression owner. |
| S23 | verified | `src/statements.x:310-315` | Input claim: `case` label takes a comma expression; no GNU case ranges. Review: statements.x:310-315 uses full parse_expression for case label; fresh case 1,2 translates, case 1 ... 3 rejects expected colon. This is parser acceptance; native constant-expression validity remains native C compiler obligation. |
| S24 | verified | `src/parse.x:2349-2350`; fixture `empty-parameter-list` | Input claim: `()` parameter list rejected; stated only in syntax map and fixture. Review: Source parser requires nonempty parameter lists; fixture diagnostic exists. No change request follows. |
| S25 | verified | `grammar.md:147-151` | Input claim: Precedence of x2c forms (`in`, `is`, lambda body, decorator target) partly documented. Review: Precedence operand levels are explicit in parser and differ by lambda/function/macro target. Small table is useful. |
| S26 | overstated | `unittest/compiler-fixtures/*.diagnostics` | Input claim: Syntax-rejection evidence exists only as about 170 parse-diagnostic fixtures; no grammar-driven corpus. Review: Fixture coverage is not necessarily insufficient because corpus is not grammar-generated. Assess missing cases concretely; corpus count not re-counted. |
| S27 | overstated | `lib/lisp.x` LispReader; `grammar.md:212-218` | Input claim: Lisp reader grammar inside `$( )`. Review: Lisp grammar is separate dialect/mode, not ordinary C expression grammar; Use the compact dialect contract and contextual grammar assessment below. |
| S28 | verified | `language.md:100-106`; `src/collect.x:378-419`; no `module` hit under `docs/src/reference/syntax/` or `etc/syntax/` | Input claim: Module block (`module { "path", ... }`) is absent from `x2c.ebnf`, `grammar.md`, `lexical.md`, and `etc/syntax/grammar.x`; `module` is a new contextual word. Review: Module is absent in syntax artifacts and lives in collection preprocessing. Add text-splicing syntax plus context prose; not fake parse_top_level production. |

## Declarations and modules

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| D1 | verified | `agents/x2c-code-standard.md:437-444`; `src/generate.x:1-9` | Input claim: Use before declaration of functions (and possibly types) within a unit. Review: Fresh probe earlier main calls later private function and prints 9. Types remain unprobed. Conflicts with module plan blanket C declaration-order/prototype sentence; resolve wording from actual requirement before coding. |
| D2 | verified | `src/collect.x:903-940` | Input claim: `#include` search order: cwd, `lib/`, compiler `src/` before `-I`. Review: _include_dirs explicitly uses includer,cwd,lib,src,extra_dirs. Host mode uses distinct -idirafter. Document both tool modes; unification is a new behavior decision. |
| D3 | verified | `src/symbols.x:19-24,588-607` | Input claim: Reserved spellings `_x2c_*`, `_init_guard_`, `_file_init_`, `_<digits>`, `pkg__`. Review: Reserved spellings checked by symbols; package-prefix restriction depends imported namespace. Document conditional scope, not global pkg__ reservation. |
| D4 | checked with execution | `src/collect.x:1927-1990` | Input claim: Imports replay through `#include`. Review: Included source imports were replayed in a fresh two-unit build. The provider and consumer link and print 7. Document import replay and package context; the initial consumer-only build lacked the provider header and was not a language failure. |
| D5 | checked with execution | No `import` in `packages/*/src`; `src/collect.x:1830-1850` | Input claim: A package importing another package. Review: A fresh alpha package imports beta; the consumer imports alpha. With both archives built, the executable prints 8. Nested imports work in this case. This does not test every alias collision or dependency cycle; document the existing transitive route without inventing another package graph. |
| D6 | overstated | `src/collect.x:2067-2073`; `protocols.md:165-180` | Input claim: `.xi` carries protocol conformance, so it is semantic. Review: .xi serializes semantic data but remains reconstructible cache. Missing cache cold path must preserve meaning; infer semantic format, not cache-dependent language semantics. Module hashes verified in _walk_file. |
| D7 | overstated | `src/utils.x:273`; `packages.md:9-11` | Input claim: `<dir>/<name>.x` package form called "legacy" in code. Review: Legacy code comment is not a deprecation policy. Lookup explicitly retains fallback; no removal justified. |
| D8 | confirmed defect | `src/install.x:344-346` vs `src/utils.x:265-266` | Input claim: `.xp` package entry accepted by `x2c install`, not by `import`. Review: A local src/indentpkg.xp package installs with status 0, then importing indentpkg fails as unknown package. The diagnostic searches only .x entries. Align installer and import entry recognition in batch E; preserve .x precedence or explicitly reject unsupported installation. |
| D9 | verified | `src/parse.x:329-335` | Input claim: `import` only at top level. Review: Import handled at unit scope. Canonical AST placement must still be checked ordinarily; no origin-based exclusion. |
| D10 | overstated | `src/utils.x:223-234` | Input claim: Any file starting `#!` is source. Review: utils explicitly excludes c,h,o,a before shebang fallback; any file starting #! overstates. State fallback only for other suffixes. |
| D11 | decision | `src/parse.x:1986-1990`; `src/type.x:90` | Input claim: `^` declarator. Review: ^ parsed as modifier does not establish Apple Blocks support or intended contract. Keep as unresolved compatibility boundary. |
| D12 | overstated | `src/protocol.x:559-560` vs `src/parse.x:344-350` | Input claim: Unreachable "`static` applies only to concrete adoption" path. Review: parse.x:313-320 strips static protocol before parse_protocol_declaration; fresh protocol-static-abstract fixture translates. All two in-tree callers route through top-level. meta static body rejects earlier meta check, so static-body diagnostic is unreachable through current ordinary source. Public direct parser API/future callers are separate; no deletion requested or proven globally safe. |
| D13 | bounded source evidence | `language.md:135-192,2140-2143,3777-3818` | Input claim: Program startup and shutdown order across units. Review: Initialization and placement contracts already exist in the module/init reference and placement API. Consolidate their navigation. Full multiunit startup/shutdown permutations were not executed; do not invent a global order from registration implementation alone. |
| D14 | overstated | grep | Input claim: `.xmacro` files: none exist. Review: Absence of .xmacro files is an inventory observation, not language behavior; no repair. |
| D15 | fixed upstream | `28fc8c97`; `src/collect.x:_spells_block` | Baseline comment-prefilter failure was reproduced. At 9004c40b the conservative prefilter allows lexical recognition; the formerly failing opener and the new trivia fixture work. Preserve this repair, not another implementation task. |
| D16 | verified | `src/frontend.x:249-256` (the spliced text is tokenized once, as the entry); `src/collect.x:510` (layout from the entry path); probes `xp.xp`+`m.x` (`type: expected scalar type`), `mix.x`+`m.xp` (`parse: expected atomic expression`), `xp2.xp`+`m.xp` prints 4 | Input claim: Members are read in the entry's syntax mode. A `.x` member in a `.xp` entry and a `.xp` member in a `.x` entry both fail to parse; same-mode pairs work. Review: Frontend tokenizes assembled text once in entry mode. Splice scanner uses each path layout only to find block. Mode policy should be stated or deliberately changed; mixed-mode runtime probes not repeated here. |
| D17 | partly superseded upstream | `28fc8c97`; `Splice.block`; `src/preprocess.x:Compiler.preproc_open_state` | Baseline discovery read all module members before conditional hiding. Final-tip discovery first hides recognized unreachable arms. Missing member under #if 0 now succeeds; #if DISABLED with DISABLED defined as zero still reads and fails. Document the limited classifier; full native conditional dependency evaluation remains a separate choice. |
| D18 | verified | `src/collect.x:421-432`; probe `dup.x`: `dup/m.x:1:1: type: function 'g' is already defined in this scope` | Input claim: A member listed twice is spliced twice; no diagnostic at the block, only duplicate-definition errors located in the member. Review: Every listed member invokes s.file, but members map deduplicates hash key only. Duplicated code causes ordinary duplicate-definition diagnosis; no extra duplicate validator needed. |
| D19 | verified | `src/frontend.x:247-253`; probe `scr.x`; `plans/archive/module-blocks.md` "Result", last paragraph | Frontend scripts are converted then spliced. Existing module plan already records source-position limitations. Document supported syntax and retain limitation; avoid claiming all compile-time origins correct. |

## Types and protocols

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| T1 | verified | `lib/common.x:32-66`; `src/toolchain.x:188` | Input claim: Platform model (signed 8-bit `char`, LP64, two's complement, IEEE) only in static assertions. Review: common.x static assertions define current runtime platform constraints. Separate implementation contract from universal language mandate; no new -std decision needed for documentation. |
| T2 | verified | `language.md:3840-3843` vs `src/expressions.x:3694-3704` | Input claim: Sibling-typedef rule applies only to pointer targets. Review: _check_native_crossing restricts siblings only when target resolves pointer. Reference states broader rule. Intended policy requires decision; do not silently narrow normative semantics. |
| T3 | verified | `src/expressions.x:3685-3760`; fixtures `pointer-unrelated-argument`, `nonzero-integer-to-pointer` | Input claim: Unrelated-pointer and nonzero-integer-to-pointer errors. Review: Native crossing performs unrelated known-pointee/nonzero integer checks, intentionally excludes unknown types. Document exact decidable boundary. |
| T4 | verified | `values.md:131-136` vs `src/builtins.x:414-420` | Input claim: `class` reverse converters do not check the tag. Review: Shape.boxing uses Var_pointer without tag check for generated reverse converter. values guide guarantee conflicts; deliberate public contract decision before implementation. |
| T5 | verified | `src/symbols.x:1111-1137` | Input claim: Built-in numeric typedef table; `u128`/`i128` map to 64-bit. Review: builtin_typedef_scalars maps u128/i128 to long long. Public semantics not established; fallback semantic knowledge is not typedef declaration. |
| T6 | verified | grep of `lib/`, `include/` | Input claim: No C typedef is emitted for `u8`, `i32`, `f32`. Review: Fresh u8 declaration translates then native compile fails undeclared u8. Small fix depends whether shorthand intended public; do not automatically emit all fallback aliases. |
| T7 | verified | `language.md:2557-2558` vs `system-macros.md:242-248`, `lib/var.x:171-233` | Input claim: Descriptor capacity: "fixed capacity" vs any number. Review: Overflow descriptors allow further classes. Fixed capacity wording inaccurate; existing class-overflow fixture. Preserve separate worker-start freeze limitation. |
| T8 | verified | `language.md:3342` vs `:3379-3380`; `collections.md:683-684` | Input claim: Typed List bracket reads: inherited or rejected. Review: Fresh ListInt bracket read succeeds, returns Var 7. No typed getindex added, inherited List getter works. Guide phrase no Var adoption does not imply no bracket access. |
| T9 | verified | `language.md:3843-3845` vs fixture `sibling-typedef-assignment.diagnostics` | Input claim: `Array.arrayint` example does not match the diagnostic. Review: language.md:3841-3845 promises Array.arrayint permits ArrayDbl to ArrayInt crossing; fixture sibling-typedef-assignment.diagnostics asks for ArrayDbl_arrayint. Typed-array declares ancestor Array_arrayint, not sibling ArrayDbl_arrayint. Fix example to ancestor source conversion or name required sibling converter; do not silently relax crossing rule. |
| T10 | overstated | `language.md:672-673` only | Input claim: No parametric types; protocol `T` is a binder. Review: Protocols explicitly explain participant binder. Negative no-generics statement may help readers but absence is not a correctness defect. |
| T11 | verified | `lib/type.x:33`; `etc/builtin-macros.x:52` | Input claim: No declaration type inference. Review: auto storage/$auto cleanup distinction holds; documentation clarification, no inference implementation. |
| T12 | verified | `src/type.x:27-159`; `lib/type.x:63-140` | Input claim: Canonical Type List grammar (`(* X)`, `(dim N)`, `(func ...)`). Review: Type is canonical List grammar consumed structurally. Publish useful forms alongside position contracts, without origin authentication. |
| T13 | overstated | fixture `sibling-typedef-assignment.diagnostics` | Input claim: Type Lists appear in user diagnostics. Review: Diagnostic List rendering is observed format, not necessarily stability guarantee; document only if callers need it. |
| T14 | overstated | `src/symbols.x:950-983` | Input claim: Typedef chain depth limit 64. Review: Constants name 64 typedefs, actual enforcement is >128 hops; do not promise exact maximum chain depth without boundary probe. |
| T15 | verified | `src/expressions.x:3424,3526` | Input claim: Enums box as `<i32>` regardless of range. Review: Enum Var numeric crossings choose i32. Larger-range enum loss not runtime-probed; public range policy unresolved. |
| T16 | verified | `lib/typed-map.x:27-70`; `language.md:3838` | Input claim: Typed Maps are structs, not `Map` typedefs; substitution rules. Review: typed-map generates distinct structs. General typedef-substitution paragraph does not apply; document conversion operations rather than representation promise. |
| T17 | verified | `src/expressions.x:3449-3460`; `values.md:144-145` | Input claim: Unboxing to an unknown pointer typedef is unchecked (`Var_pointer`). Review: _read_var pointer fallback uses unchecked Var_pointer after checked readers/converters. Correctly scope to no checked reader, not all unknown typedefs. |
| T18 | verified | `lib/protocols.x:14-89` | Input claim: Built-in protocol inventory (`Cleanup`, `Block`, `Iter`, `Contains`, `Var`) has no page. Review: lib/protocols.x inventory has Cleanup Block Iter Contains Var. Lack of generated module page need not force new page; reference inventory can link source/book. |
| T19 | overstated | `language.md:806` | Input claim: The reference calls a guide chapter "normative". Review: A guide can be normative by explicit incorporation. Rearrangement is editorial choice, not contradiction. |
| T20 | reviewed with bounded execution | `docs/src/guide/protocols.md`; `src/protocol.x` (2856 lines) | Input claim: Protocols guide not verified against `src/protocol.x`. Review: Protocol contract inventory was compared with parse.x and protocol.x. Five existing runtime cases and three negative cases were replayed by the coordinator; fresh static-body and associated-type probes were also checked. Static protocol bodies are accepted privately, contradicting the adoption-only sentence. Protocol declarations retain AST nodes but create no runtime object. Repair those guide sentences. This is not exhaustive protocol conformance proof. |
| T21 | verified | `collections.md:931` vs `:1003` | Input claim: "six" vs "seven" packed Arrays. Review: collections.md:931 says seven, :1003 six. Correct count sentence to seven after checking family inventory. |

## Expressions

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| E1 | verified | `language.md:3210` vs `src/operator-ledger.x`; `protocols.md:321-323` | Input claim: `@` listed as a dynamic `Var` operator. Review: Same removed operator as S1; single docs correction, not independent feature decision. |
| E2 | verified | `src/component-operators.x:42`; `src/component-access.x:1-4,115,137-138`; `language.md:3318-3320` | Input claim: No general evaluation-order rule; dynamic `Var_binary` and `Array`/`Map` stores keep C order though the component header claims order. Review: Dynamic binary and exact Array/Map stores emit ordinary calls; participant store call_in_order differs. Compiler output sequencing trace needed for full guarantee. Current per-form docs already permit C order for indexed updates. |
| E3 | refuted | `language.md:3227-3229` vs `:3250-3252`; `src/component-operators.x:140-147`; `src/expressions.x:2537-2540` | Input claim: Unary `-` on `Var`: reference says `Var.neg` and also says rejected; no fixture. Review: Fresh Var w=-v works and prints -4. Var neg protocol resolves before fallback rejection. Correct summary and component-owner reference sentence to describe fallback eligibility, not remove supported unary minus. |
| E4 | verified | `src/expressions.x:1747-1824` | Input claim: Method resolution order and method-before-field rule. Review: resolve_postfix_member direct/import/protocol then field then ancestry in call context; arrow skips methods. Method-before-field is limited by context/type. |
| E5 | verified | `src/expressions.x:1803`; `from-c.md:71` | Input claim: No overloading; one `Type_method` C name. Review: One Type_member global symbol means no conventional overloads. ABI permanence is separate decision. |
| E6 | verified | `src/parse.x:2478`; `language.md:1136` | Input claim: `Owner.member` to `Owner_member` mapping; possible collision `A.b_c` / `A_b.c`. Review: Underscore mapping observed; collision candidate not probed. Do not add new mangling or validator from speculative collision. |
| E7 | overstated | examples only | Input claim: Static call spelling `Type.method(args)`. Review: Many examples establish spelling, but static/member designator grammar deserves brief rule. Missing formal sentence low priority. |
| E8 | decision | `language.md:594-597` | Input claim: Null receiver in method calls and delegation. Review: NULL passed to a method is not inherently UB: callee may accept NULL. Aggregate field dereference differs. Specify each operation; blanket null-receiver error would change runtime contract. |
| E9 | verified | `from-c.md:411` vs `src/component-printf.x:147-149` | Input claim: Computed printf format with a `Var` argument is an error. Review: component-printf rejects computed format when Var argument present; from-c wording should state rejection. |
| E10 | verified | `language.md:3238-3243` | Input claim: `===`, `!==` and C-literal-vs-`String` comparison are traps a spec must state precisely. Review: Reference explicitly limits literal conversion and unconditional identity. Keep semantics precise without labelling documented behavior defect. |
| E11 | overstated | `src/component-lambdas.x:12`; `language.md:3495` | Input claim: Lambda capture order wording: header "left to right", doc "first use". Review: Left-to-right order of capture row agrees with row built in first-use order. No contradiction unless declaration-order reading promised. |
| E12 | verified | `src/component-destructuring.x:78-88` | Input claim: Destructuring declaration: names in scope before the source is read. Review: Destructuring common-type expansion declares targets before source evaluation. Source-only; shadowing behavior probe still needed. |
| E13 | verified | `meta-functions.md:1578-1609`; `lib/meta.x:165-195`; `language.md:613,2799,3253,3694` | Input claim: `$rewrite` semantics (families, order, decline) defined only in a guide, the generated API page, and `lib/meta.x` comments. Review: Public rewrite semantics distributed; existing language-components-foundation plan overlaps. Reuse its decisions; canonical forms intentionally constructible. |
| E14 | overstated | `language.md:3189,3250-3254,3693-3695,3712` | Input claim: Reference mixes implementation owners (`src/component-*.x`) into normative text. Review: Implementation-owner prose is useful explanatory information. Label/move it, not treat all normative page implementation references as wrong. |

## Control flow

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| C1 | verified | `match.md:264-267` vs `lib/common.x:648-666` | Input claim: `match` on a non-List `Var` silently matches as nil. Review: Fresh non-List Var match selects nil pattern; Var.list checks tag and returns NULL. The guide promises a check that conflicts with observed coercion; intended matching behavior remains a decision. |
| C2 | verified | `src/component-match.x:374`; `match.md:32` | Input claim: `match` has no exhaustiveness check; a miss does nothing. Review: _match_lowered emits default break for no match. Reference omission can link guide; no exhaustiveness warning/process expansion authorized. |
| C3 | verified | `match.md:404-408`; `src/statements.x:50` vs `:465-470`; `language.md:1723-1726` | Input claim: Macro-derived `case` patterns accepted; guide and diagnostic text say otherwise. Review: Parser accepts List-typed pattern and component handles macro case. Guide literal-only statement too narrow. Preserve canonical constructed patterns. |
| C4 | verified | `match.md:276-279` vs `src/component-match.x:9-14` | Input claim: Inline-compiled pattern class understated. Review: Header explicitly lists literals, typed captures,nested Lists,final star. Low-priority implementation detail; not needed in normative matching semantics. |
| C5 | verified | `language.md:3607-3638`; `src/builtins.x:219-258` | Input claim: Two-name `foreach` over `List`/`Array` destructures; over `Map` gives key, value. Review: Cursor and Iter paths select values differently; builtins.x maps two List/Array bindings to destructured item. Document contrast without changing to index/value. |
| C6 | verified | `src/builtins.x:229-232` | Input claim: `foreach` loop variable is one binding for the loop (affects `using &v`). Review: Loop declares binding once outside while, updates each iteration. Reference capture consequences inferred, not executed. |
| C7 | overstated | `etc/builtin-macros.x:16-58` | Input claim: `foreach`, `class`, `$scope`, `$let`, `$lock` are built-in macros; spec status unclear. Review: Builtin macro implementation does not decide normative status. Shipped language can define features implemented as macros; no need split implementation category into public contract. |
| C8 | verified | `plans/string-switch.md:3-6`; fixture `rewrite-string-switch.x` | Input claim: String `switch`. Review: Existing active string-switch.md plan says no implementation; transform switch branch absent. Keep active plan, do not create duplicate design or codify permanent lack. |
| C9 | overstated | `language.md:3523-3526` | Input claim: C control flow covered in one sentence. Review: Language inherits C control semantics, so one sentence is not itself gap. Describe deliberate divergences and cleanup additions, not duplicate C standard. |
| C10 | verified | `iteration.md:155-156` vs `:62-64,105-106` | Input claim: `iteration.md` "no heap allocation" contradicts itself. Review: iteration guarantee no heap allocation is too broad relative cursor/String paths. Narrow to traversal state where applicable. |
| C11 | decision | `iteration.md:144-147` | Input claim: Non-convertible `foreach` type is left to the C compiler. Review: Element conversion failure delegated to native compiler may be deliberate C boundary. Probe specific nonconvertible binding before proposing x2c diagnostic. |
| C12 | verified | `language.md:3708-3712` vs `src/component-raise.x:21-26` | Input claim: `raise` detail types: whether `NULL` and enums are accepted. Review: Fresh translation enum detail succeeds; untyped $NULL detail rejects raise detail type () is not immutable. This distinguishes untyped NULL from a Var Null value; do not claim all null details fail. Book allowed Null payload can remain, but explicit raw NULL usability needs intent decision. |
| C13 | verified | `src/cleanup.x` handles listed transfers only | Input claim: `exit()` or `longjmp` across `defer`. Review: Fresh foreign-exit prints before but no cleanup; foreign-jump returns to setjmp with cleaned=0. cleanup.x:435-463 lowers lexical return/break/continue/goto and blocks, not arbitrary foreign calls. Document native exit/longjmp bypass; adding cleanup interception would be public behavior/API change. |
| C14 | verified | `lib/system-macros.x:86-96` | Input claim: `$switch` system macro versus C `switch`. Review: system-macros.x:86-96 supplies separately named $switch decorator. Informative distinction suffices; no new core switch semantics. |

## Macros and compile-time execution

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| M1 | verified | `language.md:2453-2480`; `src/parse.x:3073-3166`; `src/expressions.x:1040-1101` | A central public source-form catalog is missing. Existing named-type/bundle forms already have normative shapes; do not claim no shapes are documented. Extend that owner with templates, positional contracts, and examples. |
| M2 | decision | `src/parse.x:3090-3166`; `language.md:2506-2521` | Reachability is not a compatibility promise. Catalog source forms and opaque binding records separately from bound/lowered compiler API forms. No origin authentication or recursive validator. |
| M3 | overstated | `src/expressions.x:1101`; `language.md:2478-2480` | Resolve._content fallback returns input, but that alone proves neither acceptance nor miscompilation. Downstream generation may reject it. Preserve deliberate nonrecursive annotation trust; reproduce harmful wrong output before proposing validation. |
| M4 | verified | `language.md:2296-2299` vs `src/stage.x:234-238`, `meta-functions.md:877` | Fresh Array/Map insertion is implemented; meta-fresh probe prints 1 2 1. Correct the opposing reference sentence, preserving cycle/shared-collection rejection. |
| M5 | verified | `language.md:2319-2320`, `meta-functions.md:1661-1663` vs `language.md:2343-2345`, `src/meta-helper-client.x:129-150` | Compiler-answered project queries are explicit in reference:2343-2345, guide:1426-1429, and client dispatch. Delete stale arguments-only restriction; no new query subsystem. |
| M6 | verified | `meta-functions.md:3,927-928` vs `:698-699` | Guide:698-699 explicitly selects --meta-cc default cc, never target --cc; opening/results text is stale. Correct those sentences. |
| M7 | decision | `language.md:1000-1003` vs `src/macros.x:793-794` | Definition.naming only reserves x2c., at src/macros.x:793. A documented reservation can constrain users without enforcing every misuse. Decide intended lisp.* reservation before adding checks or deleting the promise. |
| M8 | verified | `language.md:1057-1061` vs `src/macros.x:1539-1547` | untyped_roles excludes name; hole-name probe fails on int $name=1. Existing explicit Name hole is the minimal usable route. Decide inference extension versus wording correction. |
| M9 | verified | `language.md:1464`; `plans/archive/x2c-metalanguage.md:308` vs `src/macros.x:1325-1345` | No Block macro category exists; Stmt owns block syntax. Fix spelling, with no new category. |
| M10 | overstated | `language.md:1452-1464` vs `etc/builtin-macros.x:54-58` | NamedType is a decorator target; MatchRow is a hole only, target=0 in category table. Adding MatchRow to decorator targets would be a new feature. Correct only supported target list. |
| M11 | verified | `language.md:1043-1049` vs `src/macros.x:838-856` | Local Unit/Declaration results and Function/Unit/NamedType decorators are rejected by check_signature. Reference should list these; grammar already does. |
| M12 | verified | `src/macros.x:2459-2486`; fixture `foreach-keyword-collision` | _fixed_alias and alias_kinds establish restrictions. Add short reference cross-reference; reuse existing collision fixture. |
| M13 | verified | `macros.md:332-334`, `language.md:1375-1376` vs `:1797-1804` | Legacy-for-all text contradicts signature using example for Expression. Describe supported roles and remove broad legacy characterization; do not remove syntax. |
| M14 | verified | `src/macros.x:450-454` | 10000 application cap exists. Missing exact-limit fixture is coverage information, not a reproduced defect or justification for recurring expensive checks. |
| M15 | refuted | `lib/lisp.x:375,1001,1036,1161`; `language.md:2323` gives no values | 40M steps, 6 MiB stack, depth1024 are source limits. Eight arguments is NOT a limit: lib/lisp.x:373-394 allocates wider argv in Scope. lisp-nine probe prints 9. List three implementation limits, not four normative caps. |
| M16 | overstated | `lib/lisp.x:309-322,440-452,1253-1254`; `etc/init.xlisp` | Dialect facts are split among source comments, generated module API and etc/init.xlisp; not wholly undocumented. Add one compact compile-time Lisp contract, linking API instead of reproducing entire library. |
| M17 | verified | `library/modules/lisp.md:757` vs `lib/lisp.x:1253-1254` | Header at lib/lisp.x:8 says nil only; lisp_truth:1254 says nil and void. Generated page also has correct lisp_truth text. Edit authoritative header and regenerate page. |
| M18 | verified | `src/macros.x:4912-4968`; `language.md:2110-2115` | Effects are rewrite/new-name/cleanup/place. early absent. Separate source API from provisional bound/lowered carrier mechanics; do not publish every internal stage as language syntax. |
| M19 | decision | `lib/meta.x:198-200`; `src/meta-sdk.x:474-481` | No ordinary source callers found, but public prototype + linked sdk implementation is a consumer-facing API. Absence of repository calls does not prove dead API. Follow deprecation/usage decision before deletion. |
| M20 | overstated | `lib/meta.x:113-161,209-279,368-388`; `language.md:1972-2005` | Operations are documented in authoritative lib/meta.x and generated meta page. Lack of duplicated language-reference details is not absence. Link generated API and make semantics complete at its owner. |
| M21 | overstated | `lib/meta.x:63-71`; `meta-functions.md:981-990` | lib/meta.x:63-71 specifies TypeInfo and Source shapes; guide covers them. Reference can link these contracts rather than duplicate record layouts. |
| M22 | overstated | `language.md:2455-2456` vs `:2105`; `src/parse.x:3150-3152` | Parsed captured AST strips source at wrappers; enclosing statement can return compiler-origin source anchoring. Distinguish APIs; no blanket removed-everywhere claim. |
| M23 | verified | `macros.md:124-136,215-223`; `language.md:1228-1236` | Guide tables incomplete against macro_categories. Link canonical complete reference table and retain only teaching examples locally. |
| M24 | verified | `src/grammar.x:114`; `meta-functions.md:1186` | Entry sequence syntax exists; add to existing splice contract/example without separate chapter or grammar owner. |
| M25 | refuted | `language.md:2098-2144,2347-2351`; `meta-functions.md:1534-1556` | Reference:2347-2351 explicitly defines x2c helper underscore-to-dot Lisp mapping. Both spellings are correct in different language contexts. Keep each contextual spelling. |
| M26 | verified for grouping examples | `language.md:1099-1103` | Fresh grouping prints 84/6/0 for result multiplication, operand addition and negated comparison. Generated C selectively groups operands/results; global minimal-parentheses claims remain unproved. |
| M27 | refuted | `language.md:1939-1950` | Re-read lib/lisp.x:461-478,1818-1844,1998-2007. def rejects protected/inherited/frozen names; host set_global can shadow inherited/protected bindings but rejects frozen session. Distinction already documented. |
| M28 | overstated | `src/compiler.x:2344-2365`; `src/macros.x:2851-2856`; `src/transform.x:118,362-386`; `meta-functions.md:1578-1596`; `agents/lowering-with-macros.md:252-258`; fixture `rewrite-function-written` | Written-definition mechanism verified; direct source function with trailing kernel fails binding while unmarked control compiles. Source binder src/parse.x:3130 accepts four fields. Constructed bound/lowered carrier bypass is not tested. Do not promise kernel as public source AST or add origin tracking. |
| M29 | known open work | `plans/language-components-foundation.md:825-826` | The foundation plan already records self-meta rewrite observation inconsistency. No new full reproduction was performed. Retain the existing continuation owner and require focused reproduction before its repair; documentation alone cannot close it. |

## Runtime ownership

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| R1 | verified | `memory.md:65-67,108-112` vs `lib/scope.x:499-506,581-584,703-714` | scope-catch prints caught. Correct memory guide; the shared bad-state cause transfers to a matching catch or terminates. Abort is the default uncaught consequence, not a universal rule. |
| R2 | verified | `memory.md:239-241` vs `lib/scope.x:1025-1036` | Detached probe emits leak report but no finalizer. Shutdown releases thread root chain, not every detached owner. Qualify shutdown finalizer promise by ownership/reclamation. |
| R3 | verified | `lib/scope.x:106-118,208-214` | TLS active Scope is explicit; allocation records have mutable unprotected fields. Guide already places synchronization responsibility on shared mutable objects. Document Scope confinement at API owner; do not infer supported cross-thread Scope sharing from locks elsewhere. |
| R4 | decision | `lib/scope.x:309,704`; `lib/mutex.x:93-133`; `lib/thread.x:293,333` | API-specific null behavior is deliberate contract variation, not a defect. Retain per-method contracts; global uniformity would change caller obligations. |
| R5 | verified | `lib/list.x:301-311`; `lib/buffer.x:275-281` | Document convert-and-free convention in library overview if useful; do not treat suffix as a universal semantic operation without inventory. |
| R6 | overstated | `memory.md:43-45` vs `lib/common.x:87-100` | memory guide introductory list is illustrative, not exhaustive. Common.x ownership comments can be canonical complete inventory. Missing types alone are low-priority clarity work. |
| R7 | verified | `memory.md:83` vs `:98` | Named request source prints forgotten expectation. Correct expected output and run optional focused doc sample. |
| R8 | verified | `agents/x2c-philosophy.md:833-850` | Philosophy explicitly states output parity does not prove transient reclamation. Keep limitation; optional instrumented batch memory probe, no new gate. |
| R9 | refuted | `regions.md:148-156` | Region guide already documents per-unit/cross-unit limitation at148-156. This is a supported limit, not an undocumented ambiguity. |

## Errors, interoperability, and platform boundaries

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| X1 | overstated | `memory.md:305-307`; `exceptions.md:237-239`; `language.md:3754` vs `lib/error.x:430-437,487-489` | Floor abort occurs without transfer; Error transfer cleanup wording is correct for actual selected transfer. memory guide passes-through/finally propagation wording is broad. Qualify with selected catch and ordinary floor; do not silently choose new universal cleanup semantics. |
| X2 | overstated | `lib/error.x:1302-1316`; `src/compiler.x:1471-1498`; `lib/exception.x:241-244` | Mechanisms differ, but script cmd-fail preserves command status, not always1 (compiler.x:1488-1491). 134 is Unix-shell convention, not portable exit guarantee. Describe abort, script status propagation, and exit(1) separately. |
| X3 | verified | `src/compiler.x:1492-1496`; `lib/error.x:444-458` | Generated script broad catch selects before policy table. Program and script policy behavior differ; characterize before deciding consistency change. |
| X4 | overstated | `wrapping-c-libraries.md:400-446` | Interop guide is existing book semantic owner. Cross-link it from reference; do not create independent duplicate C-frame cleanup contract. |
| X5 | overstated | `src/generate.x:1496-1509`; `lib/error.x:196-199` | Generated main initializes; common.x:841-856 is process-once initialization. This is necessary for initial embedding but insufficient foreign-thread setup. Do not publish call-initialize-only recipe for all embeddings. |
| X6 | decision | `src/generate.x:440-449` | Code generation infers _Noreturn. Public source semantics and C interface promise require separate decision; document observable behavior first, retain generated implementation detail informative. |
| X7 | decision | `language.md:3767-3773` | Reference limits guarantee to tested optimized repository build. Broader compiler/flag guarantee needs evidence; wording choice cannot establish portability. |
| X8 | verified | `lib/error-macros.x:15-20` | Public fallback macro exists; add user-defined cause example to existing errors guide and link it. Do not apply fallback to shared nonreturning causes. |
| X9 | verified | `src/toolchain.x:188-191`; `src/emit.x:917`; `language.md:3968` | No driver -std default; GNU extensions and POSIX transfer primitives are used. Describe supported toolchain requirements rather than asserting all generated output always uses every extension; explicit -std is a behavior change requiring native validation. |
| X10 | decision | `values.md:317-320`; one "undefined" in `language.md:3374` | C semantics baseline exists, but explicit UB boundary and defined Var arithmetic exceptions deserve concise documentation. Do not promise defined arithmetic universally. |
| X11 | overstated | no "implementation-defined" in the book | No catalog verified, but absence of literal terminology is not absence of individual constraints. Add short boundary/index, not an exhaustive new language-lawyer specification prerequisite. |
| X12 | overstated | `lib/thread-state.x:13`; `lib/thread.x:212-213` | Fresh foreign thread Error readiness is TLS false; Thread wrapper explicitly initializes/releases. Blanket cannot-raise/leaks claims overstate callers that manually initialize/release. Support contract is undecided; no foreign-thread runtime probe here. |
| X13 | decision | `contexts-and-threads.md:96-101` | Guide already assigns ordinary C race responsibility. Specify supported cross-thread ownership/immutable sharing under that existing model; adding atomics model or new runtime synchronization is beyond doc repair. |
| X14 | verified | `src/toolchain.x:205-212`; `src/cli.x:338,631` | Driver honors requested -pthread. It is documented in build help and CLI. Not automatic is a tooling fact, not a language defect. |
| X15 | verified | `cli.md:686-687` vs `src/cli.x:209-210` | Hidden fatal-warnings exists and stages use it. Correct CLI sentence to user-facing supported controls versus internal stage option; do not make hidden option public incidentally. |
| X16 | refuted | `cli.md:729-730`; `src/diagnostics.x:130-131` | Such-as diagnostic examples do not promise exhaustive taxonomy. Registry/catalog only if a consumer requires stable machine codes. |
| X17 | verified | `implementation-map.md:321-327` vs `src/diagnostics.x:39-41`, `src/cli.x:1251` | diagnostics-file logging exists; CLI max-errors default20 differs from low-level default. Repair implementation map naming component and context. |
| X18 | refuted | `language.md:4056-4073` vs `cli.md:690-708` | Region chapter owns region diagnostics; CLI owns complete warning catalog. Cross-reference is sufficient; duplicate full catalog would invite drift. |
| X19 | refuted | `agents/x2c-philosophy.md:626-653` | language.md:3775 already says Error transfer does not restore signal mask. Callable cleanup representation belongs to internals; no language gap follows from omission. |
| X20 | decision | `language.md:2009-2010`; "provisional" label on compiler API | Compatibility policy is product decision. Distinguish language from provisional compiler API; do not upgrade internal forms to stable ABI simply because reachable. |

## Documentation organization

| ID | Disposition | Owner or evidence pointer | Assessment and remediation |
| --- | --- | --- | --- |
| O1 | verified | `docs/src/index.md:23`; `site/src/content/home.md:19` | Slice absent current runtime; remove stale feature overview item. |
| O2 | verified | `implementation-map.md:63-110,281-285` | Map old feature paths to components plus ordinary binder/transform owners. Keep map informative; verify references and generated module catalog. |
| O3 | verified | `agents/x2c-code-standard.md:1170` | Removed Ast.try_sequence remains cited. Replace with current operation/example after tracing; do not recreate API. |
| O4 | verified | `agents/x2c-docs-drift-report.md:31` | _path_audit has20 entries. Correct count or remove fragile prose count. |
| O5 | verified | `symbols.md:157` vs `lib/atom.x:146,172` | Atom.hash is descriptor member; correct guide terminology. |
| O6 | overstated | `system-macros.md:18` | Explicit import can mean generic inclusion in English. Prefer explicit include for precision, low priority rather than semantic defect. |
| O7 | verified | `macro-at-splicing.md:3-14`; `quotation-adoption-audit-2026-10-03.md:259-262`; `x2c-metalanguage.md:300-310,388-391`; `language-components-foundation.md:39-40` | Plans are histories; stale top status matters only where it falsely claims current work. Correct status while preserving dated implementation records; foundation log supersedes opening boundary. |
| O8 | overstated | `Makefile:192-195,215` | Optional examples are explicitly Gary policy in Makefile:192-195. Ignored examples have required reason comments. They are not accidental gate omissions; exact counts not independently recounted here. Do not add recurring requirement. |
| O9 | overstated | `docs/src/library/modules/` | 26 missing pages confirmed by set difference, but most are generated/private/internal units. Evaluate public exports rather than mandate one page per lib file. protocols inventory can link semantic reference. |
| O10 | overstated | `examples/tours/language.x` | A tour may deliberately sample language; no completeness promise established. Add examples only for a concrete learning goal, not every feature inventory. |
| O11 | verified | `docs/src/index.md:68-70`; `tools/check-doc-examples:126` | Compile-only samples produce objects; outputs samples link and run. Clarify index wording and optional policy. Do not imply every sample is fully linked. |

## The 35 questions

These are dispositions, not 35 requests for permission. Discoverable facts and
editorial repairs can proceed during a later authorized implementation.
Consequential choices are collected in batch G rather than hidden in tests.

| Question | Resolution or next action |
| --- | --- |
| Q1: `@` | Removed deliberately. Correct stale syntax/reference claims; do not restore an operator to satisfy old prose. |
| Q2: uncaught cleanup | Selected Error transfer runs cleanup; the uncaught floor aborts without that transfer. Qualify prose now. Universal cleanup before abort would be a semantic change. |
| Q3: termination status | Describe program abort, script command-status propagation, and explicit exit separately. Do not unify them without a product decision. |
| Q4: non-List match | Current Var-to-List conversion yields nil and a nil pattern can match. Decide whether that is intended or whether the guide's rejection promise governs. |
| Q5: Var negation | Works through the protocol member. Correct the study and misleading fallback paragraph. |
| Q6: inserted collections and compiler queries | Fresh mutable insertion and compiler-answered project queries exist. Correct stale restrictions at their owners. |
| Q7: scalar sibling typedefs | Existing enforcement concerns pointers. A universal scalar separation rule needs a deliberate compatibility decision. |
| Q8: class unboxing | Generated converter behavior and advertised tag checking disagree. Decide checked conversion expectations before adding runtime checks. |
| Q9: typed Lists | Inherited bracket access works and returns Var. Correct contradictory prose; no second getter path. |
| Q10: Scope misuse | Extra release is catchable through the shared Error cause. Abort is the default uncaught consequence, not a universal result. |
| Q11: reserved Lisp namespace | Distinguish a documented user reservation from compiler enforcement. Choose enforcement or wording only if the reservation's intended scope is unsettled. |
| Q12: untyped name holes | Explicit Name holes are the existing route. Extending inference is optional language work, not required to document current roles accurately. |
| Q13: signature `using` | Supported roles include Expression. Replace legacy-only wording without removing the syntax. |
| Q14: canonical AST catalog | Catalog ordinary source forms, positions, and opaque bindings. Do not publish every internal bound/lowered carrier as source syntax or authenticate origin. |
| Q15: rewrite contract | Complete ordering, decline, placement, and visibility contracts at the existing owners. Expression visibility and bound-carrier stability remain distinct decisions. |
| Q16: built-in macro status | Implementation as a macro does not make a shipped feature non-language. Describe user semantics without exposing internal implementation classes. |
| Q17: String switch | Already has an accepted, unexecuted plan. Refresh obsolete APIs there; preserve feature semantics and implementation status. |
| Q18: C compatibility | Treat caret declarators, bool/typedef behavior, and extension support separately. Parser acceptance does not establish native toolchain support. |
| Q19: numeric shorthand | Semantic fallback names do not necessarily emit native typedefs. `u8` native failure and `u128` width mapping require an explicit supported-name boundary. |
| Q20: packages | Nested imports and included imports worked in fresh linked probes. Legacy lookup remains supported. Repair the separately reproduced `.xp` install/import mismatch. |
| Q21: protocol authority | A guide can own semantics when explicitly incorporated. Correct its two verified contradictions; moving the chapter is not a prerequisite. |
| Q22: platform model | State tested/native requirements, including signed-char and width assumptions. A universal C dialect or new default `-std` is a separate compatibility choice. |
| Q23: undefined behavior | Document inherited native-C boundaries and explicitly defined dynamic operations. Do not promise universally defined arithmetic or foreign-call cleanup. |
| Q24: ABI | Generated spellings and inferred `_Noreturn` are not automatic stability promises. A collision or external compatibility repair requires a concrete caller/probe. |
| Q25: embedding | Separate process initialization from foreign-thread initialization and teardown. Process-once initialization alone is not a complete foreign-thread recipe. |
| Q26: evaluation order | Preserve established per-form sequencing. A universal left-to-right rule would change semantics and requires a complete lowering inventory. |
| Q27: declaration order | Complete-unit function collection supports forward calls, including module members. Correct the blanket prototype requirement. Private type forward-use remains a separate unexecuted boundary. |
| Q28: include search | Different translation/native search orders are different tool contracts. Document them without automatically unifying the implementations. |
| Q29: limits | Document actual implementation limits. Eight Lisp native arguments is a fast-path threshold; typedef-chain enforcement is not simply a guaranteed depth of 64. |
| Q30: namespaces | State reserved names with import/package and scope context. No universal new reservation or collision validator follows from a summary omission. |
| Q31: fatal warnings | Distinguish public CLI controls from the hidden stage option already in use. Making it public is an independent choice. |
| Q32: unused API | No repository callers does not prove no external callers. Preserve public API until usage and compatibility are assessed. |
| Q33: grammar checks | Optional syntax checks do not prove parser equivalence. New recurring checks need explicit approval and comparable work removed or consolidated. |
| Q34: module syntax mode | Recommend the existing entry-mode textual assembly contract. Independently parsed member modes would change the architecture. |
| Q35: conditional modules | Final-tip discovery suppresses recognized unreachable arms, but unresolved native conditions still allow eager reads. Document the existing classifier. Full native conditional dependency evaluation would be additional behavior. |

## Appendix crosswalk

The older appendices describe `1e90f378`. Repeated claims inherit the current
main-row assessment rather than becoming independent findings. Their stale
line citations and historical counts must not become current proof.

- Appendix A drift D1-D23 maps respectively to S1/E1, L1, L3, S2/L11, S3,
  S4, S5, S6, S7, S8, S8, S9, S10, S11, S12, S14, S15, L13, L14,
  S16, anonymous Stmt-arrow grammar, L16, and L2. The anonymous Stmt-arrow
  production needs the parser's existing contextual route, not a new feature.
- Appendix B numbered gaps 1-36 map respectively to D1, D2, T1, T2, T3,
  T4, T5, T6, T7, T8, T9, D3, D4, D5, D6, L8, L9, T10, T11, S13,
  T19, D11, D8, D7, D10, T14, T15, T13, T12, T21, O6, T16, D9, T17,
  D14, and D12.
- Appendix C numbered gaps 1-30 map respectively to E1, C1, E2, E3, C2,
  private match dispatch, C3, E4, E5, E7, C5, C6, C7, C8, C9, E12,
  E2, C10, C11, E9, C4, S19, E11, E8, C12, S20, T20, C13, C14,
  and E10. Private match dispatch is an implementation explanation, not
  missing public syntax. The separately named `$switch` macro is not
  ordinary String switch.

| Appendix D gap | Main ID or disposition | Additional evidence/acceptance |
| --- | --- | --- |
| D.C1 | M1 | Source-form catalog, not copy of every internal dispatch arm. |
| D.C2 | M2 | Include declaration-initialized in scope inventory; stability decision remains. |
| D.C3 | M3 | Unvalidated fallback alone is not wrong-output evidence. |
| D.C4 | M4 | meta-fresh reproduced. |
| D.C5 | M5 | Compiler helper query client and guide establish live query route. |
| D.C6 | M6 | --meta-cc is explicit current host selector. |
| D.C7 | M7 | Namespace contract decision. |
| D.C8 | M8 | Untyped declarator-name probe rejects. |
| D.C9 | M9 | No Block row. |
| D.C10 | M10 | MatchRow target claim refuted; NamedType supported. |
| D.C11 | M11 | Existing check_signature owner. |
| D.C12 | M12 | Existing alias restrictions. |
| D.C13 | M13 | Signature using semantics retained. |
| D.C14 | verified | src/macros.x:_name accepts keywords after dot; grammar macro-name must match. Parser owner remains; lexical trivia claim needs independent exact examples. |
| D.C15 | M14 | Exact-count coverage absent; no new recurring gate. |
| D.C16 | M15 | Eight is fast-path threshold, nine native args reproduced. |
| D.C17 | M16 | Existing source/API docs plus compact dialect contract. |
| D.C18 | M17 | Edit lib/lisp.x header, regenerate. |
| D.C19 | verified/decision | lib/meta.x:165-195 documents rewrite families, ordering and decline. Full reference definition missing; add reference section linking API, correct stale lifted-lambda statement. Public carrier stability separately undecided. |
| D.C20 | M18 | early removed at current baseline. |
| D.C21 | M19 | No repo calls does not prove no outside callers. |
| D.C22 | M20 | Existing generated API is semantic owner, reference links suffice. |
| D.C23 | M21 | Shapes documented in lib/meta.x. |
| D.C24 | M22 | Captured syntax versus enclosing anchored item. |
| D.C25 | unverified | Parser quotation branches at src/macros.x:1620-1627 show category parsing, not full behavioral proof of every quoted category. Preserve position constraints; focused accept/reject quotations before changing spec. |
| D.C26 | M23 | Guide holes. |
| D.C27 | M23 | Guide results; canonical table covers Declaration/Decorator. |
| D.C28 | M24 | Entry splice reference example. |
| D.C29 | verified | src/macros.x:1392-1400 parses body using; EBNF needs that production. No alternate parser. |
| D.C30 | refuted as gap | No .xmacro implementation required by current ordinary .x module contract. Do not add extension to satisfy a brief's unsupported premise. |
| D.C31 | O7 | Historical versus top-level status distinction. |
| D.C32 | M27 | Source re-read settles host/Lisp distinction. |
| D.C33 | M26 | Grouping examples execute correctly; global parenthesis minimality remains unproved. |

| Appendix E gap | Main ID or disposition | Additional evidence/acceptance |
| --- | --- | --- |
| E.C1 | X1 | Actual selected transfer versus abort floor. |
| E.C2 | X2 | Script command failures preserve status; not universally1. |
| E.C3 | X3 | Broad generated catch precedes policy. |
| E.C4 | X8 | fallback user-cause example. |
| E.C5 | X6 | Generated ABI versus language promise. |
| E.C6 | X7 | Preserve proven compiler/flag scope. |
| E.C7 | X4 | Cross-link existing native crossing owner. |
| E.C8 | X5 | Process initialization insufficient foreign-thread recipe. |
| E.C9 | R1 | Catch probe passes. |
| E.C10 | R2 | Detached probe confirms callback omission. |
| E.C11 | R7 | request versus forgotten. |
| E.C12 | R3 | TLS Scope and caller race obligations. |
| E.C13 | R4 | Per-method null semantics. |
| E.C14 | R5 | Suffix convention low priority. |
| E.C15 | R6 | Illustrative introductory list. |
| E.C16 | R8 | Contract already explicitly partial. |
| E.C17 | X12 | Fresh foreign thread unsupported inference, not universal impossibility. |
| E.C18 | X13 | Existing C race model. |
| E.C19 | X14 | Driver flag documented in build help. |
| E.C20 | X15 | Internal stage option exists. |
| E.C21 | X16 | Nonexhaustive example taxonomy is intentional possible scope. |
| E.C22 | X17 | File logging exists. |
| E.C23 | X17 | Distinguish CLI default20 from low-level operation. |
| E.C24 | decision | src/parse.x method naming maps member separator to underscore. ABI collision not reproduced; do not mandate collision diagnostics based on speculative spelling. Lookup precedence is source-reviewed; no ABI-collision runtime reproduction is claimed. |
| E.C25 | X9 | GNU/POSIX support boundary. |
| E.C26 | decision | lib/common.x:32-66 asserts signed8-bit char, native widths, two's complement, binary32/binary64; driver -fsigned-char. This is verified implementation support, not evidence Gary chose permanent language restriction. |
| E.C27 | X10 | Native UB versus dynamic defined operations. |
| E.C28 | unverified | src/expressions.x:1752-1756 prioritizes method lookup in call context, but field-collision outcome not probed here. Retain as an unexecuted collision scenario, not an accepted defect. |
| E.C29 | X19 | Signal-mask behavior already in reference, representation informative. |

| Appendix F gap | Main ID or disposition | Additional evidence/acceptance |
| --- | --- | --- |
| F.D1 | S1/E1 | Arithmetic @ removal belongs lexical/expression review. |
| F.D2 | C1/C3 | Macro pattern behavior belongs statement/match review. |
| F.D3 | D.C19/M18/M28 | Add one rewrite contract; fix authoritative API conflict. |
| F.D4 | decision | Implementation owners are useful informative references; remove only if reorganized, not because paths inherently invalidate normative prose. |
| F.D5 | M16 | Compact dialect section plus API links. |
| F.D6 | X13/R3 | Existing guide already covers races/Context isolation. |
| F.D7 | L5/L6 | Scanner encoding boundary is source-reviewed; no new String Unicode contract inferred. |
| F.D8 | X11 | Catalog absence not every constraint's absence. |
| F.D9 | E2 | Multiple native/introduced operation orders; one universal rule would change semantics. |
| F.D10 | verified | Built-in protocol inventory exists lib/protocols.x:14-58. Reference inventory links current normative protocol contracts; generated page omission alone is not API gap. |
| F.D11 | X18 | Complete warning catalog stays CLI owner. |
| F.D12 | decision | Optional syntax-spec staleness check does not prove parser equivalence. No new recurring gate authorized. |
| F.D13 | O8 | Gary expressly made examples optional. |
| F.D14 | refuted as shipped feature | plans/string-switch.md remains plan; rewrite fixture implements user translator. Do not specify ordinary built-in String switch. |
| F.D15 | O1 | Stale Slice feature prose. |
| F.D16 | O2 | Current component map. |
| F.D17 | L5/L7/S rows | Concrete scanner probes required; no language validation added here. |
| F.D18 | X20 | Product/API stability decision. |
| F.D19 | overstated | Startup ordering is already specified piecemeal at reference module/init sections and placement area contract. Consolidate navigation, preserve canonical program-structure owner. Full cross-unit shutdown order not probed. |
| F.D20 | R8/R4 | Existing partial status truthful; no forced uniform null/exhaustion convention. |

## Coverage of summaries and the proposed specification

Sections 2.1-2.6 and the corresponding A-C appendices were compared with the
scanner, tokenizer, parser, expression ladder, literal decoder, binder, and
lowering owners. The precedence ladder agrees with the operator ledger;
prefix/cast recursion and special operand contexts need grammatical treatment,
not just a numbered precedence table. Token spellings inside percent forms
must be distinguished from raw source spellings. Accepted parse shapes still
face typing, placement, emission, and native-C constraints.

Sections 2.7-2.9 and D-E were checked against macro category tables, signature
checks, rewrite/placement operations, the Lisp evaluator, Scope, Error, Thread,
and the native boundary. Fresh probes settle the consequential corrections
recorded above. Full quotation-category permutations, every Error policy,
foreign-thread stress, cross-platform ABI behavior, and every constructed
bound/lowered carrier were not executed. None is declared defective merely
because the study or this assessment lacks that coverage.

Section 3 and appendix F correctly identify documentation drift but overstate
several absences. Generated API pages already own contracts; the protocol guide
is explicitly incorporated; signal-mask and region limits already exist.
`doc-check` checks some structure and inventories, but not arbitrary semantic
truth. Historical sample counts and missing-page counts do not measure language
correctness. Optional examples and syntax checks are deliberate policy.

Section 0's written-definition succession is real, including the removed early
effect and ordinary void prototypes. The alias-forwarder path remains an
exception needing repair. The old meta API comment still promises lifted lambda
visibility and must follow the newer design. The older appendices must not
reverse that succession or imply modules were part of their earlier grammar.

The sixteen-chapter outline is useful as navigation, not a prerequisite rewrite.
Preserve one owner for each contract:

| Proposed material | Existing owner and consolidation |
| --- | --- |
| Lexical rules, grammar, expressions | Existing generated syntax data plus language reference. Correct their context and evidence before splitting chapters. |
| Types and compile-time Type Lists | Type semantics stay in the reference; construction/inspection APIs link them. Opaque bindings stay opaque. |
| Statements, Errors, lifetime | Statements own syntax; Errors own transfer and termination; lifetime owns cleanup ordering and acquired values. Cross-link instead of repeating contracts. |
| C interoperability and embedding | Native crossing and entry obligations remain in the wrapping guide/reference. Error consequences link that owner. |
| Values, truthiness, Lisp | Separate Var/C truth from the Lisp dialect's nil/void rule. One compact Lisp section links its generated API. |
| Concurrency | Preserve native C race obligations and Thread/Context/Scope ownership limits. Do not invent an atomics model as editorial work. |
| Metaprogramming | Catalog ordinary canonical source forms and rewrite/placement contracts. Internal carriers are not automatically stable source forms. |
| Diagnostics | CLI owns the complete warning catalog; region semantics link it. Do not duplicate all codes into another chapter. |
| Library annex | Link generated API contracts; do not downgrade them to merely informative copied signatures. |
| Implementation annex | Architecture and implementation map own informative generated-C routes. Repair current owners there. |
| Rationale/history annex | Link plans with current statuses. Preserve dated decisions; historical text does not automatically supersede current semantics. |

Repair confirmed contradictions first, then add the compact AST/rewrite/Lisp
contracts, then improve navigation. No new parser, origin tracking, second
validator, or recurring conformance gate follows from this organization.

## Draft EBNF and precedence review

The draft is a useful parser-extraction sketch, not a complete acceptance
specification. Every production family was compared with its existing owner.
Nine focused translation probes were independently replayed by the coordinator.
Eight reject draft-admitted forms; the do/while probe translates without a
terminating semicolon. No formal equivalence proof or exhaustive token corpus
was attempted. Translation alone does not prove native compilation or intended
semantics.

| Production family | Source owner | Assessment and correction |
| --- | --- | --- |
| Entry, scripts, modules, linkage | `src/parse.x:307-397,506-565`; `src/collect.x:342-432` | Static typedef needs outer termination. Module splicing occurs before the parser and cannot simply recur inside linkage groups. Script orchestration also establishes context and restrictions. The baseline comment rejection was a prefilter defect repaired at the final tip; neither it nor blanket eager reads belongs in the grammar. |
| Imports, directives, static assertions | `src/parse.x:632-642` and import handling | Package/export resolution and retained preprocessing directives are semantic/contextual leaves. Static assertion shape does not prove constant-integral/native validity. |
| Declaration rows and specifiers | `src/parse.x:917-947,1026-1094,1290-1470` | Typedef classification requires bindings. Arbitrary scalar-word sequences overaccept `void int`. Attach existing scalar/storage predicates instead of defining another parser. |
| Declarators, parameters, names | `src/parse.x:1980-2033,2340-2488` | Ordinary empty parameter lists and lambda empty signatures differ. Type lookahead and method ownership are contextual. Keyword method members work; reference/caret recognition does not establish all placement/native support. |
| Aggregates, enums, named types | `src/parse.x:1490-1785` | Broadly faithful shapes. Field/delegate roles, tag holes, and class keyword expansion remain contextual; generic declaration alternatives do not permit every field storage/type. |
| Protocols | `src/protocol.x:476-674`; `src/parse.x:313-320` | Require participant/member/associated-type ordering and modifier predicates. `as`/`tag` are distinct adoption choices; meta bodies reject, private static bodies work through top-level dispatch. |
| Blocks and ordinary control | `src/statements.x:72-220,261,310-334,619-641` | `with` requires raw braces, so generic block allowing percent braces overaccepts. Do/while without semicolon translates. Targetless goto parses but fails emission; enclosing context and native case validity still matter. |
| Parenthesized statements | `src/expressions.x:242-277` | Cast, typed destructuring, and resumed expression paths are real, but depend on declaration lookahead. Preserve those recognizers in the grammar explanation. |
| Match, catch, raise | `src/statements.x:380-493`; `src/literals.x:369-410,562-600` | List patterns, compact Symbols, capture categories, and detail types impose different contracts. Template row slots are not arbitrary ordinary-source alternatives. Cleanup semantics come from lowering. |
| Operator ladder and casts | `src/expressions.x:46-242,314-345` | Binary levels agree with the ledger. Prefix/cast recursion is not a flat precedence rank. Bare `is int *` rejects: pointer selectors need parentheses. Operator availability still depends on types and protocols. |
| sizeof | `src/expressions.x:394-426` | Its early-return parser rejects the tested parenthesized-index operand, while native C prints 4. Batch C repairs operand parsing; do not adopt this as normative precedence. |
| Postfix, primary, composites | `src/expressions.x:452-699,754-950` | Slice support is receiver-dependent. Statement expressions require the existing semicolon/hole lookahead, not any grouped block. Map/initializer selection and native string words use contextual recognition. |
| Lambdas and captures | `src/lambdas.x:59-195` | Raw braces or assignment-expression bodies; percent braces are not automatically ordinary lambda blocks. Ordinary explicit captures use `&`; template capture slots differ. Cells and lifetime are lowering contracts. |
| Quoted data and interpolation | `src/literals.x:105-176,286-319,705-789,834-893`; `lib/tokenizer.x:390-423` | Percent terminals often describe normalized token identities rather than repeated source percent signs. List splices differ from Array/Map template sequence slots. Grammar does not prove constructed value shape or correct escaping. |
| Macro names and definitions | `src/macros.x:785-791,2410-2468,3271-3312` | Shared $/@ name production overaccepts @ definitions and keyword targets. Keep definition and invocation names distinct. Keyword components after dot remain supported. |
| Macro signatures and bodies | `src/macros.x:737-900,1320-1416` | Expression bodies require arrow expressions; category-specific body syntax and local restrictions cannot be freely combined. Sequence holes, unique names, and using clauses have existing signature predicates. |
| Calls, extensions, decorators | `src/macros.x:3211-3289,3440-3526,3840-3958,4132-4155` | Scalar @one() is rejected. Claims depend on visible definitions, result kinds and position. Signature-directed arguments, trailing-comma restrictions, and target consumption must remain explicit. |
| Quotations and template slots | `src/macros.x:1580-1640` | Category/lookahead selects typed quotations; template/nested quotation restrictions still apply. Ordinary canonical Lists remain legal by structure and position, without origin authentication. |
| Lisp and lexical leaves | `src/macros.x:1466-1518,2099-2140`; `lib/lisp.x:1132-1225` | External leaves do not form a complete Lisp/lexer grammar. Singular/sequence escapes and token modes must constrain callers; identifier-like is broader only in selected positions. |

Correct the explicit overacceptances before incorporating any draft production
into the existing syntax owner. Attach contextual predicates where used. Keep
raw source assembly, token modes, parser shapes, typing/placement, and native
acceptance distinct. The production-family review does not authorize a second
parser, a recursive AST validator, or a recurring equivalence gate.
