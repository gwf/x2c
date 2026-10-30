---
slug: code-is-data
section: magic
tab: code is data
title: A code literal is a List. Take it apart.
---

```x2c
~#include <assert.h>
~
int main(void) {
  List code = %(block
    (if (not ready) (call wait) (call start))
    (if true (call save) (call discard)));
  puts(simplify(code).str());
  // ( block ( if ready ( call start ) ( call wait )) ( call save ))
  ~assert(simplify(code) ==
  ~       %(block (if ready (call start) (call wait)) (call save)));
  ~assert(simplify(%(if false (call wrong) (call right))) == %(call right));
  ~assert(simplify(%(if (not true) (call wrong) (call right)))
  ~       == %(call right));
  ~assert(simplify(%(if ready (if true (call yes) (call wrong))
  ~                           (if false (call wrong) (call no))))
  ~       == %(if ready (call yes) (call no)));
  ~assert(simplify(%(block)) == %(block));
  ~assert(simplify(%(call untouched)) == %(call untouched));
  return 0;
}

// Recognize a nested condition and exchange its branches.
List simplify(List node) {
  match (node) {
    case %(if (not ?condition) ?yes ?no):
      return simplify(%(if $condition $no $yes));
    case %(if true ?yes ?): return simplify(yes);
    case %(if false ? ?no): return simplify(no);
    case %(if ?condition ?yes ?no):
      return %(if $condition $(simplify(yes)) $(simplify(no)));
    // Capture a whole block, transform it, splice it back in.
    case %(block *body):
      return %(block @(body.map(%!(List item) => simplify(item))));
    default: return node;
  }
}
```

The same `%(...)` that holds your data holds a program, and `match` takes it
apart by shape: `?name` binds one thing, `*body` binds the rest, `$` and `@`
put the pieces back. This little simplifier is the technique the x2c
compiler uses on itself.

Lisp worked this out in 1958. x2c kept the idea and dropped the second
syntax.
