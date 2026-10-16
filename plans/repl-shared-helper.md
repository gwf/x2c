# One native helper for the REPL

> Status: active
> Planned 2026-10-16; shared loading and object calls are implemented.
> Combined verification and publication remain in progress.
> Gary selected resetting all loaded native state after every successful
> load, including a first load of an additional file.
> Adjacent meta/macro campaign notes were checked against `e057f9509` on
> 2026-10-16. They do not change the selected behavior or delivery mode.

## Result and example

Keep `:load "file.x"` and one REPL namespace. All loaded files and their
source dependencies form one native program in one helper process.
Top-level input remains interpreted. Prompt functions retain their current
compiled execution and shared prompt-variable storage.
Keep the existing external command, Lisp evaluator, and Lisp runtime.
The Lisp forms constructed with `%(...)` in `repl-lower.x` are evaluator
data; source-code quotation rules do not require replacing those forms.

`objects.x` defines public storage and a function:

```x2c
#pragma once
struct Point { int x; int y; };
int samples[3] = {10, 20, 30};
struct Point point = {1, 2};
int first(void) { return samples[0]; }
```

`operations.x` uses ordinary declarations through its include:

```x2c
#include "objects.x"
int sum(const int *values, int count) {
  int total = 0;
  for (int i = 0; i < count; i++) total += values[i];
  return total;
}
void shift(struct Point *p, int dx) { p->x += dx; }
int advance(void) { samples[0]++; return first(); }
```

After loading both files, `sum(samples, 3)` returns 60, `shift(&point, 5)`
changes `point.x` to 6, and `advance()` changes `samples[0]` to 11. The
native calls share the actual objects. Passing a struct by value still
makes the ordinary native copy inside the helper.

## Loading and reload

- Every load builds the current contents of all registered files and their
  dependencies as one candidate program. Resolved paths identify files.
  A source dependency has one provider and one instance of its storage;
  explicitly loading that dependency exposes its public names without
  adding another copy. Ordinary C header and internal-linkage rules remain.
- Source files use normal includes, prototypes, and `extern` declarations.
  Compatible declarations refer to one public definition. Distinct public
  definitions with the same name conflict. Static definitions stay private;
  const objects and fields retain their restrictions. Retain the existing
  single public `main` rule and its argc/argv and output adapters.
- Prepare the complete candidate and validate all existing public function
  signatures, globals, and type declarations before publication. Keep the
  existing compatibility rules, including parameter renaming and additive
  names. Removing or changing an existing public declaration requires a
  new session. Check the whole program, including edits outside the file
  named by the command.
- On success, replace the shared helper and reset **all loaded native
  state**, including static state and dependencies. This applies to adding
  a file, reloading an unchanged file, and reloading an edited file. Report
  that reset with the existing loaded/reloaded result.
- Prompt variables, prompt functions, previously returned data, and saved
  callable adapters survive. Existing callers use the replacement program.
  Compile, link, declaration, or preparation failure leaves the old helper,
  its state, and published names intact.
- A crash, exit, or timeout restarts the whole native program on the next
  call and therefore resets all loaded state. Ordinary caught errors keep
  the helper running. No native state migration or old code retention.

## Implementation

1. Generalize `Frontend.build_loaded` from one exposed root to the session's
   root set. Reuse `meta-project` scanning, provider ownership, native
   objects, dependencies, cache, and linking. Extend binding-aware provider
   naming to compatible cross-root declarations, including `extern` objects;
   do not concatenate source text or invent another linker. Ensure all
   required groups built, rather than accepting a partially usable helper.
2. Move helper ownership to the session. Keep file records for declarations
   and inspection origins. Make existing function and global adapters read
   the session's current helper. Retain the candidate executable, prepare
   publication, switch once, and close the previous helper. Native state
   initializes for the shared session, not each provider-table selection;
   compilation and declaration inspection must not leak into runtime state.
3. Extend loaded-call adaptation to select loaded globals and their fields
   or elements inside the helper. Generate typed bridges during load and
   recognize eligible calls before converting their arguments to scalar
   getters. Send object selections and scalar arguments, never process
   addresses. Resolve selections in the current helper, preserving native
   pointer/reference aliasing and struct-by-value semantics. Reuse ordinary
   typing, conversions, const enforcement, and existing index checks.
   Extend `repl-globals.x` rewriting before either prompt backend runs.
   `C.globals`/`C.gaddress` own prompt storage in the REPL process; loaded
   objects must not enter that address path.
