# Source beauty baseline reproductions

> Status: reference - 2026-09-29.
> Inert current-tree evidence for [source-beauty-execution](source-beauty-execution.md).
> Baseline: `247b7fbe59198517a86a3d1f041448f0c9d30f90`.

Copy each code block to a scratch file, build with the configured stage0
compiler, and retain output under debug/. None is a new recurring check.
The parent also keeps executable originals in .context/source-review/probes/.

## callback-wide.x

```x2c
static unsigned long invoke(unsigned long (*fn)(unsigned long)) {
  return fn(0x100000001UL);
}
int main(void) {
  unsigned long result = invoke(%!(x) => x);
  printf("result=%lu\n", result);
  return result != 0x100000001UL;
}
```

## cleanup-shadow.x

```x2c
#define IS_VOLATILE(x) _Generic(&(x), volatile int *: 1, default: 0)
int main(void) {
  int value = 0;
  try { value = 1; }
  catch %(unused *): {}
  {
    int value = 2;
    printf("inner volatile=%d\n", IS_VOLATILE(value));
    return IS_VOLATILE(value);
  }
}
```

## duplicate-manifest/main.x

```x2c
int main(void) { return 0; }
```

## duplicate-manifest/x2c.toml

```toml
[dependencies]
[dependencies]
[target.app]
sources=["main.x"]
```

## error-flat-list.x

```x2c
#include <stdlib.h>
int main(int argc, char **argv) {
  int count = argc > 1 ? atoi(argv[1]) : 1000;
  Array values = [];
  for (int i = 0; i < count; i++) values.push(i);
  List detail = values.list_free();
  try raise %(bad-arg (detail $detail));
  catch %(bad-arg *cause): {
    printf("caught %d values\n", count);
  }
  return 0;
}
```

## json-locale.x

```x2c
#include <locale.h>
#include "json.x"
int main(void) {
  if (!setlocale(LC_NUMERIC, "de_DE.UTF-8")) return 2;
  Var parsed = Json.parse("1.5"), original = 1.5;
  printf("decimal=%s parsed=%.17g emitted=%s\n",
         localeconv()->decimal_point, parsed.double(), original.json());
  return 0;
}
```

## list-builders.x

```x2c
static size_t retained(int count, int append) {
  Pool.open();
  size_t before = Pool.current().stats().interned;
  List result = NULL;
  if (append) {
    for (int i = 0; i < count; i++) result = result.append(%($i));
  }
  else {
    Array values = [];
    for (int i = 0; i < count; i++) values.push(i);
    result = values.list_free();
  }
  size_t added = Pool.current().stats().interned - before;
  if (result.len() != count) abort();
  Pool.close();
  return added;
}
int main(void) {
  printf("append=%zu array=%zu\n", retained(1000, 1), retained(1000, 0));
  return 0;
}
```

## macro-wide.x

```x2c
int main(void) {
  Var source = 4294967297;
  Var lifted = $(begin 4294967297);
  Var constructed = $(x2c.literal.int 4294967297);
  printf("source=%ld lifted=%ld constructed=%ld\n",
         source.integer(), lifted.integer(), constructed.integer());
  return 0;
}
```

## match-case.x

```x2c
int main(void) {
  Lisp lisp = $auto(Lisp.kernel());
  lisp.eval_string(File.open("etc/init.xlisp", "r").string_close());
  Var result = lisp.eval_string("(def n 0) "
    "(defun tick () (begin (def n (+ n 1)) '(b))) "
    "(match-case (tick) ((a) 0) ((b) 1)) n");
  printf("subject evaluations=%ld\n", result.integer());
  return 0;
}
```

## match-order-direct.x

```x2c
$(def review_order nil)
int main(void) {
  match ((Var) $(begin (def review_order (cons 'subject review_order)) 0)) {
    case %(*) : {
      (void) (0 + $(begin (def review_order (cons 'arm review_order)) 0));
    }
  }
  puts($(repr (reverse review_order)));
  return 0;
}
```

## match-order-macro.x

```x2c
$(def review_order nil)
macro Statement $ordered() => {
  match ((Var) $(begin (def review_order (cons 'subject review_order)) 0)) {
    case %(*) : {
      (void) (0 + $(begin (def review_order (cons 'arm review_order)) 0));
    }
  }
}
int main(void) {
  $ordered();
  puts($(repr (reverse review_order)));
  return 0;
}
```

## order-direct.x

```x2c
$(def review_order nil)
int main(void) {
  try {
    (void) (0 + $(begin (def review_order (cons 'body review_order)) 0));
  }
  catch: {
    (void) (0 + $(begin (def review_order (cons 'catch review_order)) 0));
  }
  finally {
    (void) (0 + $(begin (def review_order (cons 'finally review_order)) 0));
  }
  puts($(repr (reverse review_order)));
  return 0;
}
```

## order-macro.x

```x2c
$(def review_order nil)
macro Statement $ordered() => {
  try {
    (void) (0 + $(begin (def review_order (cons 'body review_order)) 0));
  }
  catch: {
    (void) (0 + $(begin (def review_order (cons 'catch review_order)) 0));
  }
  finally {
    (void) (0 + $(begin (def review_order (cons 'finally review_order)) 0));
  }
}
int main(void) {
  $ordered();
  puts($(repr (reverse review_order)));
  return 0;
}
```

## sdk-name-string.x

