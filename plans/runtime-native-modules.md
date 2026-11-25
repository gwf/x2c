# Runtime native modules: compile and load x2c in a running program

> Status: proposed 2026-11-24. Not approved, not started. It is the third
> of three linked plans, after [the x2cui Lisp surface](x2cui-lisp-surface.md)
> and [the builder](x2cui-builder.md). It stands alone: nothing here needs
> x2cui.

## Result

An ordinary x2c program, built to allow it, compiles one `.x` file while it
runs, loads the result into its own process, and calls the new functions.

```c
NativeModule module = NativeModule.build("handlers.x");
Func total = module["order_total"];
```

Loading the functions into a Lisp session makes them callable from a UI
tree's handlers. With the two x2cui plans, a saved UI file can carry x2c
source next to its tree, and the application gains compiled behavior when
it opens the file.

## Current facts

- Nothing that loads an object was ever in `lib/`. What was removed on
  2026-08-05 was `Func.load`, about 30 lines that looked up a symbol
  already linked into the process and called it through libffi. `-rdynamic`
  was removed with it, and `unittest/probes/run-preprocessor-boundary.sh`
  asserts it stays absent from ordinary builds.
- The capability exists in the compiler. `x2c build --kind meta-module` is
  a documented build kind (`docs/src/reference/cli.md`). It writes a native
  module that leaves the x2c runtime unresolved and binds to the loading
  process's copy. On macOS the link is `-bundle -bundle_loader <loader>`;
  elsewhere it is `-shared -Wl,-Bsymbolic-functions` (`src/toolchain.x`).
- A module exports three things (`src/meta-group/emission.x`): a stamp
  naming the compiler that built it, `x2c_module_reset`, and
  `x2c_module_targets`, a Map from each function's name to a `Func`.
- The compiler loads a module with `dlopen(RTLD_NOW | RTLD_LOCAL)` after
  checking the stamp, reads the Map, and never unloads it, because the
  `Func` values point at the module's code (`src/meta-native/modules.x`).
- A module today contains only functions declared `meta native`, and only
  the compiler and the commands that link the compiler load one.
- A loading process must contain the whole runtime and export its symbols.
  The compiler and commands link with `-force_load` or `--whole-archive
  -rdynamic`. A program from `x2c build` links only the runtime members it
  uses and exports nothing.
- An install contains `bin/x2c`, `lib/libx2c.a`, the `lib/*.x` sources and
  headers, and a toolchain file naming `cc`. It does not contain the
  compiler as a library.
- Class and protocol descriptor registration becomes read-only after the
  first successful `Thread.start` (`lib/thread.x`, `lib/var/classes.x`). A
  later registration raises `<bad-state>`.
- The REPL rejects redefinition of a function and reloads by starting a new
  worker process. Nothing in the repository replaces code in place.
- Native modules are disabled on Windows and Cygwin. The wasm target has no
  `dlopen`.

## Design

### A host opts in at build time

`x2c build --export-runtime` links the whole runtime into the program and
exports its symbols, with the flags `builds/stage.mk` already uses for the
compiler. A program built without the option cannot load a module, and
`NativeModule.load` raises an Error that names the option. Ordinary builds
keep their size and the existing probe keeps passing.

### A module holds ordinary functions

`x2c build --kind module` builds the same file format as `meta-module`,
with the same stamp and the same `x2c_module_targets` entry. Its Map holds
every public function the named sources define, each as a `Func` with the
signature `Code.native_signature` reports. This is the signature source
`$lisp.bind` already uses, so a loaded function binds into a Lisp session
with `Lisp.bind` and no further description.

The existing `meta-module` kind and its `meta native` rule do not change.

### The runtime loader

A new runtime unit, `lib/native-module.x`, holds what
`src/meta-native/modules.x` does today to open a file: check the stamp,
`dlopen` with `RTLD_LOCAL`, read `x2c_module_targets`. The compiler then
calls the runtime unit, so one loader exists.

- `NativeModule.load(path)` loads a built module and returns it.
- `NativeModule.build(source)` runs `bin/x2c build --kind module` as a
  child process with `lib/process.x`, writes the output under a cache
  directory named by the hash of the source text and the compiler stamp,
  and loads it. An unchanged source loads the cached file without
  compiling.
- `module[name]` returns the `Func` for a function, and `module.names()`
  lists them.

The stamp check is the compatibility rule: a module loads only into a
program whose runtime was built by the same compiler. A mismatch raises an
Error before any module code runs.

The child process finds `bin/x2c` and the toolchain through the same
install lookup the `x2c` driver uses. On macOS the module's link needs the
path of the loading executable, which the runtime already knows.

