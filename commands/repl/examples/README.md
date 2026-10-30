# Explore a C program in the REPL

This demo loads the existing [C N-body benchmark][source] unchanged. It uses
the benchmark's static functions and `bodies` array directly.

[source]: ../../../examples/shootout/benchmarks/nbody/main.c

From the repository root, build the compiler and commands, then run the demo:

```sh
make commands
./x2c repl < commands/repl/examples/nbody.repl
```

The [input script](nbody.repl) runs one simulation step and exits. The REPL
prints discovery results, source, object fields, and energy values. To try
commands yourself, start `./x2c repl` and follow these steps instead.

## Discover the program

```text
:load "examples/shootout/benchmarks/nbody/main.c"
:symbols --kind function --file "examples/shootout/benchmarks/nbody/main.c"
:symbols bodies
```

The function list includes `advance`, `energy`, and `offset_momentum`, even
though the C file declares them `static`. The global list shows `Body bodies[5]`.
Loading starts a fresh session.

## Read the source and data type

```text
:source offset_momentum
:members Body
```

`:source` shows the original static function definition. `:members` lists
position, velocity, and mass fields, plus functions that accept a `Body *`.
The function calls keep their ordinary C syntax.

## Call functions and inspect their effects

```text
:inspect bodies[0]
offset_momentum(BODY_COUNT, bodies);
:inspect bodies[0]
printf("%.9f\n", energy(BODY_COUNT, bodies));
:inspect bodies[1]
advance(BODY_COUNT, bodies, 0.01);
:inspect bodies[1]
printf("%.9f\n", energy(BODY_COUNT, bodies));
```

`bodies[0]` is the Sun. Its velocity starts at zero; `offset_momentum` sets it
to balance the system's momentum. `bodies[1]` is Jupiter. After `advance`, its
x coordinate changes from about `4.841431` to `4.847340`, along with its other
position and velocity fields. Both calls operate on the same static array.

The energy values before and after the step are:

```text
-0.169075164
-0.169074954
```

`printf` also returns `13`, the number of characters written. Enter `:quit`
to exit. Enter `:reload` to rebuild the original program and start fresh.
