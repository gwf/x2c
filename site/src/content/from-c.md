---
title: Start from C
---

Most C files are already x2c files. Rename one from `.c` to `.x` and it
compiles and runs as before. The exceptions today are a few literal forms,
such as `L'a'`, `u8"..."`, and `'ab'`, and code whose syntax only appears
after macro expansion.

From there, adopt x2c one change at a time. The steps below start with a
small C program and change a few lines at each step, marked in the code. Every
step is a complete program that prints the same result. The last step goes
the other way: a C `main` calls the x2c code through the header x2c writes.
