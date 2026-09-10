---
title: Packages
---

**Packages give libraries their own namespaces.** Each package keeps its
x2c interface separate, so third-party libraries can be used together
without their names colliding. Build a package once, then import it by
name, with an alias if you like.

Where needed, shims and adapters turn a C API into idiomatic x2c types,
methods, and operations. The native API remains available. Packages can
also provide Lisp bindings and decorators that extend how you use a
library or express an idea.

The examples below show one program from each package: draw a chart, build
a terminal application, query data, parse text, fetch pages, run processes,
calculate rankings, train a model, or verify a function's contract. Each
pairs code with its result and links to the complete source.
