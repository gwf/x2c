# Binding and Match research

Existing behavior, verified at current source:

- `src/ast.x:32-64` defines `(binding positive-identity spelling)`; semantic lookup uses identity, emission and diagnostics recover spelling. This is already an ordinary structurally inspectable List, not an opaque binding pointer.
- `src/compiler.x:2852-2889` issues identities from the compiler's shared name counter, remembers `known` identity facts, and maintains bindings per semantic scope. `Sym.define` at 2924-2930 uses that scope; `_semantic_lookup` at 2975 onward searches from inner to outer. Spelling alone cannot represent reference identity; different scopes issue distinct identities.
- `src/parse.x:2422-2455` states and implements ordinary syntax binding, in source order, in current compiler state. It mutates Sym and does not implicitly open a semantic transaction. Do not run it speculatively merely to recognize a pattern without addressing those effects.
- `src/macros.x:2741-2777` already identifies one template lexical declaration by ordinal and namespace; `_definition_local` records an identity once, and `_replace_definition_bindings` rewrites every occurrence through one map. `src/macros.x:3634-3659` changes definition-only identities to replacement binders; expansion can then allocate a fresh semantic identity and reuse it throughout. This is the best existing seed for the normalization map.
- `lib/match.x:1158-1171` uses a capture slot the first time a binder appears and equality on subsequent appearances. `lib/match-machine.x:108-111` compares Var values. This means repeated holes today require ordinary Var equality; it does not mean alpha-equivalence.
- `lib/match.x:730-762` recursively replaces binders, splices sequence captures, retains missing binders, and unquotes `!quote`. A future public total instantiate operation must decide whether missing arguments constitute a partially applied template or an error; do not silently inherit unresolved Match binders into executable syntax.

## Recommendation

Keep canonical AST Lists and compiler-issued bindings. Add a shared template-local interface: an ordered collection of declaration identities owned by the template, preserving namespace and repeated references. For semantic comparison, map those owned identities to deterministic ordinal slots; references to identities absent from the owned set remain rigid free references. This is a comparison/projection view over the existing AST, not another AST language that downstream binding must interpret. The authoritative template value continues to contain ordinary canonical syntax plus its hole and local interfaces.

Names remain labels. An owned declaration's label never decides matching. A free reference's spelling alone never decides matching either. Member names, operators, grammar tags, and unresolved textual references are separate roles; do not rewrite every string or Symbol.

Alpha matching must use a bijection between pattern-owned and subject-owned declarations. Both directions matter: two distinct pattern declarations must never collapse onto one subject identity. Ordinal normalization provides this relation for fixed declarations in structurally corresponding positions. Holes require care: local declarations inside a hole are private to that captured subtree; free references from the capture into the surrounding matched template require an explicit boundary map. Captures should return original syntax plus that interface, so reconstruction substitutes original subtrees while consistently translating references to any newly instantiated surrounding locals. Blindly returning a normalized subtree loses usable original binding identities; blindly returning the original subtree can leave references attached to old declarations.

Bound syntax gives the reliable reference graph. For open parser syntax, identify declaration/reference roles while ordinary binding or macro-definition parsing visits them, rather than introducing a second resolver. Alpha comparison of unresolved open syntax should remain structural until an explicit compiler-context resolution step. In particular, an identifier that resolves at a definition site is rigid unless it denotes a template-owned introduced declaration. The same spelling at a use site is not automatically equal.

## Alternative comparison

1. Existing binding IDs plus explicit local map: smallest reuse; needs local/free classification and capture boundary map. Positive IDs remain authoritative output. Recommended.
2. De Bruijn depth/index everywhere: elegant alpha comparison but requires converting every scope and binder namespace, shifting on subtree movement, and representing free identities separately. It enlarges the canonical syntax contract without buying needed recognition power.
3. Pure declaration-position IDs: convenient stable labels but references must still be resolved to their declaration positions. Paths shift under edits and sequence insertion; a positional key alone is not a substitute for reference identity.
4. Pairwise bijection during matching: avoids allocating normalized syntax, but requires Match equality to consult the bijection and roll it back on backtracking. Start with ordinary normalized comparison Lists so the existing matcher remains reusable; optimize only with measurements.

## Isolated model evidence

`/tmp/dual-macro-alpha.py` is a Python semantic model, not a compiler feature probe. It normalizes canonical-shaped binding nodes using an explicit known-owned declaration list. Execution passed four assertions: alpha-renamed declarations compare equal; reference to the outer declaration instead of the shadowing inner declaration compares unequal; same-spelled distinct free bindings compare unequal; extracting a local reference makes it free relative to the extracted subtree. Its normalized output is:

```
(block (declare (local 0))
       (block (declare (local 1)) (ident (local 1)))
       (ident (local 0)) (ident (free 10)))
```

The model does not establish declaration discovery, x2c parsing, typing, namespace handling, lifetime, helper transport, or capture rebasing. Those remain implementation work. It establishes why the owned/free interface is necessary and why spelling erasure alone is insufficient.

## Round trips