4. Use that call path from interpreted input and compiled prompt functions.
   Scalar arguments and indices execute once under existing evaluation
   rules. `$ast.walk` visits sibling Lists right to left: use it only for
   order-independent discovery, never to schedule argument evaluation.
   Keep supported data/void results and existing saved-callable
   behavior. Prompt-local native objects, raw pointer results, callbacks,
   and arbitrary remote heap objects remain outside the crossing contract.
   No per-line compilation or general remote-object registry is introduced.
5. Update the REPL guide, help, and existing tests. Review and correct the
   completed authored diff, run the focused checks and publication gate,
   and deliver through the repository's normal workflow. Performance
   comparison remains separate work; add no gate or recurring requirement.

## Verification

Extend existing tests for cross-file calls and mutations, shared dependency
storage, prototype/extern linkage, nested object arguments, aliasing, and
single evaluation. Exercise direct and compiled prompt callers, saved
functions, equivalent paths, privacy, const, bounds, and crossing limits.
Replace independent-helper expectations with whole-program resets on
successful loads and restarts. Rejected loads must preserve old results,
counters, and prompt state. Retain the autodiff and main walkthroughs.
Run `sh commands/repl/tests/run.sh`, the existing meta-helper probe, and
`tools/gate-state.py ensure agent-pr-check` for implementation delivery.
Build changed commands with `make commands` as needed. The publication gate
already runs `make commands-check`, including the REPL API tests; do not add
a duplicate broad check. If interpreted lowering changes, compare `--dump`
on a bounded set of unchanged submissions. New loaded-call forms can differ.

## Adjacent-work disposition

- PR #226, "share REPL lowering helpers and walks," is merged, and its
  source commit `bf839dc36` is already an ancestor of this checkout. Keep
  `_lower_block_apart`, the consolidated name scans and content lowering,
  direct `compound_operator()` calls, and `_size_limit`; there is no pending
  rebase work for that change. Its reported 81-probe comparison was not
  rerun here and is not evidence for the proposed helper changes.
- Two premises are stale: typed prompt functions already compile, and
  loaded scalar globals, fixed arrays, and structs already support reads
  and writes. The campaign's avoided areas now contain the implementation
  this plan extends. Its partial review is not coverage of those paths.
- The top-level `match` binder defect still reproduces. With
  `List p = %(point 1 2);` and `int r = 0;`, the wildcard pattern sets `r`
  to 5; both reported binder variants reject with `unsupported expression`
  and leave `r` at 5. Keep this as a separate defect and coverage gap; do
  not make its repair a prerequisite or codify rejection as intended behavior.
- The enum reconstruction and `_lower_setindex` simplifications remain
  possible local cleanups if those functions need changes. They are not
  additional deliverables. Keep `_bare` unchanged unless nested `at`
  semantics are established; recursive unwrapping is not proven equivalent.
  Defer the embed-text meta wrapper and direct `C.*` alias binding: neither
  is needed for shared loading, and the former could add build work.
- The campaign's command-only bootstrap exemption does not cover this
  plan's `src/meta-project.x` and related compiler changes. The existing
  publication gate owns generated refresh and bootstrap proof. Its
  shared-integrator direction belonged to that session; this session keeps
  the normal individual/direct delivery unless Gary changes it.

## Plan review

The builder already links multiple providers. A temporary two-source probe
passed an array and struct pointer inside one helper and observed shared
mutations: consecutive calls returned 78 and 85. Multiple-load publication
and prompt object-argument bridges remain unimplemented.

Trust compiler binding, canonical types, and provider identity. Reuse native
initialization and transport; delete per-file helper ownership. The session
owns replacement, and typed bridges own the process crossing. Existing Match,
AST templates, and compiler operations provide the implementation vocabulary.

Retain declaration checks for live caller compatibility, collision/link
checks for unique definitions, and const/bounds/crossing checks for valid
native access. Negative tests protect those rules and atomic replacement;
add no duplicate validators or diagnostic-only checks. Resetting the entire
helper avoids state serialization, pointer rebasing, and module hot swapping.
