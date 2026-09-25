# Meta sequencing: classes, extensions, protocols, lifetime proof

> Status: active - steps 1-3 landed on `dev` 2026-09-24 (last commit
> `7a371fa6`); step 4 is implemented here as an optional selected-root audit.

The remaining meta work spans four threads from
[meta follow-ups](meta-followups.md): Var class capacity, native
extensions (track G), meta-capable protocols (track E), and an optional
lifetime proof (track F phase 8). They are not independent. This
plan fixes the order so that no step builds on machinery a later step
replaces.

## Order

1. **Class registration and capacity.**
2. **Native extensions and packages.**
3. **Meta-capable protocols beyond Iter.**
4. **Conditional lifetime proof.**

### 1. Class registration and capacity

Designed in [class registration](archive/class-registration.md).

Two separate problems, designed together:

- **Lazy registration.** Today each class reserves its Var row in its file
  initializer, so linking a runtime object spends a row whether or not a
  value of that class is ever boxed. Registering on first box would make
  linking free of rows. Registration currently freezes at the first
  successful `Thread.start` (`Var.register_object_tag` in `lib/var.x`), so
  first-box registration after that point needs a thread-safe registry or
  another rule.
- **Capacity.** The class number occupies five bits of the Var encoding
  (`lib/var.x`, the tag layout table), so there are 32 rows per family and
  the 32nd registration aborts at startup. Lazy registration delays hitting
  that limit; it does not remove it. More classes needs a representation
  change, such as keeping the class in the object rather than the tag.

Decide first whether capacity is needed now or lazy registration is enough
for steps 2 and 3. Several past changes worked around the row budget; the
design should list them.

### 2. Native extensions and packages

Designed in [package meta modules](archive/package-meta-modules.md).

Track G delivered loadable meta modules with a hash stamp and a
name-to-`Func` target Map. Extend it so a package declares its role:

- needed at compile time: built as a meta module and loaded for
  translation, build and REPL use;
- needed only at link time: linked statically or dynamically as today.

Importing a package then loads its compile-time part when the package has
one. The route that links an extension into the compiler (track G
follow-up) uses the same target Map registration. This depends on step 1:
a module that can call the whole runtime needs the whole runtime linked,
which today costs 13 more rows at startup.

### 3. Meta-capable protocols beyond Iter

Designed in
[meta protocols beyond Iter](archive/meta-protocols-beyond-iter.md).
Only its fourth delivery, the typed containers, depends on step 1;
deliveries 1-3 can start earlier.

Track E delivered marked adoptions for Iter. Buffer, Array, Map and Var
follow. Exposing them may require helper types visible to meta code, and
each boxed helper type takes a class row, so this follows step 1. Packages
that adopt protocols for meta use follow step 2.

### 4. Conditional lifetime proof

The optional `x2c-graph certify` audit starts from selected functions and
follows their reachable project calls. It combines the compiler's region
effects with explicit, reported native assumptions. A result distinguishes
proved scoped lifetime behavior, established violations, and paths whose
effects remain outside the proof. Ownership passed back to a caller appears
as an obligation. The audit stays outside ordinary compilation; the
per-definition check still runs before meta code executes. File and Job
finalizers were delivered in the narrower meta lifetime work. This step
follows the first three because they changed compile-time and module-boundary
reachability.

The first case study selected `main` over hand-authored `src/*.x` and
`lib/*.x` (excluding generated `lib/x2c.x`). It returned `incomplete`: no
root-wide proof, no reported violation, no native assumptions, and more than
19,000 obstacles. The report is retained locally in
`debug/certify-compiler-final.out`.

## Not in this sequence

The smaller track C items stay in [meta follow-ups](meta-followups.md):
an MSYS2 run of the LLP64 `size_t` mapping, `off_t` and `time_t` widths,
and enum values across translation units.

## Follow-ups from steps 1-3

- Boxing an overflow heap class (past the 30 direct rows) costs about
  46 ns: a global lock plus a Map lookup. Make it lock-free if the
  compiler's own heap classes pass 30 on hot paths.
- The region check misses an escape through a chained returning call,
  such as `return Buffer.write(&local, "a").newline();`. A single call or
  a named intermediate is caught. The gap predates step 3.
- The container generators cannot emit `meta` prototypes, because a
  `meta` prototype inside a `macro Unit` does not parse.
- A package with a native dependency cannot be linked into the compiler
  with `--extension`; its native flags do not reach the compiler build.
