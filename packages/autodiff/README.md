# Autodiff

Autodiff supplies dual-number families, forward and reverse derivative
decorators, checkpointed reverse derivatives, and a runtime tape for dynamic
computation graphs. It uses the x2c runtime and has no external dependency.

Build from the repository root:

```sh
make -C packages/autodiff build
builds/0/x2c build --package-dir packages examples/magic/autodiff.x
```

Import `"autodiff"` to use `$ad.dual`, `$ad.forward`, `$ad.reverse`,
`$ad.both`, and `$ad.checkpoint`. Import `"autodiff" with AdTape, AdNode`
for unqualified runtime type names. The archive and native meta module must
be built with the same compiler as the consumer.

See [the differentiation guide](../../docs/src/guide/autodiff.md) for running
examples and restrictions. Tape nodes belong to the active Scope; keep that
Scope alive while recording and differentiating. `backward` clears old
adjoints, seeds the result, and visits recorded operations in reverse.

The existing autodiff unit suite remains in `unittest/test-autodiff.x`;
compiler fixtures cover both the runtime and compile-time surface.
This relocation preserves the existing implementation and its license.
