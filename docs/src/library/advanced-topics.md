# Advanced Topics

The first three chapters apply x2c to one specialized task each, with the
setup each one needs. The fourth states the invariant behind the region
warnings:

- [Automatic Differentiation](../guide/autodiff.md) uses the optional autodiff
  package and its compile-time macros to calculate derivatives.
- [Verifying Functions with C*](../guide/verification.md) uses the optional
  C* package and its external prover to check annotated functions.
- [Training and Inference with torch](../guide/torch.md) uses the optional
  Torch package and libtorch for machine learning.
- [The Region Model](../guide/regions.md) states the invariant behind the
  region warnings and the limits of the check.

The C* and Torch packages are separate from the standard library. For the
package mechanism itself, see [Packages](../guide/packages.md).