- Exact substitution round trip for a binder-free structural template: `instantiate(T, match(T, S)) == S` by canonical structural equality, assuming a successful complete match.
- With introduced declarations: round trip equals S by alpha-equivalence, preserving rigid external identities and declaration/reference incidence. Compiler-assigned integer IDs and fresh spelling need not be equal.
- Repeated expression holes: compare under the captured subtree's own local alpha map and its external-binding interface. Thus `(x + x)` matched as `$same + $same` succeeds only when both references resolve to the same external binder, not merely when both spell `x`.
- After ordinary binding: reconstruction must resolve every rebased reference to the intended reconstructed declaration; this is stronger than visual alpha equivalence. Binding/typing and contextual placement remain ordinary compiler operations.

Not investigated here: full grammar binder coverage, Match typed predicates and source capture lowering, native helper wire format, or anonymous template lifetime. Parent research covers those areas.

Follow-up model: `.context/dual-macro/alpha-model.py` now additionally tests capture-side metadata and reconstruction. All ten assertions passed with `python3 .context/dual-macro/alpha-model.py`. A capture retains its ordinary syntax, its private declaration identities, a map from externally referenced surrounding local identities to template-local slots, and rigid free identities. Reconstruction remaps only its boundary refs; original hole-owned declarations and rigid frees remain intact. An absent destination local rejects an escaping capture. A collapsed pair of distinct declaration references fails comparison. These tests demonstrate the semantic algorithm with supplied metadata; they do not discover that metadata from raw x2c syntax or integrate compiler Match. For repeated instantiation, hole-owned declarations must also receive one consistent freshening map when copied into a new executable region; preserving them in this model demonstrates recognition/reconstruction of one original region, not multiple expansion safety.

## Cross-review correction: hole-dependent declaration order

A whole-subject preorder ordinal pass is NOT a correct direct implementation of the recommendation. Example: template `{ $prefix; int fixed; use(fixed); }`; candidate prefix owns two declarations. Globally assigning subject ordinals shifts `fixed` from slot 0 to slot 2. Fixed template declarations must align by template structural position, excluding subtrees consumed by holes. The previous Python model supplies owned lists aligned by hand; it does not solve that alignment.

The smallest reuse for fixed locals is existing Match captures: lower a fixed declaration identity into `(binding ?__local_k ?)` and every corresponding reference into that same identity capture. Matching IDs instead of complete binding nodes ignores user labels but preserves repeated references. Record namespace in the template local descriptor. Distinct local slots still require injectivity: ordinary Match does not require two differently named capture slots to hold distinct values. Subject binder/reference role information must come from ordinary binding or template-parser metadata; a generic List walk cannot establish it.

Repeated holes must not reuse one ordinary Match slot when equality is alpha-equivalence. Lower each occurrence to a distinct capture slot, then compare captures with their own local declaration maps and the fixed-local correspondence established by the enclosing pattern. Otherwise Match rejects two alpha-equivalent hole subtrees before a semantic comparison can run. This extends the existing capture-layout projection approach; it does not create another pattern grammar.

### Backtracking is consequential

`lib/match.x:1417-1478` implements interior stars with shortest-first split enumeration. Checking alpha equality, local-map injectivity, or boundary validity only after the first structural success is incomplete: that split may fail the contextual relation while a later split succeeds. Static guards currently cannot run an arbitrary callback: `lib/match.x:1314-1357` recognizes only built-in `!is` classifications/type tags; `_compile_guard_core` at 1359-1376 handles structural `!or`, `!not`, `!is`, `!set`, and `!and`. No supplied contextual equality or candidate-acceptance callback was found in this path.

Viable implementations:

1. Add a bounded internal acceptance/comparison interface to Match's existing machine. Capture equality and final contextual checks become part of the same transactional match. A rejected contextual candidate returns through existing choice/sequence retry paths; map writes use existing marks/journal rollback. Ordinary List matching keeps the current equality behavior. This is the strongest full-semantics option, but the exact continuation wiring needs a compiler/runtime prototype; a callback bolted onto public `try_match` after committed success is insufficient.
2. Preprocess candidate views per attempted structural alignment and use existing Match, enumerating complete structural capture solutions with an iterator/continuation that resumes on rejection. This reuses matching but still needs an existing-machine resumable interface; reimplementing sequence search outside Match would be parallel machinery.
3. First milestone supports unambiguous terminal sequence holes and fixed structure, where one structural match followed by contextual checks is complete. This is a viable scoped milestone, NOT evidence that arbitrary interior sequence holes cannot work. The spec must explicitly distinguish this limitation from the intended full feature and not claim full parity.
4. Flatten every hole subtree into an independent alpha-normalized comparison key before matching. This can handle self-contained hole-local alpha equality, but enclosing-local references still need alignment-dependent remapping. It does not remove the contextual/backtracking problem in general.

Recommendation: specification should require contextual failure to participate in ordinary Match backtracking, while implementation starts with fixed structure and terminal sequences as an isolated prototype, then demonstrates an interior sequence counterexample before claiming full integration. No production semantic validator is added: these checks define the matching relation, not executable syntax legality. Ordinary binding and typing remain authoritative.
