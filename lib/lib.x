/*  lib.x -- disjoint sets with union-find

    Copyright (c) 2025 Gary William Flake

    This module is aggregated into the x2c.x runtime and implicitly
    available through the prelude.
    DisjointSet owns a mutable union-find structure behind a pointer typedef;
    callers release it with DisjointSet.free.
*/

#include "x2c.x"

/** Owns a mutable union-find forest over integer elements.

    `DisjointSet.new` creates the only valid state. The structure and its two
    arrays are `Scope`-owned; `DisjointSet.free` releases them early and
    invalidates every alias.
*/
typedef struct DisjointSet {
  int *parent, *size, length, ncmpnts;
} *DisjointSet;

/** Creates a union-find over elements `0` through `n - 1`.
    `n` must be nonnegative. The result belongs to the active `Scope` and
    starts
    with each element in its own component.

    Raises: `<size-limit>` or `<alloc-fail>` while allocating the structure or
    its arrays.
*/
DisjointSet DisjointSet.new(int n) {
  DisjointSet set = Scope.malloc(sizeof(struct DisjointSet));
  set.parent = Scope.malloc(sizeof(int) * n);
  set.size = Scope.malloc(sizeof(int) * n);
  set.length = n;
  set.ncmpnts = n;
  for (int i = 0; i < n; i++) {
    set.parent[i] = i;
    set.size[i] = 1;
  }
  return set;
}

/** Releases a live set and its arrays, invalidating every alias. */
void DisjointSet.free(DisjointSet set) {
  Scope.free(set.parent);
  Scope.free(set.size);
  Scope.free(set);
}

/** Returns the representative of `x` and compresses its traversed path.
    `set` must be live and `x` must be between zero and `set.length - 1`.
*/
int DisjointSet.find(DisjointSet set, int x) {
  int p = set.parent[x];
  if (p == x) return x;
  while (p != set.parent[p]) {
    set.parent[x] = set.parent[p];
    x = p;
    p = set.parent[p];
  }
  return p;
}

/** Merges the components containing `a` and `b` by size.
    `set` must be live and both elements must be in range. The larger
    component's root wins unless the sizes tie, when the root of `a` wins.
    Merging an existing component is a no-op.
*/
void DisjointSet.union(DisjointSet set, int a, int b) {
  int a_root = set.find(a), b_root = set.find(b);
  if (a_root == b_root) return;
  if (set.size[a_root] < set.size[b_root]) {
    int t = a_root; a_root = b_root; b_root = t;
  }
  set.parent[b_root] = a_root;
  set.size[a_root] += set.size[b_root];
  set.ncmpnts--;
}

/** Returns canonical `(size representative)` rows for the current roots.
    Rows are ordered by `Var.compare`, ascending first by size and then by
    representative. Returned `List`s live through their owning `List` pool,
    which may be an ancestor of the active pool.

    Raises: `<size-limit>` or `<alloc-fail>` while collecting or sorting rows.
*/
List DisjointSet.sizes(DisjointSet set) {
  Array sizes = %[];
  for (int i = 0, n = set.length; i < n; i++)
    if (set.parent[i] == i) sizes.push(%(${set.size[i]} $i));
  List result = sizes.sort();
  sizes.free();
  return result;
}

/** Returns the live set's current number of disjoint components. */
int DisjointSet.num_components(DisjointSet set) => set.ncmpnts;
