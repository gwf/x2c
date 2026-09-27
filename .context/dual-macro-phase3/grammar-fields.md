# Field grammar appendix

This is a descriptive grammar of the existing canonical List contract, not a
new language or validator. `S(x)` marks a field supplied by source syntax;
`D(x)` marks a compiler-derived field. `SD(x)` means the same positional field
holds source spelling before resolution and a derived representation afterward.
A sequence marker applies its classification to every element. Head tags are
fixed discriminants and have no source/derived field. Children retain their
own field classifications recursively. `()` means absence, not a new node.
Types remain ordinary Lists in their existing grammar; nonterminals below
name compiler roles, not new runtime representations.

`S(Node)` does not imply that every annotation within Node was source-written;
it means the child occurrence corresponds to an ordinary source operand/body.
`D(Node)` denotes synthesized scaffolding as a whole. A production may be
reachable only through `%()` construction or an internal producer and still
be canonical. Exact validity remains the ordinary owner operation's decision.

## Root, origins and identities (ast.x:9-65; parse.x:2470-2490)

```
AstSequence ::= S(Node)*                         // outer List, no tag
Node ::= SourceNode | ExpansionNode | LoweredNode | OriginNode
OriginNode ::= (at D(OriginID|m-origin) SD(Node))
             | (src D(SourceRecord) S(Node))
             | (api-source D(Line) D(Doc) S(Node))
SourceRecord ::= (source D(File) D(BeginOffset) D(EndOffset))
Binding ::= (binding D(PositiveID) S(Spelling))
Name ::= S(String) | (S(String)) | Binding
       | "x2c.ident"-node | SD(TemplateNameSlot)
MethodName ::= ((S(Owner)) S(Member))
"x2c.ident"-node ::= ("x2c.ident" S(Spelling))
```

Binding spelling can become generated: the binding producer then supplies
D(Spelling), retaining original S labels in existing compiler facts. PositiveID
is never a source spelling or positional syntax binder index. SourceRecord
fields exist for exact complete captures; new Lists do not acquire source text.

## Expressions (expressions.x:2039-2440; literals.x:1205-1254)

```
Expression ::= (expr D(SemanticType|()|<macro-expr>) S(Content))
             | (expr D(SemanticType) D(LoweredContent))
Content ::= (ident SD(Name))
          | (literal D(LiteralType) S(LiteralText))
          | (literal D(LiteralType) S(LiteralText) D(AtomOrSymbolValue))
          | (op S(UnaryOperator) S(Expression))
          | (op S(BinaryOperator) S(Expression) S(Expression))
          | (op S(?Operator) S(Condition) S(OnTrue) S(OnFalse))
          | (op S(.|->) S(Expression) S(MemberName))
          | (postfix S(++|--) S(Expression))
          | (call S(CalleeExpression|RawCalleeName) S(Arguments))
          | (index S(Expression) S(Expression))
          | (getindex S(Expression) S(Expression))
          | (slice S(Expression) S(Expression|())
                   S(Expression|()) S(Expression|()))
          | (parens S(Expression|Declaration|Block))
          | (sizeof S(Expression|Declaration|RawTokenSequence))
          | (offsetof S(TypeSyntax) S(MemberName))
          | (cast S(Declaration) S(Expression))
          | (cast D(SemanticType) S(Expression))
          | (generic S(Expression) S(Association)*)
          | (va-arg S(Expression) S(Declaration))
          | (commas S(Expression)*)
          | (array S(Expression)*)
          | (map S(MapEntry)*)
          | (map-entry S(Expression) S(Expression))
          | (composite S(InitializerItems))
          | (dotinit S(MemberName) S(Initializer))
          | (indexinit S(Expression) S(Initializer))
          | (segments S(Segment)*)
          | (splice S(Expression))
          | (dstrasgn S(Targets) S(Expression))
          | (is-type S(Expression) S(TypeSyntax))
          | (is-symbol S(Expression) S(Expression))
          | (type-tag S(TypeSyntax))
          | (lambda S(Parameters) S(Expression|Block))
          | (lambda S(Parameters) D(LambdaCaptures) S(Expression|Block))
          | (tadapt S(TargetExpression) S(SourceExpression))
Arguments ::= (args S(Expression|MacroSlot)*)
MemberName ::= (S(Spelling|TemplateMemberSlot))
Association ::= (association S(TypeSyntax|default) S(Expression))
Initializer ::= Expression | Content
InitializerItems ::= (commas S(Initializer)*)
Targets ::= (targets S(Expression|Name)*)
Segment ::= (segvar S(Expression)) | (segexp S(Expression))
          | D(CacheReference) | S(RawText)
LambdaCaptures ::= (captures D(LambdaCapture)*)
LambdaCapture ::= (capture D(Binding) D(CapturedType) S(CapturedExpression))
```

