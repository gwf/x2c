# Reading the runtime

This directory contains the x2c runtime: the types, collections, text,
files, errors, threads, and embedded Lisp that compiled programs call. It is
written in x2c, and the compiler in [src/](../src/README.md) is built on it.

A self-contained module is one `.x` file at this level, such as
[channel.x](channel.x). A split module keeps its entry and members in a
directory, such as [map/map.x](map/map.x). [x2c.x](x2c.x) includes the runtime
modules; `make build` regenerates it, so do not edit it by hand.

The [standard library overview](../docs/src/library/overview.md) explains the
runtime by task, and the [module pages](../docs/src/library/modules/index.md)
list each module's operations. The
[implementation map](../docs/src/internals/implementation-map.md) connects
language features to the runtime and compiler modules that implement them.
