# Advanced Topics

These chapters apply x2c to specialized tasks. Each explains the facilities
it uses and the setup it requires:

- [Automatic Differentiation](../guide/autodiff.md) uses the shipped autodiff
  library and compile-time macros to calculate derivatives.
- [Verifying Functions with C*](../guide/verification.md) uses the optional
  C* package and its external prover to check annotated functions.
- [Training and Inference with torch](../guide/torch.md) uses the optional
  Torch package and libtorch for machine learning.

The C* and Torch packages are separate from the standard library. For the
package mechanism itself, see [Packages](../guide/packages.md).
