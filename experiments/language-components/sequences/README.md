# Initialization and statement sequences

`managed.x` registers one policy for initialized `Tracked` values. Its macro
pattern describes a plain declaration, and its callback returns only the
quoted deferred cleanup. Client code writes an ordinary declaration:

```x2c
Tracked first = make(2), second = make(first.value + 1);
```

The callback does not traverse declarations, reconstruct AST lists, or query a
compiler SDK. The registration retains the complete macro pattern. Pointer
declarators and declarations of unrelated types do not match this policy.
This experiment deliberately manages a selected type; it does not implement
initializer-only `$auto` or ownership transfer on return. The factories in the
examples return compound literals directly.

`$after_initialization` is specifically a postlude registration. Its callback
receives one initialized declarator and returns statements to place immediately
after that initializer. It cannot replace the declaration or move its binding.
The ordinary declaration owner preserves source order and installs the returned
statements in the enclosing scope. Standalone block declarations participate;
`for` header declarations do not. Source and quoted loops follow this same
boundary. Uninitialized declarators contribute no postlude. Existing `$auto` initializers keep dev's managed-declaration path.

The compiler only splits a declaration when a callback contributes a postlude.
A split declaration with a shared inline type uses one local typedef, built by
a quotation and bound by the ordinary declaration binder. The original type
body is emitted once. Storage stays on the variable declarations, and each
original declarator keeps its pointer, array, and initializer syntax. This
reuses the existing declaration finishing pass; components have no shared-type
special cases.

`observed.x` explicitly registers an observer for every initialized local in
that translation unit. Its pattern uses the existing `DeclaratorRow` category.
It exercises qualified anonymous structs, enums, static storage, arrays, and
pointers through the actual postlude path. This is a translation-unit policy,
not a scoped declaration annotation.

`statements.x` demonstrates recursive meta execution over captured statement
sequences. Head/tail matching describes the sequence; the `$announcement`
macro recognizes each statement. Replacements are quotations. `recursive.x`
covers empty and mixed sequences. `stress.x` has 80 initialized declarators
and 128 recursively transformed statements. These are bounded examples, not
an unbounded-depth or throughput guarantee.

Run the optional `experiments/language-components/run.py` runner after building
the compiler. Each executable has a `.stdout` expectation and a `.sources`
sidecar for its included component modules.

The earlier `Code.after_bindings` implementation and its local Type/Code SDK
adapters are removed. Registration support in `after.x` uses the shared compiler registration owner.
Its postlude contract remains distinct from replacing an expression.
