# Everyday commands

These commands are the landing page's tooling slide. They assume an
installed compiler on `PATH`; from a checkout, use `./x2c`.

```sh
# Build and run in one step; a warm run reuses the executable.
x2c run hello.x

# Start a project that already builds and runs.
x2c new demo && cd demo && x2c run

# Tests are functions marked $test(); the runner finds and runs them.
x2c test

# A REPL that compiles your functions to native code as you type.
x2c repl
x2c> int total = 10;
x2c> int plus(int x) { return total + x; }
x2c> plus(3);
=> 13

# A failure names your line, not a line in the generated C.
x2c run oops.x
x2c: uncaught <no-convert> in main (oops.x:3): target i32, ...

# Diagnostics, hover, completion, references, and rename for editors.
x2c lsp
```
