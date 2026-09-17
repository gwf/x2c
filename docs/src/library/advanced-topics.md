# Advanced Topics

These chapters go past the language tour. The first three apply x2c to a
specialized task and explain the facilities and setup each one needs. The
last explains a guarantee the compiler makes about the code you already
write:

- [Automatic Differentiation](../guide/autodiff.md) uses the shipped autodiff
  library and compile-time macros to calculate derivatives.
- [Verifying Functions with C*](../guide/verification.md) uses the optional
  C* package and its external prover to check annotated functions.
- [Training and Inference with torch](../guide/torch.md) uses the optional
  Torch package and libtorch for machine learning.
- [The Region Model](../guide/regions.md) states the invariant behind the
  region warnings, what the check covers and does not, how it works, and how
  it compares with other languages.

The C* and Torch packages are separate from the standard library. For the
package mechanism itself, see [Packages](../guide/packages.md).
