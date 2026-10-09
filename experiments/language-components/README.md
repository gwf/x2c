# Language component examples

The current work is defined by [the foundation plan](../../plans/language-components-foundation.md).
These optional examples use ordinary decorators, reusable macro patterns,
quotations, and Code/Type methods. Run them with:

```sh
python3 experiments/language-components/run.py
```

| Example | What it establishes |
| --- | --- |
| [combined.x](combined.x) | Several components coexist in one client. |
| [access/component.x](access/component.x) | Collection read, store, and update selection; evaluation count and failed-update behavior. |
| [sequences/managed.x](sequences/managed.x) | Cleanup after initialization of a selected type; comma declarations, earlier-local visibility, and reverse cleanup. |
| [dispatch/components.x](dispatch/components.x) | Typed addition and switch replacement, with ordinary fallback. |
| [access/delegation.x](access/delegation.x) | One wrapper forwards missing member calls; direct-method precedence and receiver evaluation once. |
| [types/values.x](types/values.x) | Shared Type algorithms work for runtime and compile-time clients. |
| [builtin/precedence.x](builtin/precedence.x) | User rules precede builtin collection rules. |

`$rewrite` derives a dispatch category from the macro pattern, retains a
prepared matcher, and binds the first accepted replacement through the ordinary
compiler. Returning void, null, or the original input itself declines. Only the
active rule is suppressed while binding its replacement; independent rules can
compose. Each compiler orders its own rules; the rules its prelude ships are
prepared once per process and shared.

The [post-initialization boundary](sequences/README.md) keeps declarations,
bindings, and initialization in the compiler. A component contributes following
statements. It is not a complete replacement for initializer-only `$auto`.
The delegation example is also not a replacement for recursive lookup,
ambiguity handling, or completion. Those features retain dev's implementations.

`src/component-access.x` is the first active builtin migration. Array/Map
mutations use the same authoring facilities as these examples. Native array
behavior and lifecycle ownership stay in the compiler.

The [builtin report](builtin/README.md) and
[archived experiment plan](../../plans/archive/language-components-experiments.md)
preserve earlier measurements and limitations. Their results apply to the named
revisions, not automatically to this foundation. No optional runner was added
to a recurring gate.
