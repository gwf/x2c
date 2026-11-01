# Deferred async performance evidence

> Status: reference - normal benchmark reruns remain deferred by instruction.
> Recorded 2026-10-31 after dev publication at `255de641f`.
> The [execution-stack archive](../archive/async-execution-stacks.md) owns the
> delivered design and detailed evidence. This record owns its deferred work.

## Resume condition and baseline

Resume normal benchmark work only when Gary requests it. The saved shootout
measurements imported with other dev changes do not validate async overhead.
Use the existing performance workflow and named comparable baselines; this
closeout adds no benchmark or recurring requirement.

Keep these accepted costs visible when choosing a future workload:

- One million macOS arm64 buffered Channel pairs measured 36.957 ns per pair
  before versus 39.344 ns after; instruction counts were 1,030.876 versus
  1,109.348 million. These are historical focused measurements.
- Each task reserves 8 MiB usable stack by default. Sixty-five jobs reserve
  520 MiB before guards; virtual reservation is distinct from resident memory.
- Repeating 1,000 batches of 1,025 jobs retained 30.984 MiB RSS after mapped
  job arrays, versus 38.188 MiB before. Live allocations did not grow across
  batches. Those measurements do not establish a leak or zero retention.

The delivered four-target evidence used Rosetta for macOS x86_64 and Docker
emulation for Linux x86_64. Physical Intel, broader hardening, and TSan coverage
were not established. They remain evidence limits, not an added acceptance gate.
Future asynchronous I/O, language-level async/await, task handles, thread
migration, and suspension during cleanup are outside the delivered batch API;
none is dispatched by this record.

## Plan review

This record preserves accepted costs and deferred measurements. It changes no
allocation, task lifetime, Channel ownership, stack layout, or supported-target
contract. No implementation, validator, diagnostic, fixture, or process is added.