```x2c
macro Unit $make() => {
  $(list (x2c.decl.make '(int) "review_answer"
                          (x2c.literal.int 42)))...
}
$make();
int main(void) {
  printf("%d\n", review_answer);
  return 0;
}
```

## sdk-name-tag.x

```x2c
macro Unit $make() => {
  $(list (x2c.decl.make '(int) (x2c.ident "review_answer")
                          (x2c.literal.int 42)))...
}
$make();
int main(void) {
  printf("%d\n", review_answer);
  return 0;
}
```

## self-family-probe/macro-only/review-client.x

```x2c
#include "review-family.x"

typedef ReviewProbeNativeInts ReviewProbeMeasurements;

int ReviewProbeMeasurements.done(ReviewProbeMeasurements value) {
  return value.len();
}

int review_chain(ReviewProbeMeasurements value,
                 ReviewProbeMeasurements other) {
  return value.copy().getslice(0, 0, 1).setslice(0, 0, other)
    .remslice(0, 0).splice(0, 0, other).concat(other).reverse().done();
}

int main(void) {
  ReviewProbeMeasurements values = (ReviewProbeMeasurements)
    ReviewProbeNativeInts.new();
  ReviewProbeMeasurements other = (ReviewProbeMeasurements)
    ReviewProbeNativeInts.new();
  values.push(2);
  other.push(7);
  printf("%d\n", review_chain(values, other));
  return 0;
}
```

## self-family-probe/macro-only/review-family.x

```x2c
#pragma once
#include "x2c.x"
$(import "array-generics.xmacro")
#include <limits.h>
#include <string.h>

typedef Block ReviewProbeNativeInts;

static void _bad_index(String owner, int index, size_t size) {
  raise %(bad-arg (owner $owner) (index $index) (size $size));
}
static void _bad_operation(String owner, Symbol operation) {
  raise %(bad-arg (owner $owner) (operation $operation));
}
static void _size_limit(String owner, size_t size) {
  raise %(size-limit (owner $owner) (size $size));
}
static void _bad_step(String owner, int step) {
  raise %(bad-arg (owner $owner) (step $step));
}

$array.core.family(ReviewProbeNativeInts, int);
$array.typed.family(ReviewProbeNativeInts, int, 0, "ReviewProbeNativeInts");
```

## self-family-probe/with-literals/review-client.x

```x2c
#include "review-family.x"

typedef ReviewProbeNativeInts ReviewProbeMeasurements;

int ReviewProbeMeasurements.done(ReviewProbeMeasurements value) {
  return value.len();
}

int review_chain(ReviewProbeMeasurements value,
                 ReviewProbeMeasurements other) {
  return value.copy().getslice(0, 0, 1).setslice(0, 0, other)
    .remslice(0, 0).splice(0, 0, other).concat(other).reverse().done();
}

int main(void) {
  ReviewProbeMeasurements values = (ReviewProbeMeasurements)
    ReviewProbeNativeInts.new();
  ReviewProbeMeasurements other = (ReviewProbeMeasurements)
    ReviewProbeNativeInts.new();
  values.push(2);
  other.push(7);
  printf("%d\n", review_chain(values, other));
  return 0;
}
```

## self-family-probe/with-literals/review-family.x

```x2c
#pragma once
#include "x2c.x"
$(import "array-generics.xmacro")
#include <limits.h>
#include <string.h>

typedef Block ReviewProbeNativeInts;

static void _bad_index(String owner, int index, size_t size) {
  raise %(bad-arg (owner $owner) (index $index) (size $size));
}
static void _bad_operation(String owner, Symbol operation) {
  raise %(bad-arg (owner $owner) (operation $operation));
}
static void _size_limit(String owner, size_t size) {
  raise %(size-limit (owner $owner) (size $size));
}
static void _bad_step(String owner, int step) {
  raise %(bad-arg (owner $owner) (step $step));
}

$array.core.family(ReviewProbeNativeInts, int);
$array.typed.family(ReviewProbeNativeInts, int, 0, "ReviewProbeNativeInts");

Self ReviewProbeNativeInts.copy(Self);
Self ReviewProbeNativeInts.getslice(Self, int, int, int);
Self ReviewProbeNativeInts.setslice(Self, int, int, Self);
Self ReviewProbeNativeInts.remslice(Self, int, int);
Self ReviewProbeNativeInts.splice(Self, int, int, Self);
Self ReviewProbeNativeInts.concat(Self, Self);
Self ReviewProbeNativeInts.reverse(Self);
```

## sizeof-box.x

```x2c
typedef char Huge[4294967297ULL];
int main(void) {
  Var value = sizeof(Huge);
  printf("native=%llu boxed=%ld\n",
         (unsigned long long) sizeof(Huge), value.integer());
  return 0;
}
```

## symbol-docs.x

```x2c
/** First. */
int first(Symbol token) => token == <(>;
/** Second. */
int second(void) => 7;
int main(void) {
  printf("%d %d\n", first(<(>), second());
  return 0;
}
```

For paired Self families, compile client and family units together. Both
variants print 1; compare their seven signatures and alias-only .done chaining.
The JSON child changes LC_NUMERIC only inside itself. The large Error probe
takes a count; 200000 crashes at baseline on the reviewed host. The callback
probe fails native compilation and the tagged-name probe aborts translation.
Symbol-doc comparison uses tools.x2c_source.definitions on <(> versus <x>;
the original source compiles. Complete observed outputs are in the review.
