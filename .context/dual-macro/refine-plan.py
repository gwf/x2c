from pathlib import Path
p = Path('plans/dual-use-syntax-templates.md')
s = p.read_text()
s = s.replace('outside the matched template. Spelling', 'outside the matched template. Spelling')
s = s.replace('A recognition capture row contains its logical hole identity, grammar kind,\noriginal syntax, owned declarations, references to enclosing template slots,\nrigid external references, and available source association.', 'A recognition capture row contains its logical hole identity, grammar kind,\noriginal syntax, owned declarations, references to enclosing template slots\nand to declarations owned by other captures, rigid external references, and\navailable source association. Capture rows share an ownership/reference graph;\na declaration in one sequence element can bind a reference in a later element\nor another hole. A sequence is one region for alpha comparison, not a List of\nindependently closed elements.')
s = s.replace('These are ordinary inspectable Lists. The original AST is authoritative; a\ncomparison projection is transient, not a second tree shipped to the binder.', '''These are ordinary inspectable Lists. The original AST is authoritative; a
comparison projection is transient, not a second tree shipped to the binder.
Concrete proposed data shapes (field spellings are a proposed contract):

```text
(macrodef
  (name sum) (kind expression) (target ()) (targetp ())
  (parameters
    (macro-param (binder ?left) (kind expr) (sequence 0))
    (macro-param (binder ?right) (kind expr) (sequence 0)))
  (template (expr (<macro-expr>)
    (op + ?__macro_expression_left ?__macro_expression_right)))
  (fresh ()) (captures ()) (pattern INVOCATION-ROW-PATTERN)
  (stage template) (domain "unit/session")
  (roles (left expression PATH-LEFT) (right expression PATH-RIGHT))
  (origin ()) (file "source.x"))

(syntax-capture (hole left) (kind expr)
  (value (expr (int) (ident (binding 41 "price"))))
  (owned ()) (boundary ()) (cross-capture ())
  (free (binding 41 "price")) (source ()))

(syntax (stage constructed) (domain "unit/session")
  (ast (expr (<macro-expr>) (op +
    (expr (int) (ident (binding 41 "price")))
    (expr (int) (ident (binding 42 "tax"))))))
  (fresh ()) (captures ()) (boundary ()) (relocations ()))
```

The macrodef retains its existing invocation-row pattern, rather than storing a
second authored body pattern. Paths locate registered substitution positions;
they do not resolve names. Existing parser output owns precise body wrappers
and internal binder spellings; this example illustrates that canonical shape,
not an assertion of a new exported ABI already present today. The syntax bundle
is an insertion envelope, not a program AST node: the compiler adapter prepares
fresh/relocated bindings through existing expansion, unwraps `ast`, and calls
ordinary binding at the caller-owned transaction boundary. Returning a bundle
from a List-returning meta function is therefore explicit new insertion support.
Raw canonical syntax Lists continue through their existing path.''')
s = s.replace('Repeated sequences compare elementwise with their shared boundary interface.', 'Repeated sequences compare as ordered regions with one shared local map and\n  boundary interface, preserving declaration/reference relationships across\n  elements.')
s = s.replace('Other free references keep their exact identities.\nOn construction, freshen each relocated declaration once and remap only', 'References to declarations owned by another captured region retain a\ncross-capture edge, rather than being misclassified as rigid free references.\nOther free references keep their exact identities.\nOn construction, build one joint relocation map for the output region,\nfreshen each relocated declaration once, and remap only')
s = s.replace('consistent internal references per insertion. This copying case is specified\nbut not established by the current model.', '''consistent internal references per insertion. If another capture refers to
that declaration and it is copied twice, its destination occurrence must be
explicitly mapped; reject ambiguous relocation instead of selecting by spelling.
For example, Hprefix = `int x;` and Hvalue = `x` share one edge. Rebuilding both
once maps both to fresh-x. Copying Hprefix twice and Hvalue once requires an
explicit target occurrence. The cross-capture model exercises a supplied joint
map, but automatic metadata discovery and ambiguity handling in the compiler
remain implementation work.''')
s = s.replace('Inferred `expr TYPE`, `(at ...)` positions and definition-parser\n  placeholder wrappers can be projected away where the stage contract permits.', 'Inferred `expr TYPE`, inferred `return RETURN-TYPE`, `(at ...)` positions\n  and definition-parser placeholder wrappers can be projected away where the\n  stage contract permits. Explicit source types are retained. The producer-owned\n  inventory of other derived fields is still required; blanket type erasure is\n  not specified.')
s = s.replace('A body pattern never silently expands a deferred invocation.', '''For Statement/Unit and other sequence result categories, the template root is
`seq`, not a scope. Recognition at a single-item position adapts one subject
item to `(seq ITEM)`; at a sequence position it uses the supplied item sequence.
It never flattens a `block` into its contents or adds braces. Thus a macro body
containing a literal block requires that block shell in the subject. Expression
patterns use the expression root with no sequence adaptation.

A body pattern never silently expands a deferred invocation.''')
s = s.replace('Nested structural templates can be inlined for recognition after parameter', '''Snapshotting captures the outer definition and its resolved lexical references.
It does not silently freeze the entire evaluator session. Already stored nested
definitions remain captured; nested name/local-macro markers retain their
existing expansion-time resolution unless explicit structural composition
resolves and captures that child. Computation slots retain their existing
session/effect behavior. Transitive freezing could be a later explicit API;
it is not the default and need not create cyclic descriptor data for recursion.

Nested structural templates can be inlined for recognition after parameter''')
s = s.replace('macro Statement $save(Expr $value) {\n  int temporary = $value;\n  consume(temporary);\n}', 'macro Statement $save(Expr $value) {\n  { int temporary = $value; consume(temporary); }\n}')
s = s.replace('Body `block(D(L0:int,H0), call F(consume)(R(L0)))`.', 'Body `seq(block(D(L0:int,H0), call F(consume)(R(L0))))`.')
s = s.replace('macro Statement $nested(Expr $value) {\n  int x = $value;\n  { int x = 1; consume(x); }\n  consume(x + external);\n}', 'macro Statement $nested(Expr $value) {\n  {\n    int x = $value;\n    { int x = 1; consume(x); }\n    consume(x + external);\n  }\n}')
s = s.replace('Body `block(D(L0,H0), block(D(L1,1),call F(consume)(R(L1))),\ncall F(consume)(E(+ R(L0) F(external))))`.', 'Body `seq(block(D(L0,H0), block(D(L1,1),call F(consume)(R(L1))),\ncall F(consume)(E(+ R(L0) F(external)))))`.')
s = s.replace('Stages: capture the statement in the function\'s binding context; recognize', 'Stages: capture the statement in the function\'s binding context; adapt it to\na singleton `seq` and project the inferred return-context field; recognize')
s = s.replace('and its semantic transactions before ordinary `bind_syntax`.', 'with its existing caller-owned semantic transaction boundaries before ordinary\n   `bind_syntax`; the expansion operation itself does not begin a transaction.')
s = s.replace('and rigid frees. Reuse lexical capture protection', 'and cross-capture declaration/reference edges as well as rigid frees. Reuse\n   lexical capture protection')
s = s.replace('wire roundtrip', 'wire roundtrip')
s = s.replace('| `transport-datum-probe.x` |', '| `cross-capture-model.py` | joint map preserves references between captured regions; two output copies stay distinct | supplied relocation maps, not compiler discovery |\n| `transport-datum-probe.x` |')
s = s.replace('with supplied metadata. Actual compiler property 3', 'with supplied metadata. The cross-capture model verifies joint relocation\nincidence for supplied output maps. Actual compiler property 3')
s = s.replace('does not implement multiple independent fresh copies.', 'does not implement automatic discovery/allocation for multiple independent\n  fresh copies; the cross-capture model tests supplied copying maps only.')
p.write_text(s)