### Conflicts and reloading

`RTLD_LOCAL` keeps a module's symbols out of the process's global scope,
and each module's calls to its own functions bind inside it. Two modules
that define the same function name therefore never collide at link level.
The only place names meet is the caller's own Map or Lisp session.

A changed source has a new hash, so it builds a new file and loads beside
the old one. The caller decides which `Func` a name means by binding it
again. Old code stays loaded for the life of the process, because live
`Func` values and closures point into it. Compiled code that called the old
function directly keeps calling the old function. Callers that look a
function up by name, as Lisp handlers do, see the new one.

This is the whole policy: load, never unload, rebind names. It needs no
indirection tables and no migration of state.

### What a loaded module may contain

Functions, including ones that use existing classes and protocols. A
module that defines a new class or protocol registers its descriptor when
it loads. That succeeds before the program starts its first thread and
raises `<bad-state>` afterward, as registration does today. The first
version accepts that limit and documents it. Lifting it means making the
descriptor registry safe to change while threads run, which is a separate
design.

A module's `static` values belong to that module. A reload starts them
fresh; the old module keeps its own.

### Isolation

The first version loads into the host's process, Scope rules, and
threads. A caller that wants a memory boundary runs loaded functions inside
a `Context`, which already gives a bounded Scope and separate Error state.
That gives no protection against a crash in loaded code.

Crash isolation means running the module in a worker process, as the REPL
does with its supervisor and datum-framed pipes. It is not in this plan. It
becomes worth planning when files from other people are loaded.

## Scope

| Piece | Where | Estimate |
| --- | --- | --- |
| `--export-runtime` link option | `src/toolchain.x`, driver | under 50 lines |
| `--kind module` targets for public functions | `src/meta-group/emission.x` and the driver | 100-200 lines |
| `lib/native-module.x`, moved from the compiler | `lib/`, `src/meta-native/modules.x` | about 150 lines, about 60 moved |
| Build cache and child-process compile | `lib/native-module.x` | about 100 lines |
| Book section, example, tests | `docs/`, `examples/`, `unittest/` | one example, one suite |

The estimates are not measurements. Out of scope: Windows, wasm, unloading,
in-place replacement of functions or types, late class registration, worker
process isolation, and loading into a program that uses macOS hardened
runtime, which is unverified.

## Compatibility

`lib/native-module.x` is a new public runtime module and uses `dlopen`,
which the original plan excluded from the runtime. The runtime gains a
dependency on `-ldl` on Linux for programs that use the module. Programs
that do not opt in are unchanged. The bootstrap needs one refresh, because
the compiler starts calling the runtime loader.

A program that compiles at run time requires an x2c install and a C
compiler on the machine where it runs.

## Validation

- A test builds a host with `--export-runtime`, builds a module from one
  file, loads it, and calls a function through its `Func`.
- A test changes the source, builds again, and checks that a name lookup
  returns the new behavior while a kept `Func` returns the old.
- A test loads a module into a host built without the option and checks the
  Error.
- A test loads a module built by a different compiler stamp and checks the
  Error.
- One measurement: elapsed time from `NativeModule.build` on a 50-line
  source to the first call, cold and cached, on macOS arm64.

## Questions for Gary

1. Accept `dlopen` in the runtime behind an opt-in build option?
2. Accept "functions only after the first thread starts" for the first
   version?
3. Accept the names `--export-runtime`, `--kind module`, and
   `NativeModule`?

## Plan review

- **Established facts.** The stamp establishes that the module and host
  share one compiler and runtime layout; the loader checks it once and
  nothing downstream checks types or signatures again. The compiler
  establishes each function's signature in the targets Map.
- **Reuse and new mechanisms.** The module format, link shape, stamp, and
  targets Map are reused unchanged. The loader moves from the compiler to
  the runtime, so the compiler's copy is deleted. New: the build option,
  because ordinary programs do not carry or export the whole runtime; the
  `module` kind, because `meta-module` exports only `meta native`
  functions; and a content-hash cache in the runtime. The compiler's
  staging path names its own modules the same way
  (`src/meta-group/staging.x`), but that code is compiler-side; whether
  the two can share one owner is settled during implementation.
- **Idiom.** A module is a Map of `Func` values, which x2c programs and the
  Lisp runtime already consume. There is no plugin registry, interface
  description language, or symbol versioning.
- **Validators and diagnostics.** Two Errors. A missing `--export-runtime`
  would otherwise surface as an unresolved-symbol failure from the system
  loader, or on macOS as a link failure with no hint. A stamp mismatch
  would otherwise run code against a different runtime layout and corrupt
  memory. Both already exist in the compiler's loader in some form.
