---
slug: blis
section: packages
tab: BLIS
title: Rank pages with a little linear algebra.
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "blis" with Blis, BlisObject;

BlisObject rank = BlisObject.copy_vector(
  %(0.2 0.2 0.2 0.2 0.2), BLIS_DOUBLE
);
defer rank.free();

// links is the matrix; ones is a vector of ones.
double shift = 1.0;
int round = 0;
for (; shift > 1e-15 && round < 100; round++) {
  Scope.retain();
  {
    defer Scope.release();
    BlisObject next = links @ rank;
    next = next.scale(1.0 / next.dotv(ones));
    shift = (next - rank).normfv();
    rank.copy_from(next);
  }
}
printf("converged after %d rounds, shift %.1e\n",
       round, shift);
```

Multiply a link matrix by a rank vector, normalize the scores, and
repeat until they converge. `@` multiplies the matrix and vector;
ordinary operators handle the remaining arithmetic. Each round copies
the new scores into the retained rank vector and releases its temporary
values.

The complete example builds a five-page graph and starts every page
with equal rank. After 53 rounds, `index` leads. The blog has no incoming
links, so its score falls to zero.

Full example output:

```text
converged after 53 rounds, shift 7.9e-16
  index      0.3333
  guide      0.3056
  reference  0.2778
  download   0.0833
  blog       0.0000
```

[Full example](https://github.com/gwf/x2c/blob/main/packages/blis/examples/page-rank.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/blis/README.md)
