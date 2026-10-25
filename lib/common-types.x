/*  common-types.x -- the types the compiler prelude declares first

    Copyright (c) 2026 Gary William Flake

    `common.x` builds on these types, and `etc/compiler-prelude.x` declares
    them before its meta prototypes, which take and return them.
*/

#pragma once

/** Eight-byte tagged runtime value for immediate scalars and encoded handles.
    Pointer-bearing values follow the ownership rules of their concrete type;
    raw `Null` is all zero bits and `void` is all one bits.
*/
typedef union Var {
  unsigned long u64;
  double f64, void *p64;
} Var;

/** Immutable canonical cons chain; NULL is `nil`.
    Its lifetime follows its owning `List` pool, which may be an ancestor.
*/
typedef struct List *List;

/** A native mutex allocated in the active `Scope` without recursive locking.
    Its `Scope` and handle must outlive every user and waiter. Destroy it only
    while unlocked, and do not use the handle or its storage after that.
*/
typedef struct Mutex *Mutex;
