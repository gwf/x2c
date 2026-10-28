> Status: done
> Published on 2026-10-28 through PR #614 at
> `fba02f6087b80c262ed6a40612f71571f448c711`.

# Deferred method template loses its name

## Reproduction and repair

A meta helper applies a Unit Macro value with a Type and
`x2c_ident("get")` as its Name argument. The macro declares
`int $type.$name($type value)`. Before repair, the generated C contains
`int(P _x2c_gensym_macro_v_0){` without a function name. Calling the method
instead reports that `P` has no method `get`.

The failure reproduces at `282f5bfb8181b73ebfc924d8b77ac00a861a1607`.
A direct invocation and a deferred String Name argument work on that same
compiler. The original [derive probe report](../derive-and-test.md#what-the-probe-established)
at `9aeeef265` is now narrowed to this reproduced identifier-valued Name
case. The original failing source was not retained, so its exact shape
cannot be confirmed.

`_method_member` in `src/parse/declarators.x` used the Name hole's raw value.
That leaves the member as `("x2c.ident" "get")`, while a method declarator
needs its member spelling. The repair uses `try_parse_macro_member`, the
existing operation that selects the Name hole's member projection.
`_member_spelling` already converts identifier values and renamed bindings
to their source spelling. Method installation and binding remain unchanged.

## Verification

The [regression fixture](../../unittest/compiler-fixtures/macro-deferred-method-member.x)
calls methods generated through a Macro value with an identifier Name, a
named template call with an identifier Name, and a literal owner. Direct
source and deferred String Name invocations remain controls. It prints
`41 42 43 44 45` and compiles without native warnings.

Focused checks:

- `make build-safe` and `make build` pass.
- `run.sh check --fixture macro-deferred-method-member` passes.
- Neighboring fixtures `macro-member-name-hole`, `macro-mixed-name-case`,
  `macro-type-hole-method-owner`, `local-unit-macro-collection`, and
  `macro-values` pass.

Here `run.sh` is `unittest/compiler-fixtures/run.sh`. The submitting parent
passed `make stage-2` on the combined tree and ran the regression with the
stage-two compiler; it also printed `41 42 43 44 45`. The shared integrator
owns final generated artifacts and the publication gate. No full gate ran
in this repair session.

## Plan review

The method member is already a Name hole. Its established member projection
owns conversion to the source spelling. Reusing that projection removes the
raw identifier marker before ordinary method installation consumes it.
The repair adds no representation, traversal, validator, or origin restriction.
The regression checks callable generated methods rather than an additional
rejection or diagnostic.
