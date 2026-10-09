# Indexed operations and delegation

This experiment registers parsed patterns through the shared `$rewrite`
decorator. The examples use ordinary source operations, with no constructor
wrappers or separate forwarding API.

`component.x` registers Array and Map patterns for reads, assignment, `+=`,
prefix `++`, and postfix `++`. Each callback matches the same source macro
and returns a quoted call to the existing runtime storage operation. The
runtime retains update conversion, stored numeric tags, and failure behavior.
The compiler retains getter admission and the typed containing expression.
A replacement with a different result type after supported conversion is
rejected; return an explicitly converted expression when appropriate.
These callbacks do not implement a new update algorithm.

`main.x` checks values and stored u8 tags, one evaluation each of the receiver,
key, and right operand, failed conversion without mutation, and Map insertion.
Its missing-key subtraction is explicitly a kernel control because this
component registers no subtraction pattern.

`probe.x` proves that each interception point executes its registered callback.
An Indexed getter normally returns 7. Five callbacks instead return distinct
values 101 through 105. An ordinary C array remains unaffected. This test keeps
activation instrumentation out of the component.

`delegation.x` registers a member-call pattern whose receiver has type Wrapper.
A missing Wrapper method is rewritten through `.part`; the kernel resolves the
resulting call and adapts a reference receiver. The test checks a read, mutable
forwarding, a direct method that wins before fallback, one evaluation of the
receiver, and an unrelated type's ordinary method. Recursive field search and
ambiguous delegation policy are not implemented here.

Run the optional examples with:

```sh
python3 experiments/language-components/run.py
```

The runner compares stdout and exit status and retains build logs under `/tmp`.
