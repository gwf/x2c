# Phase5 research scope

Baseline research commit: 7209e953 on codex/compiler-dual-macro-spike.
Investigation and isolated prototypes only; no production changes or bootstrap
refresh. Research evidence may be committed/pushed only on this branch.

Prove runtime push, sigsetjmp and landed calls written in an open try template;
prepare target free references once per unit at enclosing parse time, preserving
native declaration/include placement. Attach stages at the real producing
operation so template clients contain no stage wrapper calls. Repeat 62 raw
C/H comparisons and failing-skeleton rollback. Record cumulative migration
cost and a recommended advisory budget. Freeze four forms, open policy,
stage attachment, slot result semantics and demand-driven producer table.
The phase4 full compiler source snapshots are research evidence: this branch
must not be merged as is. Capture-role consolidation is a separate ordinary
production change, not part of this isolated prototype.
