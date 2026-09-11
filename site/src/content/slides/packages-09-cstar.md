---
slug: cstar
section: packages
tab: C*
title: Give a function a contract.
status: experimental
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/cstar/examples/abs.x
  - label: Package guide
    href: https://github.com/gwf/x2c/blob/main/packages/cstar/README.md
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
#include "x2c.x"
$(import "../src/cstar.xmacro")

$cstar.verify(
  "fact(x >= --2147483647i)",
  "fact(x >= 0i && __return == x || "
    "x < 0i && __return == --x)"
)
static int absolute(int x) {
  if (x >= 0) {
    return x;
  } else {
    return -x;
  }
}

int main(void) {
  printf("%d %d %d\n",
    absolute(-7), absolute(0), absolute(7)
  );
  return 0;
}
```

State an input bound and the relationship between the input and
returned value, then check the function with the C* symbolic executor.
The contract covers both branches: nonnegative inputs return unchanged;
negative inputs return their negation. The lower bound excludes the
integer whose negation would overflow.

The verifier checks the selected function under that precondition. The
caller must supply an input within the bound; the annotation adds no
runtime check or other code. C* remains an experimental package for
macOS arm64 with a closed-source verification backend.

Verifier output:

```text
absolute: verified
```
