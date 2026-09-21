# REPL fit, status, and runtime surface

> Status: implemented through delivery 7
> Deliveries 1-7 were implemented and validated on 2026-09-21.
> The remaining standard-library and host candidates are undispatched backlog.

## Result

Make the experimental REPL pleasant to discover and useful for exploratory
work without giving interpreted code false native semantics. The first
delivery should provide readable help, contextual command completion, live and
truthfully labelled runtime statistics, and simple output. Later deliveries
may expose more value-oriented library and host operations after their module,
ownership, dependency, and capability rules are explicit.

Keep submission behavior, recovery, semantic rollback, history, native/meta
value parity, and the existing experimental compatibility contract. Do not
turn REPL convenience functions into implicit global compile-time effects.

## Current evidence

- `src/repl.x` separately hard-codes help text, command dispatch, and command
  usage. Its flat output has no headings and colon commands do not participate
  in completion.
- `ReplSession.complete` already reparses through the cursor in a rollback-only
  semantic transaction. It sees pending locals, session values and functions,
  visible types and macros, and members on typed receivers. It also filters
  ordinary functions that have no callable binding in the live Lisp session.
  The missing near-term contexts are REPL commands and their arguments, not a
  second source-namespace implementation.
- `--stats` currently writes three cumulative Lisp AUTO counters at exit.
  `Scope.stats`, `Pool.stats(Pool.current())`, and `Lisp.auto_stats` already
  expose allocation traffic, live allocation counts, canonical-pool storage
  and reuse, and evaluator activity. Scope has no live-byte accounting and the
  runtime has no portable current-RSS API or collector-cycle count.
- The evaluator represents scalars, String, Symbol, List, Array, Map, Var,
  interpreted Func values, local cells, and selected Iter adapters. Native
  structs, general pointers, C varargs, and resource handles such as File,
  Buffer, Regex, Job, Logger, and Thread do not have general representations
  or lifetime rules.
- The generated meta API ledger already has behavioral evidence for the large
  value-operation surface on String, List, Array, Map, Symbol, and Var. The
  conspicuous remaining gaps are primarily ownership, pointers, varargs, and
  native resources rather than a long list of safe aliases.

## Delivery 1: terminal fit and contextual completion

1. Give `src/repl.x` one small command descriptor table containing each colon
   command's spelling, synopsis, description, argument kind, and dispatch ID.
   Use it for dispatch, usage, help, and command completion. It is a terminal
   command list, not a source API catalog.
2. Render help in short headed sections: `Commands`, `Editing`, and `Options`.
   Align command synopses from the descriptor rows and keep lines readable at
   ordinary terminal widths. Reuse a small local row renderer; do not introduce
   a general help framework.
3. Complete a leading-whitespace-tolerant `:he` as `:help`. This command path
   wins whenever the edited line's first nonspace byte is `:`, including at a
   continuation prompt where commands are already accepted. After `:ast` or
   `:lowered`, offer only published session functions obtained from the
   existing session name entries. Commands with no argument offer none.
4. On a genuinely blank primary-prompt edit, merge colon commands with the
   existing semantic candidates. This gives commands, live values/functions,
   and visible type names while leaving the compiler authoritative for source
   visibility and callability. A blank continuation edit remains source-only;
   a colon-prefixed continuation edit follows the command rule above.
5. Add candidate kind metadata and compact grouped display in this delivery,
   so blank completion does not print the entire namespace one name per line.
   Groups are commands, session names, types, and other callable source names;
   receiver members remain their own context. Replacement and common-prefix
   behavior still use spellings alone. Do not add a completion cache or
   alternate parser.
6. Defer deeper grammar-role propagation until observed completion noise
   justifies it. If needed, carry the parser's expected role with the existing
   completion transfer rather than inferring syntax in the editor.

Keep `:symbols`'s machine-readable List output in this delivery. A human table
or a raw-output switch is a separate compatibility decision, not incidental
help cleanup.

## Delivery 2: live statistics

1. Add `:stats`; `:stats` writes to standard output and exit-time `--stats`
   writes the same rows to standard error. The deliberately changed shared
   format is:

   - `session`: definition count;
   - `evaluation`: since-open Lisp calls, machine entries, machine errors, and
     absolute live published-program bytes;
   - `scope (process)`: live allocation objects with a signed since-open delta,
     followed by since-open alloc/free/realloc calls and requested traffic;
   - `pool (current level)`: interned-identity and promotion activity; and
   - `pool (process)`: backing capacity partitioned into active and depot
     capacity, followed by since-open block and slot reuse.
   This preserves the three existing evaluator fields but does not preserve
   the old one-line byte format.
2. Capture Scope, Pool, and Lisp baselines after the session and editor are
   open. Take nonallocating session counts and all snapshots before formatting
   the report, so rendering traffic appears only in the next snapshot. Report:

   - session definitions;
   - since-open Lisp invocation, machine-entry, and machine-error counters plus
     absolute live prepared-program bytes;
   - process-wide live managed allocation-object count and its signed
     since-open delta;
   - since-open allocation, free, reallocation, and requested-byte traffic;
   - current-pool interned-identity and promotion activity; and
   - process pool backing capacity, with its active-block and depot
     partitions, plus clearly labelled reuse activity.
