# Bug findings at the f28fc36 baseline

> Status: reference
> Eight defects reproduced at `f28fc36`, recorded 2026-09-22. No fixes were
> made during the audit. Later `dev` changes have not been revalidated against
> these probes; reproduce each finding there before treating it as current
> repair work.

Baseline: `f28fc36fd11116666cf21962c66c5b27dda66d0b`, 2026-09-22.
All eight findings were open at the reviewed baseline. Source links are
pinned to that commit, not to the evolving `dev` branch.

This is the baseline defect queue. Architectural removal work has its own
independent
[consolidation catalog](consolidation-catalog-f28fc36.md). Passing these bug
cases does not, by itself, complete any consolidation item.

## Queue

| ID | Priority | Reproduced result | Repair area |
| --- | --- | --- | --- |
| B01 | High | Constant file initializer becomes invalid C | File initializer classification/qualification |
| B02 | High | Empty Array/Map local statics become invalid C | Lowered collection classification |
| B03 | High | Parameter-dependent sizeof local static becomes invalid C | Evaluated versus unevaluated sizeof |
| B04 | Medium | Pool String escapes receive no warning | String result ownership |
| B05 | Medium | A helper hides pooled-List return ownership | Interprocedural pooled-result summaries |
| B06 | Medium | Same-Pool nested Lists produce false escape warning | Retained-argument destination ownership |
| B07 | Medium | Direct allocators omitted while a wrapper is counted | Graph allocation reporting |
| B08 | Medium | Compiled public definition absent from successful API audit | API definition enumeration |

Priorities are relative to this review, not a claim that every failure affects
ordinary applications. Compiler-output findings are translation success followed
by native compilation failure; lifetime findings are diagnostic defects, not
executed use-after-free demonstrations.

## B01. File-scope constant sizeof emits conflicting C types

Probe:

```c
int external_function(void);
const size_t file_width = sizeof(external_function());
```

The compiler emits `size_t file_width;` and a constructor assignment, while
the generated header declares `extern const size_t file_width;`. Native
compilation rejects both the inconsistent declaration and assignment to const.
The int-returning call is unevaluated; raw C accepts this initializer.

