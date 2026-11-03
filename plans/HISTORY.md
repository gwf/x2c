# x2c historical record

> Status: reference - consolidated on 2026-11-02 from revision
> `a7a01924c8406b9e7da8edb74ac891a0aa6b2e1a`.
> This is dated history, not an architecture specification or work order.
> Current contracts belong to the book, source owners, and repository guidance.

## Recovering the original evidence

The consolidation replaces 255 plan and reference documents, their README,
and 27 supporting source/data files: 283 files and 76,699 lines in total.
The full originals remain in the
[Git snapshot](https://github.com/gwf/x2c/tree/a7a01924c8406b9e7da8edb74ac891a0aa6b2e1a/plans),
including the original names, decisions, prototypes, measurements, and logs
that were tracked. They can also be read locally:

```sh
git ls-tree -r --name-only a7a01924c -- plans
git show a7a01924c:plans/README.md
```

Use a path from that listing with `git show REVISION:PATH` to recover its
complete record. Local `/tmp` and `debug` artifacts named by an old plan
were not necessarily committed or preserved. A recorded successful local
check does not establish remote publication; the dated outcome must say so.

Superseded designs, old delivery holds, acceptance thresholds, task lists,
and implementation prohibitions do not govern present work. A rejected
prototype rejects that implementation under its recorded conditions, not
every implementation of the idea. Historical measurements retain their
workload, units, baseline, and coverage limits. They are not current guarantees.
Verified outstanding work is listed separately in [README](README.md#current-work).

## Compiler architecture

September implementation work adopted typed Match captures and ordinary
language facilities inside the compiler. The wildcard-catch investigation
corrected its premise: that feature already existed. Initializer expansion
was bounded, and cleanup work moved out of emission through `68eea0a`.
The September redesign investigation declined a replacement compiler while
salvaging useful collection configuration and initialization changes. Other
cleanup-phase and file-movement prototypes were measured separately; a
failed prototype did not establish a permanent compiler boundary.

The September 27-29 dual-macro campaign unified syntax recognition and
construction and migrated source families including try/defer, lambdas,
Func, and collections. Its final handoff was `82d686e27`. Later component
work retained ordinary binding, typing, placement, and lifecycle owners.
Early component APIs and a proposed public Segment representation were
superseded. Automatic interfaces established ordinary source-module behavior;
its original local-delivery record did not itself establish publication.

Module blocks shipped as composition within one unit at `0ff8816e`.
Module storage classes later distinguished module visibility from file-private
storage. These deliveries superseded earlier proposals for separate units.
Current source ownership is described in [src/README.md](../src/README.md).

## Compile-time x2c and runtime Lisp

The first compile-time x2c implementation lowered ordinary x2c algorithms
through Lisp. September campaigns migrated initialization, bindings,
autodiff, and macro algorithms into x2c. The September 21 meta-value design
was rejected before publication because its storage and lifetime assumptions
did not generalize. Recovery delivered generic byte storage and native
layout handling at `db86d4b7`.

Native execution subsequently replaced that direction. Project helpers and
caching replaced earlier dynamic-module experiments. October 24 compiler-Lisp
independence (`71088fa33`) was followed by the October 25 native compiler with
runtime Lisp (`ff3aba2aa`, `735e72f73`). Compiler Lisp evaluation and linkage
were removed; embedded runtime Lisp remained. Earlier wordcode, loader,
record-wrapper, and storage descriptions are intermediate designs.

Meta import and runtime-reachability fixtures preserve the distinction between
translation-time execution and emitted runtime definitions. Current semantics
are in [compile-time functions](../docs/src/guide/meta-functions.md),
[generating code](../docs/src/guide/generating-code.md), and
[the language reference](../docs/src/reference/language.md).

## Source forms, macros, and language adoption

Quotation, literal construction, explicit meta calls, and component lowering
changed through several campaigns. The October 12 splicing migration selected
`$` for one value and `@` for sequences, retiring arithmetic `@` while retaining
named matrix operations. The October 25 collection/unquote migration
(`b9eed26d1`) replaced earlier quotation spellings without removing runtime Lisp.

Free-name behavior changed on October 16 at `bcb22ae7a`: expansion-site lookup became
the rule, with explicit `using` retaining a file-scope declaration. Structural
AST construction remained intentional; canonical Lists did not require origin
authentication. Earlier capture and hygiene proposals were superseded.

Indentation syntax, `.xp` files, and eight extensionless tool migrations
were delivered on September 24. List rest parameters shipped at `075623030`; their initial spelling became
`List @name` on October 27. Map keyword rest followed. Match conditions
introduced `~=` at `94942111d`; String switches shipped October 15.
The October 24 `with`/`alias` migration began at `ab9645f0c`, removed `$let`,
and later gained `unalias`. The C-preprocessor bridge (`6ff9552ce`) became
opt-in through `--cpp` at `ffe7e2b7a`; the earlier always-on premise was retired.
Contextual-keyword work followed. The book owns the resulting syntax.

## Ownership, regions, and runtime values

Scope, canonical String/List pools, classes, Func values, dynamic Var
operations, and protocol-generated behavior grew through distinct deliveries.
Reference-parameter adoption was an explicitly selected compatibility change.
Region-warning implementations were rewritten when their representation and
cost proved unsuitable; that did not reject lifetime diagnostics themselves.

Selected-root lifetime certification shipped as an optional analysis. The
September case study reported nine of ten nominated methods certified;
`Var.token` stayed private. A compiler-source report with thousands of
obstacles was incomplete, not certification of the compiler. Broader native
handle coverage and later lifetime extensions were not promised features.

October Channel ownership changed from shared payload Scopes and
synchronization to detached ownership through `fc6ea2d51` and `27ddb7464`.
The later execution-stack design superseded parts of that model. Historical
retention investigations distinguished live allocations, allocator retention,
virtual reservation, and RSS; they did not establish a leak merely from RSS.

## Runtime and concurrency

Independent Pool and Channel synchronization progressed through failed
measurements, narrower corrections, and accepted candidate `a596f6cb5` on
October 30. Its delivery explicitly accepted remaining Channel and retained
index costs. Earlier no-push holds and failed-acceptance labels were later
superseded. An index redesign was not part of that delivery; its rejection
was not a permanent prohibition on other designs.

The October 30 Task spike was followed by execution stacks, published at
`255de641f` on October 31. The delivered model used borrowed owner lifetimes
and open/close operations, replacing prototype assumptions about private task
allocation Scopes and parked pins. Task-local state repairs covered Lisp
activation and recursive rendering. Cache-path identity, GCC ASan fake-stack
handling, NaN reconstruction, and x87 padding repairs accompanied validation.

Dated accepted costs included 8 MiB usable stack reservation per task; 65 jobs
reserved 520 MiB before guards. Repeating 1,000 batches of 1,025 jobs retained
30.984 MiB RSS after mapped job arrays, versus 38.188 MiB before, without live
allocation growth across batches. Those observations did not establish zero
retention or a leak. Four-target evidence included Rosetta and Docker
emulation, not physical Intel coverage or TSan proof. Normal async-specific
benchmark reruns remained separately deferred; ordinary later snapshots did
not establish async overhead. Async I/O, async/await, migration, and suspension
during cleanup were outside that batch API.

Grouped typed Maps shipped at `9ef736b22`. Large-table split storage followed
at `0fce29c16` with bootstrap `81c08489f`. Var/Pool storage retirement and later
split layouts superseded parts of earlier hash-table designs. These choices
were based on named lookup, insertion, memory, and build workloads, not one
universal container-performance result.

## Tools and commands

Build prerequisite and parallel-translation work improved development.
A depfile shortcut was rejected after reproducing stale objects. Startup
investigation at `b8173e817` separated stale-stage measurements from converged
compiler behavior and rejected one replay-floor optimization.

External-command phases established ordinary command programs and shared
compiler linking. Build/run/script moved externally at `b4f96d2e`, alongside
package, editor, and project-creation commands. Successive scripting APIs
superseded their September predecessors. Selected repository tools moved to
x2c; the broader porting umbrella closed without commissioning every remaining
port. Compiler-backed documentation generators replaced parallel declaration
readers. Repository metrics deliberately remained Python after a port imposed
an unnecessary compiler dependency on site generation.

The graph service (`0420f333`) delivered reusable immutable analysis snapshots,
with distinct startup and warm-query costs. An earlier editor-reuse proposal
was declined for insufficient workload and invalidation evidence. Current
command boundaries are in [external commands](../agents/external-commands.md)
and [the CLI reference](../docs/src/reference/cli.md).

October 28 located-failure work (`a6edf5ac6` through `26a85905b`) added source
locations, macro-expansion context, `Var.convert_at`, and source-map controls.
It did not establish universal location coverage; the file-scope gap remains
in the current-work list.

## REPL and editor work

REPL work progressed from incremental-session experiments through line editing
(`a04cbb07`), runtime visibility (`39578b76`), semantic completion, and compiled
prompt functions. October source loading initially used separate helpers and
restricted datum exchange. Shared-helper delivery `9051bcd1` replaced that
arrangement. The native library playground at `cdad3ab09` on October 29
superseded earlier execution and lifetime assumptions. Early memory-growth
investigations did not establish every cause of retained memory.

The language server became an external stdio command using existing compiler
information. Its editor client was published and tested. Those milestones
were distinct from later cursor, dependency, and platform follow-ups.

## Packages, applications, and releases

Package and application studies established specific source-installation,
relocation, and external-consumer results. They did not collectively prove
signing, notarization, or every platform's application distribution. SQLite
integration included ordinary x2c and embedded Lisp clients. Networking and
HTTP supplied real applications before the Notes rewrite at `1f4115f28`.
A later database-thread experiment improved some latencies but lost throughput
and consumed more CPU; the ordinary Notes example retained its mutex design.

Torch milestones delivered an ordinary libtorch surface, Scope finalizers,
training examples, MPS and Linux CPU support, Adam interchange, custom
first-order gradients, and Lisp operations through `9c36b76` and `1dbf258`.
Matched tabular, CNN, sequence, and interop studies retained unfavorable
results, including an accepted stock-Adam explicit tabular tolerance failure. These are
revision-specific results, not current speed or numerical guarantees. The
optional C* verification package shipped and was removed October 16 because
its platform/dependency maintenance cost was excessive.

Browser playground phases 1-2 delivered a hybrid service and browser WASM
execution, not a fully client-side compiler. The C-compatibility campaign
improved from three successful corpus units to fourteen of twenty-two;
eight remained unsupported when the campaign ended October 15.

Release work established public dev, immutable candidates, staging, promotion,
verification, and restoration. Release histories did not themselves authorize
production promotion. Current owners are [releasing](../agents/releasing.md),
[release operations](../etc/release/README.md), package READMEs, and dependency
profiles. Historical runner matrices and package counts are not current policy.

## Reviews, simplification, and deferred research

Source simplification moved through graph findings, function beautification,
module organization, and a consolidated code standard. The September file-move
experiment saved only about twenty-six cross-file calls. Adoption lists and
unbuilt detector ideas did not become permanent implementation obligations.
An onboarding campaign was retired after failing its acceptance condition,
despite useful delivered improvements.

Deletion audits also recorded false positives: iterator combinators and Error
accumulation were deliberately restored. Low in-tree use did not establish
that a public API was unnecessary. Bypassing Match admission memos made named
workloads 1.29-2.35 times slower over 21 paired processes; that experiment
rejected the bypass, not every future cache design. Packed-layout replay,
unsupported stabilization machinery, and a costly tag-ledger port were removed
or reverted in their recorded revisions.

Prepared literal formatting remained a feasibility experiment without an
identified shipped caller. Complete synthetic exports saved 3.73 ms and
4.00 ms across 20,000 records; those applications did not establish demand
for another public declaration. Compiler-ownership inventories and lifetime
extensions remained dated investigations. JSON tag-preserving round trips,
shared assertions, Array rest, meta Map crossings, TagId generation, arbitrary
quotation rewrites, a browser-only compiler, and an x2c playground-server
rewrite were unselected ideas, not unfinished commitments.

September-November reviews repeatedly found defects despite contemporary
green checks. Repair records distinguished reproduced defects, corrected
misdiagnoses, deliberate contracts, and coverage limits. November 2's second
remediation published at `a7a01924c`, with validated code `1b968f1a6`, compiler
and runtime repairs, runtime Lisp parity, package notices, command fixes,
and source/documentation cleanup. All eight user decisions and element
provenance were applied. Differing decimal parsers, package guards, platform
primitives, and the runtime/meta hash boundary were retained with reasons.
Its validation and performance numbers remain in the original Git record.

## Outstanding-plan adjudication, 2026-11-02

The four files formerly marked active were checked against `a7a01924c`.
Their genuine remaining work moved to the README; their delivered campaigns
are historical. Shared qualifier loops were already consolidated. The AST
catalog and rewrite ordering/decline explanations already have current book
and API owners. Runtime Lisp truthiness and execution-limit explanation, and
the approved optional structured-lint interface, remain incomplete.

The proposed Lisp.bind reorder was superseded by its explicit transfer-on-
failure contract. Public Lisp API deletion was superseded by keep-and-test.
Blanket null audits and the separate embed reader, duplicate script-record
read, and source-read diagnostic refinements were not demonstrated collective
correctness defects; they are not retained as mandatory repair campaigns.

Included-header attribute macros fail in ordinary mode but work with `--cpp`.
The old unconditional parser-defect label did not settle that compatibility
boundary. Fresh documentation validation without prior evidence still runs all
output samples; a PR range alone does not prove those outputs were validated.
That behavior is not a reproduced correctness failure or a selected gate change.
Included-header visibility, Linux linker tracing, and intermediate CPP
arithmetic retain bounded evidence questions in the README. No old architecture restriction, blanket audit, or
recurring validation requirement is created by this consolidation.
