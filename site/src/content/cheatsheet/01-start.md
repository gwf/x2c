---
title: Any C file is already an x2c file
group: Start
---

```x2c
// hello.x: ordinary C, plus one String and one interpolation.
#include <stdio.h>

int main(int argc, char **argv) {
  String name = argc > 1 ? argv[1] : "world";
  puts(%"Hello, $name!");
  return 0;
}
```

```sh
x2c run hello.x -- Ada       # build and run; -- starts the program's args
x2c build hello.x -o hello   # keep the executable
x2c translate hello.x        # emit C and a header for your own build
```

- `#include "other.x"` makes another unit's public declarations visible;
  `import "pkg" as p;` binds a package alias.
- Declarations are public unless `static`. A `.x` unit becomes one `.c`
  and one `.h`.
- A first line of `#!/usr/bin/env -S x2c script` makes a script: its
  file-scope statements are the program.
