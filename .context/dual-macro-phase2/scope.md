# Phase 2 coverage and meaning of the four forms

Authorization: continued isolated validation spike; no production implementation,
commit, gate, push, or merge. Baseline 1b23aaa7e103461c3b219b9e10546aeb35384b60.

Proposed core rule: the dollar sign selects a named global/imported macro;
a declared Macro variable is an ordinary lexical value. Parentheses apply a
value; no parentheses obtain/read it. A call-shaped case is recognition instead
of construction because it is in a Match pattern position.

| Form | Baseline | Proposed phase-2 contract |
| --- | --- | --- |
| $sum | Rejected: expected '(' | Named global/imported macro value |
| $sum(a,b) | Applies named global/imported macro | Preserve ordinary source application; meta-body construction returns code |
| sum | Ordinary program value today, including under a same-named local macro | Read a declared Macro variable; existing ordinary values retain meaning |
| sum(a,b) | Local macro / alias / ordinary call under existing precedence | Apply a declared Macro value when it is the selected callable |
| case $sum(?a,?b) | Not currently a macro body pattern | Named macro as recognition pattern |
| case sum(?a,?b) | Not currently a macro body pattern | Macro-valued variable as recognition pattern |

The capital Macro denotes the callable value category, not a tokenizer keyword
and not an opaque native object. The body remains canonical inspectable AST
Lists. Calling it requires shared construction/recognition machinery, not a
public getter or method family.

Existing compatibility is established by dollar-baseline.x, root rerun exit0:
- global $sum(1,2)=3; ordinary sum(1,2)=103;
- local macro sum(1,2)=23; $sum remains global=3;
- (sum)(1,2) and bare sum as a function pointer remain ordinary=103.

named-reference-current.x exits1 with expected '(' at bare $sum.
These tests establish current behavior only, not support for proposed forms.

Required coverage before claiming the complete simplified proposal:
- actual parser/compiler: bare named value, Macro local and parameter calls,
  dynamic selected case, passing/returning, anonymous factory/composition;
- same arithmetic body builds/matches, mismatch, repeated holes, empty and
  interior sequences, typed Name/Type/Statement projections;
- local declarations with different names, nested scopes/shadowing, rigid free
  references, fixed locals after a declaration-bearing captured prefix;
- contextual equality must reject/retry an early sequence partition within
  existing Match, for both value and span captures;
- joint relocation across hole captures and distinct fresh copied regions;
- helper tests use actual compiler-issued program identities and reuse cached
  helper across changed program binding assignments without helper-ID leakage;
- deferred invocation matching vs expanded body matching is stage-explicit;
- useful transformation predominantly in ordinary x2c macro/Match forms;
- legacy local macro/alias/function resolution and literal pattern-like data.

Incomplete partial prototypes must be labelled as such. A static-known case
adapter does not prove dynamically selected cases; arithmetic doesn't prove
fresh declaration binding; dummy datum IDs don't prove helper-domain hydration.