Lambda captures may be explicitly prescribed reference captures in source;
in that case `CapturedExpression` is the source binding expression with a
compiler-generated address operation and CapturedType reflects reference mode
(literals.x:1120-1140). Raw constructor producers can supply canonical capture
rows and ordinary binder preserves that mode (literals.x:1020-1044).

The `op` tag covers source punctuation and x2c operators selected by the
operator parser, not just C arithmetic. MemberName is a spelling slot even
when the receiver contains a bound program identifier. It is not Binding.
Source LiteralType is inferred from text/suffix and must not automatically be
ignored by every semantic comparison. Generated literals can have D text.

## Declarations, type syntax and declarators (parse.x:220-585, 850-1080,
## 2180-2340, 2601-2735; type.x:149-154, 848-878)

```
Declaration ::= (declare S(BaseTypeSyntax) S(Bindings))
              | (typedef S(BaseTypeSyntax) S(Bindings))
              | (decl S(BaseTypeSyntax) S(Bindings))
              | (dstrdecl S(BaseTypeSyntax) S(NameTargets) S(Expression))
              | (dstrdecl S(Parameters) S(Expression))
              | (function S(ResultBase) S(Declarator) S(Block))
              | (falias S(Declaration) SD(Binding))
              | (named-type S(Spelling) S(TypeSyntax|()))
Bindings ::= (bindings S(DeclaratorOrInitializer)*)
DeclaratorOrInitializer ::= Declarator | (op S(=) S(Declarator) S(Expression))
Declarator ::= (bind SD(Name|MethodName|()) S(Modifiers))
Modifiers ::= S(Modifier)*
Modifier ::= S(*|&|opt-ref|Qualifier)
           | (dim S(Expression)?)
           | (bitfield S(Expression))
           | (fnmod S(Parameters))
           | (fnmod S(Parameters) S(Modifiers))
           | (S(AttributeText))
Parameters ::= (params S(Parameter)*)
Parameter ::= (param S(BaseTypeSyntax) S(Declarator)) | (...)
NameTargets ::= (targets SD(Name)*)
TypeSyntax ::= S(TypeComponent)*
TypeComponent ::= S(TypeKeyword|Qualifier|StorageClass|TypeSpelling)
                | Modifier | Aggregate | Enum
                | SD(TemplateTypeSlot)
Aggregate ::= (struct S(TagName) S(Fields)?)
            | (union S(TagName) S(Fields)?)
            | (struct S(Fields)) | (union S(Fields))
Fields ::= (fields S(Declaration)*)
Enum ::= (enum S(TagName) S(EnumeratorList)?)
EnumeratorList ::= S(Enumerator)*
Enumerator ::= SD(Name) | Declarator
             | (op S(=) SD(Name|Declarator) S(Expression))
TagName ::= S(Name|()) | (gensym D(Role) D(GeneratedName))
SemanticType ::= D(CanonicalModifier)* D(BaseSemanticTypeComponent)*
CanonicalModifier ::= Modifier | (func D(SemanticTypeList))
SemanticTypeList ::= D(SemanticType)*
```

`BaseTypeSyntax` is a List of components, not `(type ...)`. SemanticType shares
the same underlying ordinary List grammar; canonicalization maps source fnmod
parameter AST to func semantic parameter Types. Existing base keywords and
qualifiers are leaf Symbols (void, numeric keywords, struct/union/enum storage,
const/volatile/restrict, static/extern/inline/threaded/meta etc.), not one new
production each. `opt-ref` and reference modes are existing Type grammar, not
new public syntax-template categories. `Type.declaration_parts` and parameter_ast
own the inverse presentation; do not reconstruct modifiers independently.

Unnamed params and array dims have empty Name/Expression fields. C `(void)` is
an explicit param `(param (void) (bind () ()))`; `(params)` must not be assumed
semantically equivalent without the ordinary parameter owner. Member fields,
bitfields, tags and enumerators bind in their existing compiler contexts.

## Statements (statements.x:125-240,330-429,462-490; parse.x:2744-2913)

