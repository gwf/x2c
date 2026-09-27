# Shared rewrite and cost survey (isolated, bounded)

Observed owners: `src/ast.x:170` delegates `Ast.rewrite_children` to
`src/ast-rewrite.xmacro:1`. This visits immediate List children, allocates
scratch storage only on a changed child, and returns the original node when
unchanged. Existing clients use that same owner; approximately fourteen
references are not fourteen independently implemented low-level walkers.
Context-sensitive clients include lambda cells (`src/transform.x:1234`),
nested lambda regions (`1260`), destruction lowering (`3031`), and region
unwinding (`2418`). Those clients own scope/region traversal decisions.
A shared pure rewriting driver can compose local template rules with this
owner. Collapsing their semantic recursion indiscriminately is unproven.

Templates describe shapes; compiler operations own effects. Direct Func
adapters are cached using canonical source type and binding key
(`src/transform.x:507`), resolve expected/source types (`545`), and publish
helpers through `Compiler.add_early` (`src/compiler.x:2506`).
`Compiler.transform` (`src/transform.x:4310`) drains early declarations until
empty. Shape templates may replace List builders inside these operations;
they cannot replace resolution, memoization, or declaration ordering. A
native helper alone lacks the compiler context to perform these operations.

Performance: no comparable full-pipeline measurement was completed. Direct
List building, helper substitution, and compiler-owned deferred freshening
have different work and stage costs. Parser/probe build receipts are not
performance evidence. No runtime substitution proxy is presented as the cost
of the complete design. Full byte-identical typed/open-bound rewrite parity
and adapter publication parity remain untested. A meaningful future isolated
measurement must compare the same generated declaration workload, consume
fresh introduced declarations through ordinary binding, separate cold helper
build from warm transport, and verify output before comparing time. No
production/bootstrap changes or recurring performance gate is proposed.

The user-requested survey location was not available to this worker; this
file records the bounded evidence without guessing that missing location.
