# X2C Development Reference

This page keeps implementation facts that are useful but too detailed for the
quick start. The root `AGENTS.md` owns workflow, validation, and publication;
project skills own task execution.

## Authoritative and generated files

- Change compiler sources under `src/` and runtime sources under `lib/`.
- Never hand-edit generated C/H under `bootstrap/` or numbered `builds/`.
- Never hand-edit `lib/x2c.x`; `lib/Makefile` generates it.
- Use `builds/0/x2c` for current behavior. `bin/x2c` remains the bootstrap
  compiler unless stage 0 was intentionally installed.
- Keep temporary output in `/tmp` or `unittest/build/` and failure logs under
  `debug/`.

Generated C compilation records header dependencies in `.d` files. Staged
compiler builds and projects using `etc/x2c.mk` include them, so public
generated-header changes rebuild their consumers. A clean build is a recovery
and diagnostic tool, not a substitute for dependency tracking.

## Runtime representations

Lists and non-empty Strings are canonical immutable values; empty List/String
uses native zero. Arrays and Maps are mutable allocated objects. Scope owns
allocation lifetime. A raw null Array/Map pointer may mark internal absence or
pending initialization, but it is not an empty container value. Explicit
resource release remains valid where the public API supports it. Do not copy a
rule from one of these representations to another.

## Delete before generating

First look for a current language form or existing operation that removes
repeated source. Direct receiver calls, supported conversions, protocol
defaults, `SymbolSet`, and non-returning allocation failure can delete code
without adding machinery. Do not retain a wrapper, forwarding protocol,
compatibility alias, or post-allocation branch after its only job disappears.

Use a macro, decorator, or compile-time Lisp table only when genuinely uniform
source remains. The definition, data, helpers, and invocations should be
shorter or easier to verify than the direct code. Keep policy-bearing names and
types visible. Good candidates include mechanical function families, test
registration, and facts duplicated across enums, tables, switches, and
declarations.

For a hot compiler path, retain an idiom conversion only with fewer source
lines, a paired timing whose confidence interval is below parity, and
byte-identical generated output. A readability improvement off the hot path
needs no timing and must not claim a performance result. Record reusable macro
evidence in `agents/adapters-macros-decorators.md`.

A rejected prototype describes that implementation, not a permanent ban.
Record the source shape, compiler capability, diagnostics, generated C, size,
and performance that decided it so a later compiler change can be evaluated
against facts.

## Preprocessing

x2c does not expand C preprocessor macros. Directives pass to generated C;
symbol collection stores macro identifiers unexpanded in declaration
positions. Therefore:

- Preprocessing must not change top-level declaration structure. Do not wrap
  declarations in `#if` or expand macros into declarations.
- Object-like constant `#define`s remain valid where C requires an integer
  constant expression. `static const` cannot replace them in every context,
  and 64-bit constants such as `VAR_NULL_BITS` are not portable enumerators.
- Quote-includes must form an acyclic graph resolved from the including file,
  then `.`, `src/`, `lib/`, the `-I` chain, and `include/`.
- The compiler never reads system headers. Declare compiler-visible types in
  `.x` source or the runtime library.

File-local `static` globals do not enter `etc/symbols.xlisp`; only their own
translation unit collects them.

## Documentation evidence

Use accepted behavior, executable tests, current source and Makefiles, then
generated artifacts as evidence before explanatory prose. The module catalog
is generated from non-static definitions:

```sh
make doc-generate
make doc-check
```

`make doc-generate` rewrites `agents/x2c-module-catalog.md`; `make doc-check`
is read-only. Compile complete examples with `builds/0/x2c`. Mark fragments as
illustrative or pseudo instead of presenting them as standalone programs.

## Performance work

Run the relevant focused benchmark shown by `make help`; `make bm-all` runs the
current runtime set. Select `make config-debug` or `make config-optimize`,
rebuild, and record the mode with results.

Full LTO is an opt-in experiment:

```sh
make clean
make BUILD_LTO=1 build
```

External programs linked with the resulting `libx2c.a` must also use the
reported `BUILD_LDFLAGS` (`-rdynamic -pthread -flto`) on their final link.
`-rdynamic` preserves runtime-loaded function symbols after LTO
internalization. Rebuild after changing the option; ordinary builds keep
`BUILD_LTO=0`.

## Further references

- `agents/x2c-philosophy.md` - current design facts and their evidence.
- `agents/x2c-coding-style-guide.md` - mechanical source style.
- `agents/x2c-code-organization-guide.md` - where code belongs.
- `agents/x2c-debugging-guide.md` - phase dumps and miscompile isolation.
- `docs/src/internals/implementation-map.md` - feature routing.
- `plans/README.md` - durable plan format and archival rules.