```
Statement ::= (stmnt S(Expression)) | (empty)
            | (block S(Node)*) | (group S(Node)*) | (seq S(Node)*)
            | (return) | (return D(ReturnContextType) S(Expression))
            | (return S(Expression))                 // transformed
            | (if S(Expression) S(Statement))
            | (if S(Expression) S(Statement) S(Statement))
            | (while S(Expression) S(Statement))
            | (do S(Statement) S(Expression))
            | (for S(Declaration|Expression|()) S(Expression|())
                   S(Expression|()) S(Statement))
            | (switch S(Expression) S(Statement))
            | (case S(Expression)) | (default)
            | (break) | (continue)
            | (goto S(Name)) | (label S(Name))
            | (defer S(Statement))
            | (raise S(Expression) S(Arguments))
            | (try S(Statement) S(Catches|()) S(Statement|()))
            | (match S(Expression) S(CaseRows))
Catches ::= (catchcases S(CatchRows) D(HandlerBinding))
CatchRows ::= S((S(PatternExpression) S(Statement))) *
CaseRows ::= S((S(PatternExpression) S(Statement|GuardedBody))) *
           | S(PreprocessorNode) *                    // interleaved
GuardedBody ::= (guarded D(GuardExpandedStatement))
GuardExpandedStatement ::= (if S(GuardExpression) D(Block))
```

Catch bodies receive generated binder declarations; Match typed captures
receive generated temporaries/declarations. The source pattern and source
body remain distinct fields. Patterns are ordinary Match data expressions,
not a new AST syntax-variable language. Guarded marks control flow after
source guard rewriting and must not be dropped in a lowered-stage match.

## Compile-time source items (parse.x:1760-1775,2717-2735;
## protocol.x:150-154, 525-558,2350-2567; macros.x:3370-3390)

```
PreprocessorNode ::= (preproc S(Text))
Import ::= (import S(PackageName) S(Alias|()))
CAssertion ::= (c-assert) | (c-assert S(Expression) S(Expression))
Protocol ::= (protocol S(ProtocolRecord) SD(StorageMode) D(Location))
ProtocolRecord ::= ("protocol-record" S(BaseType) S(ParticipantBinder)
                    S(AssociatedTypes) S(ProtocolMembers))
AssociatedTypes ::= (associated S((S(Name) SD(TypeSyntax))) *)
ProtocolMembers ::= (members S((S(Name) D(SignatureType) S(NativeName|()))) *)
Adoption ::= (adopt S(BaseType) S(ParticipantType) SD(StorageMode) D(Location))
           | (adopt S(BaseType) S(ParticipantType) SD(StorageMode)
                    S(RepresentationType) D(Location))
           | (adopt S(BaseType) S(ParticipantType) SD(StorageMode)
                    S(TagExpression) D(Location))
TagExpression ::= (tag S(Expression))
MetaProtocol ::= (meta-protocol S(Adoption))
               | (meta-protocol S(BaseType) S(ParticipantType)) // retained
MacroDefinition ::= (macrodef S((name S(Atom))) S((kind S(ResultKind)))
 S((target S(TargetKind|()))) S((targetp S(HoleDescriptor|())))
 S((parameters S(HoleDescriptorList))) D((fresh D(FreshRows)))
 D((captures D(BindingList))) D((pattern D(MatchPattern)))
 S((template S(Node|()))) D((origin D(Location))) D((file D(Path)))
 D((imported D(Bool))) D((builtin D(Bool))) S((local S(Bool))))
HoleDescriptor ::= (macro-param S((binder S(Atom))) S((kind S(HoleKind)))
                    S((sequence S(Bool))))
FreshRows ::= D((D(PlaceholderBinding|Atom) S(SourceLabel) D(LispFlag))) *
```

MacroDefinition assoc rows are the current complete descriptor, not a newly
invented opaque template AST. Hole inference can derive kind/sequence facts
from source slot use; those fields are then D in the recorded descriptor even
though explicitly authored kinds/sequence markers are S. Pattern is the current
construction-capture projection pattern, not the proposed recognition projection.

## Pending expansion and declaration production
## (macros.x:2490-2510,2838-2869,2965-3029,3971-3985,4160-4269;
## parse.x:2470-2557,2675-2716)

```
ExpansionNode ::= (macro-invoke SD(StoredDefinition) D(InvocationInput) D(Site))
                | (macro-slot S(SpliceFlag) S(MetaExpression|LispText)
                              D(ConstructionState)*)
                | (macro-bind D(ProjectionAtom))
                | (meta-call S(CalleeExpression) S(Arguments))
                | (meta-cap D(ProjectionAtom))
                | (tpl-call SD(StoredDefinition|CalleeExpression) S(Arguments))
                | (local-macro S(Atom))
InvocationInput ::= (args D(MacroCapture)*)
                  | (target D(Arguments) S(MacroCapture))
MacroCapture ::= (capture S((source S(Node)*)) D((value D(Value)*))
                   D((expression D(Expression)))? D((splice D(List)*))?
                   D(ConstructionState)*)
StoredDefinition ::= MacroDefinition | S(Atom) | D(QuotedDescriptor)
Site ::= D(Token|m-invoke)
DeclarationProduction ::= (declaration-bundle D(Rows))
 | (syntax-recipe S(Callback) S(Arguments))
 | (declaration-recipe S(Callback) S(Arguments))
 | (declaration-pending S(Callback) S(Arguments) D(FrozenMacroStack)
                        D(PrivateMode))
 | (default-forward S(Child) S(Parent) S(Member) S(Fallback)*)
 | (declaration-forward S(Child) S(Parent) S(Member) D(FallbackList)
                        D(PrivateMode))
 | (default S(Function))
 | (declaration-default S(Function) D(FrozenMacroStack) D(PrivateMode))
 | (declaration-function D(Declaration) S(Body) D(FrozenMacroStack))
Rows ::= (rows SD(Node)*)
```