3. Label cumulative bytes as `requested traffic`, not memory in use. Scope
   allocation objects include process runtime, compiler, and root storage;
   they are not user values. Pool active and depot bytes are retained block
   capacity, not reachable payload, and both partition backing capacity rather
   than adding to it. Scope and Pool traffic overlap for large allocations and
   must not be summed. Label global counters as process-wide and baselined
   deltas as `since REPL open`, not session ownership. Promotion, explicit
   `Pool.free`, block reuse, and slot reuse are activity counters, not live
   value or reclamation counts. There is no garbage collector, so do not
   report pool release, reuse, or epochs as collections or GC cycles.
4. `program_bytes` is live published AUTO program storage for this Lisp
   session, not total evaluator memory. Do not include the other AUTO and Pool
   diagnostic counters in the default report; a verbose mode can be planned
   later if concrete debugging demand appears.
5. Do not add allocation-header sizes, OS-specific RSS sampling, or detailed
   `MachineStats` instrumentation in this delivery. Exact live Scope bytes and
   per-session byte attribution require a separate allocator design; peak RSS
   is not current memory.

## Delivery 3: useful output

1. Add the exact REPL-only declarations `void print(String text)` and
   `void println(String text)` to the fixed declaration fragment owned by
   `Frontend.open_session` in `src/frontend.x`, and parse it when opening the
   otherwise empty unit. `ReplSession.new` installs their native callables into
   only that unit's child Lisp session through the existing `$lisp.bind`
   mechanism; it does not mutate the inherited shared macro library.
2. The native adapters also live with the session adapter. A null `String` is
   the empty x2c String and writes zero bytes. Use length-aware output;
   `println` then writes one newline. Neither operation explicitly flushes.
   A short write or stream error raises `<io-fail>` with the operation and
   `errno`, so `ReplSession.submit` reports an evaluation failure and the next
   submission remains usable. Output precedes the terminal's result line.
   String interpolation is the formatting mechanism, for example
   `println(%"count=$count")`.
3. Reserve `print` and `println` in REPL sessions: completion offers them and a
   user definition with either name is rejected like any other live callable.
   Do not publish them into every compiler macro session until compile-time
   output as a global side effect is deliberately approved.
4. When the final expression has `void` type, treat it as an executed statement
   rather than rewriting it into a printable result. This fixes the existing
   zero-sentinel display generally, so printing does not add `=> 0`.
5. Do not call the bridge `printf` and do not accept generic rest `Var`
   arguments. C varargs require format-dependent native types and default
   promotions; a List of boxed values cannot reproduce that contract.

## Delivery 4: grammar-aware completion

Completion now carries parser-owned expression, type, statement-start,
block-start, submission-start, continuation, or member context through the
existing rollback transfer. Each grammar owner supplies its legal keywords,
and visible semantic rows are filtered by role while preserving the existing
callability check. `else`, `catch`, and `finally` have narrow continuation
hooks. The terminal groups these candidates under `Keywords`; it still offers
no punctuation, snippets, labels, operators, or editor-side grammar.

## Delivery 5: verbose statistics

`:stats verbose` and `--verbose-stats` add the complete `LispAutoStats`,
Scope, Pool, and `MachineStats` projections. Each REPL attaches a zeroed
machine counter record for its lifetime and detaches it at teardown. The
concise report remains the default, and combining both exit options prints one
verbose report. Absolute values and since-open deltas remain separately
labelled.

## Delivery 6: exact live Scope bytes

Every managed allocation now records its requested payload size beside the
public allocation header. Process-wide atomic counters track current and peak
live requested bytes across allocation, free, destruction, release, and
successful realloc; moves preserve the count and zero-sized objects contribute
zero bytes. The concise report adds current bytes and a signed since-open
delta, while verbose output adds the peak. These payload bytes remain distinct
from Pool retained capacity and Lisp program bytes; no total-memory number is
synthesized.

## Delivery 7: safe runtime formatting

`String.format(String fmt, List values)`, called as `fmt.format(values)`, is a
fixed-signature runtime and meta operation. It parses a documented C-style
subset, converts numeric values with `Var.convert`, renders `%s` with
`Var.str`, normalizes star width and precision, and sends each validated
conversion to one correctly typed `Buffer.printf` branch. A private Buffer
stages the complete result. Pointer, write-count, wide, positional, and other
unsupported formats raise `<format>` with a byte offset and reason; nested
conversion causes are retained. Native `String.printf` and compiler static
format lowering are unchanged.

## Standard-library and host candidates

These are ranked backlog candidates, not dispatched work. Each group requires
a bounded mini-plan before implementation. Initial exposure is REPL-only;
moving a deterministic operation into every compiler meta session is a later
public API decision. Prioritize by represented values, ambient-state behavior,
and whether a call owns a resource.

