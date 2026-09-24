# Meta sequencing: classes, extensions, protocols, certification

> Status: active - order decided by Gary on 2026-09-24. No step has
> started. Each step needs its own design review before implementation;
> this plan records the order and the dependencies that set it.

The remaining meta work spans four threads from
[meta follow-ups](meta-followups.md): Var class capacity, native
extensions (track G), meta-capable protocols (track E), and whole-project
lifetime certification (track F phase 8). They are not independent. This
plan fixes the order so that no step builds on machinery a later step
replaces.

## Order

1. **Class registration and capacity.**
2. **Native extensions and packages.**
3. **Meta-capable protocols beyond Iter.**
4. **Whole-project lifetime certification.**

### 1. Class registration and capacity

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

Track E delivered marked adoptions for Iter. Buffer, Array, Map and Var
follow. Exposing them may require helper types visible to meta code, and
each boxed helper type takes a class row, so this follows step 1. Packages
that adopt protocols for meta use follow step 2.

### 4. Whole-project lifetime certification

Track F phase 8: opt-in whole-project certification that treats unknown
calls as unproved, the effect inventory, and File and Job finalizers. It
goes last because steps 1-3 change what runs at compile time and across
module boundaries, which would invalidate an earlier certification.

## Not in this sequence

The smaller track C items stay in [meta follow-ups](meta-followups.md):
an MSYS2 run of the LLP64 `size_t` mapping, `off_t` and `time_t` widths,
and enum values across translation units.