ConstructionState and FrozenMacroStack are existing administrative data,
not program AST grammar or user syntax to invert. They preserve lifetime,
source-order and capture context. Arbitrary LispText/callback computation is
not structurally invertible. See source owner for positional construction
rows that travel beside source/value rather than inventing a semantic validator.

## Lowered and emission productions (transform.x:165-255,1836,2037-2057,
## 3076-3088,3528-3551,3755-3818; cache.x:265,451-468; emit.x:1024-1200)

```
LoweredContent ::= (cache D(CacheID))
 | (var D(Expression)) | (nil)
 | (string SD(String|Expression))
 | (cons SD(Expression) SD(Expression))
 | (append SD(Expression) SD(Expression))
 | (varray D(Expression)*) | (vmap D(VarPair)*)
 | (tadapt D(OriginID) S(Expression))
 | (managed-init S(Expression))
 | (initval D(InitializerInput)? D(InitializerChoice)*)
VarPair ::= (vpair D(Expression) D(Expression))
InitializerInput ::= (input D((D(Placeholder) S(Expression))) *)
InitializerChoice ::= (D(Expression|()) D(SelectorPath)
                       D(DestinationType) S(Expression))
SelectorPath ::= D(Selector)*
Selector ::= (dotinit S(MemberName)) | (indexinit S(Expression))
LoweredNode ::= (localinit S(Declaration) S(Block))
 | (sourceinit D(Function))
 | (initcode D(InitializerInput) D(Block))
 | (matchcases S(Expression) D(LoweredCaseRows))
 | (defer S(Statement) D(EnvironmentBinding) D(CallbackBinding)
           D(CaptureRecords) D(WrittenBindings))
LoweredCaseRows ::= D((D(LogicalBinderList) S(PatternExpression)
                       S(Statement|GuardedBody))) *
EmissionDecoration ::= (comment SD(Text)) | (space D(Text))
                     | (src-at D(OriginID))
```

`src-at` is emitted token/source-map output, not accepted source AST input.
`comment` and `space` are emitted/presentation fragments. Compiler-generated
calls can have raw C callee String and declarations can contain raw attribute
text; these use existing emitter fallback rather than a new AST head enum.
The grammar contract is intentionally open to ordinary canonical C token
leaves in generated forms. There cannot be a finite “every accepted List”
validator grammar consistent with the current generic emitter fallback.

## Census coverage and exclusions

The companion head census records 215 literal `%(` head spellings in
ast/parse/expressions/statements/literals/type/transform/emit/cache/macros/
generate/protocol. It is a *miss detection aid*: it includes Match patterns,
semantic maps and diagnostics, misses dynamic `$tag` heads and String heads,
and is not automatically a grammar. The rows above explicitly include dynamic
op/member/aggregate/type forms and protocol-record/x2c.ident String heads.
The census classification distinguishes AST families, Type leaf spellings,
presentation output and registry/diagnostic metadata. `fadapt`, `findirect`,
`fhandle`, `fgetter`, `fpointer-factory`, `iadapt` are adapter memo keys, not
AST expression productions (`transform.x:511,645,659,716,796`;
expressions.x:3791). `indirect-adapter` is a helper result record
(transform.x:639), `field/method/delegate/step/ambiguous` are member resolution
results (expressions.x:454-480,1862-1889), `func-arg` is extraction data from
_func_call_arguments, not an emitted program node (expressions.x:1733).
`unit/module` are dump-definitions records, `native` is a generated-reference
set key and `attributes` is a binding-fact key (generate.x:629,840-844,895).
`with`/`with-name` are macro-like substitution facts, not AST nodes
(statements.x:604-617). Other metadata rows are listed in census with references.

The table does not claim a mechanically proven closed grammar for every
Lisp/metadata List that happens to travel through the compiler. Source
positions/types are context-sensitive, and source/native crossing operations
remain authoritative. Consolidating this inventory into the one specification
should retain these distinctions rather than claim an invented complete
semantic validator.