1. **Core scalar math:** build a named allowlist from the already declared C99
   math functions whose parameters and results are represented scalars.
   Exclude pointer-output and raw-text entries such as `frexp`, `modf`,
   `remquo`, and `nan`. Also exclude rounding-mode-sensitive entries such as
   `nearbyint`, `rint`, `lrint`, and `llrint` until the REPL's floating-point
   environment contract is settled. For every candidate, specify `errno` and
   floating-exception side effects and compare those as well as native/meta
   results, domains, and nonfinite values. Do not approve the whole scalar
   family from signature shape alone.
2. **Pure value modules:** strong candidates are `Diff.lines`/`unified`,
   `Json.parse`, `Regex.escape`, and Path's text-only `join`, `dirname`,
   `basename`, `extension`, and `stem`. Existing String digest, JSON rendering,
   collection, matching, iteration, and conversion operations should be reused
   rather than wrapped again.
3. **Read-only host queries:** candidates are `Env.get`, `Path.absolute`
   (`Path.absolute(".")` for the current directory), `Path.exists`,
   `Path.is_dir`, `Path.is_file`, `Path.is_executable`, `Path.size`,
   `Path.modified_time`, `Path.list_dir`, `Path.glob`, and `Path.read_text`.
   A general meta filesystem read must participate in compiler dependency
   ownership, rather than silently making builds depend on untracked host
   state.
4. **Mutating host and process operations:** file writes, directory creation,
   copy/move/remove/symlink, subprocess execution, clocks, and randomness need
   an explicit capability and reproducibility policy before exposure.
5. **Native resources:** defer File, Buffer, Block, Regex objects, Job, Logger,
   Context, Thread, and Mutex until the evaluator has an opaque-resource
   representation, cleanup/lifetime rules, and error-transfer behavior. Do not
   bind isolated methods that can create a handle the session cannot safely
   close.

The pure and host candidates live in optional modules that the ordinary REPL
prelude does not currently load, while `import` and preprocessing remain
outside the submission subset. Before implementing those groups, decide one
module path that reuses their authoritative declarations and implementations:
either supported session module loading or a deliberately curated REPL
prelude. Do not copy their algorithms into REPL adapters. Core math and the
small output bridge do not depend on that decision.

## Validation and delivery

- Extend the optional REPL checks with exact help output, narrow-width
  candidate presentation, command and indented-command completion,
  `:ast`/`:lowered` argument filtering, and blank completion containing a
  command, session value, session function, and type.
- Preserve pending-local/member completion and prove completion changes no
  symbols or diagnostics.
- Check `:stats` before and after known submissions for monotonic allocation
  and request traffic and stable labels without asserting host-dependent
  absolute counts. Do not require live allocations or pool capacity to be
  monotonic.
- Check print ordering, empty text, interpolation, no spurious result value,
  recovery after a failed call, completion visibility, and rejection of
  unavailable native calls.
- Give every generally installed library binding a native/meta differential
  fixture. Use inert temporary directories and controlled environment values
  for host probes.
- Update the REPL and meta-function guides and the generated meta API ledger
  where their owned behavior changes. Keep focused spike checks optional; add
  no recurring gate.
- Review and fix the completed authored diff before the required final-tree
  publication validation.

Gary authorized deliveries 4-7 as one ordered direct-to-`dev` change after the
first three deliveries. The remaining standard-library and host candidates
remain separate, undispatched work. The authored diff receives one source
review and one unchanged-tree `tools/gate-state.py ensure agent-pr-check`
publication proof.

## Plan review

The compiler parser establishes source context, `Sym` establishes visibility,
member resolution establishes receiver candidates, and the live Lisp session
establishes evaluator callability. Command completion and presentation consume
those facts without rechecking source semantics. Scope, Pool, and Lisp own the
statistics and their scopes of attribution; the formatter only projects and
labels existing snapshots.

The design reuses semantic completion, session name entries, existing runtime
counters, interpolation, native implementations, and the current binding
mechanism. The only initial lasting machinery is one terminal command table,
baseline snapshots, a shared stats formatter, and two fixed-signature session
bindings. Candidate-kind rows are justified only when grouped empty-prefix
display is implemented. No API catalog, completion cache, alternate parser,
generic varargs bridge, resource wrapper, or copied standard-library algorithm
is proposed.

No new validator, dedicated compiler diagnostic, or negative compiler fixture
is proposed. Optional REPL checks confirm that failed or unpublished names do
not appear in completion, preventing false publication; that `:ast` and
`:lowered` do not suggest values, preventing invalid command suggestions; and
that unavailable native functions remain absent and rejected, preventing an
interpreted call from crossing an unsupported ABI. These checks exercise
existing boundaries rather than creating a new language rejection. Native
comparison fixtures protect value and side-effect parity for bindings that
ordinary native and interpreted execution share.
