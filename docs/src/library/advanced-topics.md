# Advanced Topics

The first three chapters apply x2c to one specialized task each, with the
setup each one needs. The fourth states the invariant behind the region
warnings:

- [Automatic Differentiation](../guide/autodiff.md) uses the optional autodiff
  package and its compile-time macros to calculate derivatives.
- [Training and Inference with torch](../guide/torch.md) uses the optional
  Torch package and libtorch for machine learning.
- [Building Interfaces with x2cui](../guide/x2cui.md) uses the optional
  x2cui package and CUI to draw windows and user interfaces.
- [The Region Model](../guide/regions.md) states the invariant behind the
  region warnings and the limits of the check.

The autodiff, Torch, and x2cui packages are separate from the standard
library. For the package mechanism itself, see
[Packages](../guide/packages.md).
