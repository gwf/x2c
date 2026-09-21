# Long-session ownership assessment

The local REPL supports sustained sessions across the tested subset, including
recovery and retained results. It is not ready to promise bounded memory or
production integration. The remaining problem is session ownership, alongside
the cost of repeatedly copying increasingly large semantic maps.

This follows the [outer transaction experiment](retention.md) at `b50c712d`.
All measurements below use the subsequent tokenization, lowering-map, and
parser scratch cleanup. Peak RSS is a process high-water mark, including
startup and allocator caching; it is not live session bytes.

## Changes and ownership evidence

- The adapter allocates tokenization containers and its brace stack under the
  same detached owner as the outer transaction. It restores the compiler's
  borrowed cursors, tokenizer, source text, conditional map, and brace stack
  before destroying that owner. Token text, origin coordinates, and diagnostic
  entries use canonical storage outside it. Origin records remain live for
  retained syntax; they are not reset between inputs.
- Each result retains its diagnostic source text. The terminal temporarily
  selects that text while printing reports, including errors inside synthetic
  function wrappers. Old diagnostic entries and source survive later inputs.
- The lowerer creates only its six state maps, copied branch environments,
  and loop environments under a detached owner. Actual lowering runs in the
  caller's scope and pools. This distinction preserves wide integer boxes:
  canonical Lists may borrow those boxes, so scoping the whole lowering would
  leave dangling values. Existing map-growth ownership follows construction.
- Conditional scanning and declaration/block parsing free local Arrays on
  early returns and exceptional exits. Their canonical List results survive.
  Generic semantic scope pop and Lisp allocation behavior are unchanged.

## Measurements

At 5,000 submissions, compared with the preceding transaction-only fix:

| Workload | Previous extra allocations | Current extra allocations | Current peak MiB |
| --- | ---: | ---: | ---: |
| Fixed updates | 520,012 | 210,012 | 70.5 |
| Growing initialized values | 280,000 | 50,000 | 88.5 |
| Growing functions | 460,003 | 210,003 | 91.2 |
| Malformed declarations | 100,000 | 30,000 | 60.8 |
| Incomplete parameters | 215,000 | 115,000 | 61.0 |
| Expression evaluation | 525,021 | 215,021 | 70.6 |
| Mixed submissions | not measured | 182,536 | 65.8 |

Fixed updates fall from about 104 to 42 outstanding allocations per input.
The mixed cycle combines updates, calls, wide results, malformed/incomplete
input, and a failed multi-initializer declaration whose earlier effect must
survive. It verifies each value result and the final accumulated value.

| Workload | Inputs | Seconds | Peak MiB | Extra allocations |
| --- | ---: | ---: | ---: | ---: |
| Fixed updates | 50,000 | 7.529 | 204.7 | 2,100,012 |
| Mixed submissions | 50,000 | 7.846 | 190.5 | 1,825,036 |
| Malformed declarations | 50,000 | 5.762 | 66.2 | 300,000 |
| Incomplete parameters | 50,000 | 5.988 | 104.5 | 1,150,000 |
| Expression evaluation | 50,000 | 5.597 | 209.0 | 2,150,021 |
| Existing Lisp function | 50,000 | 0.208 | 60.6 | 2 |
| Lower existing AST | 50,000 | 0.280 | 53.6 | 0 |
| Replace/call existing lowered form | 50,000 | 0.262 | 70.2 | 300,000 |
| Fixed updates | 100,000 | 15.200 | 355.7 | 4,200,012 |
| Mixed submissions | 100,000 | 14.663 | 326.6 | 3,650,036 |
| Growing values | 10,000 | 17.336 | 129.2 | 100,000 |
| Growing functions | 10,000 | 17.507 | 134.6 | 420,003 |

Growing definitions take roughly 3.5 seconds at 5,000 and 17.5 seconds at
10,000. Full semantic-map copying remains a scaling limitation even though
those copies are reclaimed. Timings are host observations, not benchmarks
against a controlled idle system.

## Remaining owners and integration decision

Isolated repeated lowering of one already-parsed update retains no additional
Scope allocations. Reinstalling and calling the same lowered update retains
six per iteration; calling the existing function again adds only two total
warm-up allocations. The Lisp Lambda record and its capture map are
session-owned. Replacing its binding does not release that owner, and ordinary
callers can retain callable identities. A blanket evaluation scope or freeing
the previous callable would violate those lifetime rules.

The other fixed-update growth remains in front-end/adapter work: lexical
semantic maps, origin-bearing syntax, and canonical/boxed values. Parameter
maps are popped and then replayed around function bodies; compiler macro and
source facilities can retain map identity. Generic `Sym.pop_scope` therefore
cannot free the popped maps. Canonical storage also accumulates despite a
fixed set of user variables. This investigation distinguishes these owners
but does not claim that every remaining object is necessary or fully apportion
all parser allocations.

Production integration should follow a design for durable definitions versus
releasable submission results, and for Lisp callable/capture reachability.
The current result contract keeps everything borrowed until unit close;
shortening it requires an explicit caller-lifetime decision. A collector or
new export/root mechanism is outside this spike. Semantic transactions also
need a design that avoids copying every prior definition for each new one.
These are the next consequential choices, not further unreviewed frees.

Compile-time coverage remains a separate task. No provisional changes from
it were integrated; no new execution coverage, redefinition, or production
CLI surface was added. This checkout is local research, with no bootstrap
refresh or publication gate claimed.

## Validation and reproduction

All 747 compiler fixtures (1,746 artifacts) pass unchanged. The optional
submission checks cover 19 terminal cases, native parity, repeated unit
teardown, and old results used after 600 subsequent submissions in each of
three sessions. Retained cases include a wide integer, its syntax and lowered
forms, a captured closure, mutable Array identity, and diagnostic text.
Those API checks also pass with the generated compiler, runtime, and client
rebuilt under AddressSanitizer. Leak detection is disabled because the
experiment separately measures known session retention.

With the current compiler built as described in [README](README.md):

```sh
python3 tools/repl-spike/check.py
python3 tools/repl-spike/retention.py 5000
python3 tools/repl-spike/retention.py 50000 fixed mixed rejected incomplete evaluate lisp
python3 tools/repl-spike/retention.py 10000 values functions
python3 tools/repl-spike/retention.py 50000 lower rebind
python3 tools/repl-spike/retention.py 100000 fixed mixed
```

The optional driver stops a workload above 512 MiB peak RSS or after its
120-second timeout and never counts a failed/incomplete run as passing.
Results go to `debug/repl-retention/`; reruns replace matching workload logs.
Local evidence for this assessment is preserved in `debug/repl-long-*.log`,
`debug/repl-long-5000-samples/`, and `debug/repl-long-50000-samples/`.
No recurring validation requirement was added.
