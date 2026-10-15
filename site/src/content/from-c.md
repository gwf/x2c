---
title: Bring your C.
examples:
  - slug: rename
    caption: rename a C file and compile it
    files:
      - examples/from-c/points.x
    run: |
      mv points.c points.x
      x2c run points.x
    output: examples/expected/from-c-points.stdout
    note: "The C file compiles unchanged once it is named `points.x`. Use x2c features in it when you want them."
  - slug: header
    caption: call one x2c file from C
    files:
      - examples/from-c/words.x
      - examples/from-c/main.c
    run: |
      x2c build --output count main.c words.x
      ./count
    output: examples/expected/from-c-words.stdout
    note: "`x2c build` translates `words.x`, writes `words.h` with the C prototype for `count_words`, compiles `main.c`, and links the x2c runtime."
---

x2c is a superset of C. Rename a C file to `.x` and it compiles, or keep your C
and call one x2c file through the header it generates. Both programs are
checked [examples](https://github.com/gwf/x2c/tree/main/examples/from-c).