Cause: [cache.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/cache.x#L546),
lines 546-554, descends into the sizeof operand; lines 286-348 then defer the
initializer and strip definition qualification.

Repair must preserve fixed-size sizeof as a native constant and keep header
and definition qualification consistent. Do not exempt every sizeof: B03
requires evaluation. Controls already compiled successfully: raw C with this
expression and x2c with `sizeof(int)`.

Evidence: [constant.x](#constantx) and [recorded results](#recorded-results).

## B02. Empty Array/Map local statics bypass runtime initialization

Separate functions containing `static Array value = [];` and
`static Map value = {};` emit native static initializers calling Array_new
and Map_new. Both are rejected as nonconstant C initializers.

Cause: [transform.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/transform.x#L1009),
lines 1009-1032 and 1720-1721, produces `varray`/`vmap` before cleanup runs.
[cleanup.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/cleanup.x#L269),
lines 269-340, still tests `array`/`map` at line 307. Empty forms have no
other runtime-valued child to trigger initialization.

Repair must route these through first-use initialization, preserving once,
retry, threaded behavior, and ordinary referent ownership. The language
contract is [language.md](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/docs/src/reference/language.md#L1899),
lines 1899-1917; this does not require extending a temporary Scope's lifetime.

Evidence: [local_containers.x](#local_containersx) and [recorded results](#recorded-results).

## B03. Parameter-dependent sizeof is misclassified as constant

`static const size_t width = sizeof(int[n]);` inside a function taking `int n`
is left as a native C static initializer. Native compilation rejects it as
nonconstant. The static object's type is fixed-size size_t; only its initial
value depends on the parameter.

Cause: [cleanup.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/cleanup.x#L269),
lines 269-340, skips all sizeof operands at line 331. The documented local
static behavior includes runtime argument-dependent initializers.

Repair must distinguish fixed-size unevaluated operands from evaluated VLA
size expressions. Verify that B01 remains native constant storage, while this
case evaluates on the first successful initialization only.

Evidence: [local_vla.x](#local_vlax) and [recorded results](#recorded-results).

## B04. Pool-owned String returns are not diagnosed

Direct returns of String.new(bytes) and String.malloc(size) from a Pool.open /
deferred Pool.close bracket produce no region warning. A matching direct
cons return does warn. Runtime ownership is Pool, not active Scope:
[string.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/lib/string.x#L207),
lines 207-215 and 337-415.

Cause: [regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L83),
lines 83-117 omit canonical String constructors and classify String_malloc as
Scope allocation. Birth assignment is at lines 301-328.

Repair result ownership without asserting that copying String constructors
retain their input pointer. The current `(pool)` row also encodes cons
argument retention, so merely inserting String names with that row is wrong.
Canonical ancestor reuse means the warning remains conservative. No freed
String was dereferenced during reproduction.

Evidence: [ownership.x](#ownershipx), lines 3-19, and [recorded results](#recorded-results).

## B05. A pooled-result helper loses its caller's Pool ownership

`make_list(value)` returns cons(value,NULL), without opening a Pool itself.
A caller returns make_list(value) from its Pool bracket without a warning.
The equivalent direct cons return warns. The graph allocation-returns command
identifies make_list as returning a pooled cons.

Cause: [regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L292),
lines 292-328 and 339-371, cannot carry pooled-result kind through the Boolean
FRESH summary at lines 237-246.

Repair must preserve possible pooled-result provenance across calls. Do not
replace the graph's all-return-path classification with a may-return-fresh
Boolean, or claim every canonical constructor physically allocates.

Evidence: [ownership.x](#ownershipx), lines 26-34, and [recorded results](#recorded-results).

## B06. Same-Pool List construction produces a false escape warning

Inside one Pool bracket, `a = cons(value,NULL); b = cons(a,NULL);` is used
only before closing that Pool. The compiler nevertheless warns that `a` can
outlive its region when stored through an unknown pointer.

Cause: [regions.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/src/regions.x#L237),
lines 237-246 and 443-461, treats cons argument retention as an unknown sink
instead of attaching it to the receiving cell's Pool.

Repair must use the actual destination owner. Do not silence all cons sinks:
retaining a short-lived mutable object in a longer-lived List remains a
meaningful escape.

Evidence: [ownership.x](#ownershipx), lines 36-42, and [recorded results](#recorded-results).

## B07. Loop report omits direct allocation but counts a wrapper

A loop containing Scope.malloc, String.new_len, and a local helper returning
Scope.malloc reports zero direct allocation sites and one scoped helper site.

Cause: [lifetime.x](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c-graph/lifetime.x#L130),
lines 130-167, uses a narrower direct-call set than lines 169-182 used for
helper returns. Missing direct calls go to project target resolution; runtime
definitions were deliberately not supplied in this isolated input.

Repair must make direct/helper coverage consistent. Report counts will change;
do not label that a byte-identical refactor or change helper certainty silently.

Evidence: [ownership.x](#ownershipx), lines 44-51, and [recorded results](#recorded-results).

## B08. API audit succeeds while omitting a compiled public definition

A scratch source declares an int prototype and implements it using a
zero-argument Unit macro with x2c.ident for its exported name. Translation
and native compilation succeed. Its interface contains generated_api(int),
but the hash-checked API collector returns an empty callable set without error.

Cause: [x2c_source.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/x2c_source.py#L656),
lines 656-736, skips unit macros with no holes; the collector at
[gen-api-reference.py](https://github.com/gwf/x2c/blob/f28fc36fd11116666cf21962c66c5b27dda66d0b/tools/gen-api-reference.py#L604),
lines 604-650, only checks functions selected by the scanner.

Repair must enumerate actual selected definitions, distinguishing prototypes,
private/generated forms and imports. An additional probe without the explicit
prototype emits the function but no interface function row; therefore existing
interface rows alone cannot be assumed to provide complete enumeration.
This reproduces the callable collector's gap, not a claim that the entire
repository doc-check ran successfully on the modified scratch tree.

Evidence: [audit_surface.x](#audit_surfacex), the [collector driver](#surface_probepy),
and [recorded results](#recorded-results).

## Reproduction environment and commands

The preceding review built a clean archive of the baseline with
`make build-safe`. Compiler: x2c 0.14.0,
stage 0 built from that archive. Native toolchain: existing Apple clang 17.0.0,
arm64-apple-darwin24.6.0. No installation or bootstrap refresh was performed.
This report split reread the existing evidence and verified the unchanged
source baseline; it did not rebuild or rerun those probes.

To reproduce, use a separate checkout or archive of the exact baseline.
Save the complete probe sources below under their stated paths, then run:

```sh
mkdir -p debug probes/out
make build-safe >debug/bootstrap.log 2>&1
make -C tools/x2c-graph X2C_ROOT=../.. all >debug/graph-build.log 2>&1
```

Run the following commands individually: the first three native compilations
are expected to fail at this baseline, so do not stop the sequence at the first
nonzero result.

```sh
builds/0/x2c translate --out-dir probes/out probes/constant.x
cc -fsigned-char -pthread -O2 -iquote builds/0/lib \
  -c probes/out/constant.c -o probes/out/constant.o
builds/0/x2c translate --out-dir probes/out probes/local_containers.x
cc -fsigned-char -pthread -O2 -iquote builds/0/lib \
  -c probes/out/local_containers.c -o probes/out/local_containers.o
builds/0/x2c translate --out-dir probes/out probes/local_vla.x
cc -fsigned-char -pthread -O2 -iquote builds/0/lib \
  -c probes/out/local_vla.c -o probes/out/local_vla.o
builds/0/x2c translate --out-dir probes/out probes/ownership.x
tools/x2c-graph/builds/x2c-graph loop-allocations --all probes/ownership.x
tools/x2c-graph/builds/x2c-graph allocation-returns make_list probes/ownership.x
builds/0/x2c translate --out-dir probes/out src/audit_surface.x
cc -fsigned-char -pthread -O2 -iquote builds/0/lib \
  -c probes/out/audit_surface.c -o probes/out/audit_surface.o
python3 probes/surface_probe.py
```

All translations above returned 0. The first three native compilations
returned 1. The API source's native compilation and collector probe returned
0, with no callables reported by the latter. The relevant source and output
are preserved below; temporary build logs are not required to read this report.
No publication gate or broad suite was run as part of the historical bug audit.
The documentation gate used to check in this report is not new behavioral
validation of these findings.

## Not established as additional bugs

- Native signature spelling differs between Func and Lisp paths; deciding
  whether to preserve that spelling is a compatibility question, not an
  additional reproduced call-conversion defect.
- A runtime-created signature may outlive its active Pool after Lisp.bind
  transfers only Func storage. This remains a source-based lifetime concern;
  no instrumented failure was reproduced.
- The foreign-qualifier ledger contains unowned/historical enforcement claims.
  That is documentation-provenance cleanup, not proof of wrong qualifier code.

These do not inflate the eight confirmed findings or authorize extra fixes.

## Portable reproduction sources

The sources below preserve the reviewed probes. Save each block at the stated
path in the baseline checkout; they are documentation, not newly enrolled test
fixtures. The ownership source retains its original line numbering.

### constant.x

Save as `probes/constant.x`:

```c
#include "x2c.x"

int external_function(void);
const size_t file_width = sizeof(external_function());

size_t local_width(void) {
  static const size_t width = sizeof(external_function());
  return width;
}
```

### local_containers.x

Save as `probes/local_containers.x`:

```c
#include "x2c.x"
Array local_array(void) {
  static Array value = [];
  return value;
}
Map local_map(void) {
  static Map value = {};
  return value;
}
```

### local_vla.x

Save as `probes/local_vla.x`:

```c
#include "x2c.x"
size_t local_vla(int n) {
  static const size_t width = sizeof(int[n]);
  return width;
}
```

### ownership.x

Save as `probes/ownership.x`:

```c
#include "x2c.x"

String pooled_string(char *bytes) {
  Pool.open();
  defer Pool.close();
  return String.new(bytes);
}

String pooled_transient(size_t size) {
  Pool.open();
  defer Pool.close();
  return String.malloc(size);
}

List pooled_list(int value) {
  Pool.open();
  defer Pool.close();
  return cons(value, NULL);
}

String scope_transient(size_t size) {
  $scope() { return String.malloc(size); }
  return NULL;
}

static void *allocate(void) => Scope.malloc(8);

static List make_list(int value) => cons(value, NULL);

List pooled_list_helper(int value) {
  Pool.open();
  defer Pool.close();
  return make_list(value);
}

void same_pool(int value) {
  Pool.open();
  defer Pool.close();
  List a = cons(value, NULL);
  List b = cons(a, NULL);
  (void) b;
}

void allocation_loop(char *bytes, size_t size) {
  for (int i = 0; i < 2; i++) {
    void *a = Scope.malloc(8);
    String b = String.new_len(bytes, size);
    void *c = allocate();
    (void) a; (void) b; (void) c;
  }
}
```

### audit_surface.x

Save as `src/audit_surface.x`:

```c
#include "x2c.x"

int generated_api(int value);

macro Unit $make_api() => {
  /** Returns the next integer. */
  int $(x2c.ident "generated_api")(int value) => value + 1;
}

$make_api();
```

### surface_probe.py

Save as `probes/surface_probe.py`:

```python
import importlib.util
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'tools'))
import x2c_source
import x2c_symbols

spec = importlib.util.spec_from_file_location('api', root / 'tools/gen-api-reference.py')
api = importlib.util.module_from_spec(spec)
sys.modules['api'] = api
spec.loader.exec_module(api)

source = root / 'src/audit_surface.x'
symbols = x2c_symbols.HeaderSymbols([x2c_symbols.read_sexp(
    (root / 'probes/out/audit_surface.xi').read_text())])
print('interface paths:', symbols.paths())
print('compiler function rows:', symbols.functions('src/audit_surface.x'))
print('source discoveries:', x2c_source.definitions_for_path(source))
audit = api._collect_public_surface(
    source, 'src/audit_surface.x', symbols, compiler=True,
    check_hash=True, root=root)
print('API audit passed:', audit.path, 'callables=', audit.callables,
      'declarations=', audit.declarations)
```

## Recorded results

These are observations from the audited baseline, not reruns on later dev.
Compiler timings, scratch-directory names and diagnostic caret lines are
omitted; the messages and graph facts below are retained.

### Native compilation

- B01: `redefinition of 'file_width' with a different type`, followed by
  `cannot assign to variable 'file_width' with const-qualified type`.
  The definition is `size_t file_width;`, the header is
  `extern const size_t file_width;`, and the constructor assigns
  `sizeof(external_function())`.
- B02: `initializer element is not a compile-time constant` for both
  `static Array value = Array_new();` and `static Map value = Map_new();`.
- B03: the same nonconstant-initializer error for
  `static const size_t width = sizeof(int[n]);`.

The B01 controls were a raw C file containing `#include <stddef.h>`,
the function prototype and the constant declaration, and an x2c file with
`#include "x2c.x"` and `const size_t file_width_control = sizeof(int);`.
Both native compilations returned 0.

### Ownership diagnostics and graph facts

The only region warnings in the ownership translation were:

```text
probes/ownership.x:18:3: region: a fresh allocation can outlive the region it was allocated in when returned
  note: region opened at line 16
probes/ownership.x:40:3: region: 'a' can outlive the region it was allocated in when stored through an unknown pointer
  note: region opened at line 37
```

Thus the direct cons return warned, neither Pool String return nor the
helper-mediated List return warned, and the same-Pool nested List warned.

The allocation-returns query reported:

```lisp
(allocation-returns "make_list" (summary (returns 1))
 (returns
  (return "probes/ownership.x" "make_list"
   pooled "cons" (location "probes/ownership.x" 28 37))))
```

The loop query's summary was:

```lisp
(summary (functions 1) (expressions 1) (direct (pooled 0) (scoped 0))
 (helper-calls (pooled 0) (scoped 1)) (reported 1))
```

Its sole candidate was `allocate` at ownership.x:48:5, with
`(operations (helper "allocate" scoped 1))` and loop depth 1.

### API collector

```text
interface paths: ('src/audit_surface.x',)
compiler function rows: {'generated_api': FuncType('int', ('int',))}
source discoveries: ()
API audit passed: src/audit_surface.x callables= () declarations= ()
```
