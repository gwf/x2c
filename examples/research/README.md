# Nested module research example

This example belongs to the isolated nested-module research spike. Run it
with that worktree's experimental compiler:

```sh
builds/0/x2c build --output /tmp/nested-modules-example \
  examples/research/nested-modules.x
/tmp/nested-modules-example
```

The entry owns one Map object. Its members can read that object and inherit
the preceding module macro. The adjustment entry owns two nested members.
Only those members can call its module-visible `example_delta` helper.
The outer member calls the adjustment entry's public operation.

`stored_answer` remains static because only one file needs it. Public child
names contribute to the root's interface without a child name prefix.

The optional probe matrix is `unittest/probes/run-modules.py`. The example
is not enrolled in a recurring gate while the language remains experimental.
