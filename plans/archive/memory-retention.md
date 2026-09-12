# Attribute retained memory before changing ownership or Pool policy

> Status: done - attribution complete, 2026-09-11; no policy change.
> Delivery commit subject: `overlap native fingerprints and close research probes`.
> Current-source probes distinguish Pool depot retention from the Torch
> request-loop footprint. No runtime memory policy or public API is changed.

## Scope and method

This work follows [the research agenda](../research-agenda.md). Its two questions
have separate owners: intentional Pool backing retention and the unexplained
process-footprint excess in the historical Torch comparison. One is not
assumed to cause the other.

Probes use source at `2befcb4` on arm64 macOS 15.7.9 (24G830), the existing
native compiler, and the prepared Torch 2.10.0 Python wheel. The Torch package
and tabular application were rebuilt from current source into a private
`/tmp` directory, with existing optional native-handle counters enabled. The
existing benchmark artifacts were reused. No dependencies were downloaded,
host tools changed, or performance claims made from these diagnostic runs.

The temporary native helper samples `malloc_zone_statistics` byte counters
and Mach physical footprint at the existing request-cleanup sampling points.
A separate pressure-relief control invokes `malloc_zone_pressure_relief`;
it is an attribution experiment, not a proposed application behavior. The
helper's allocator block-count field is not used: this host reported an
inconsistent value after pressure relief. Byte counters and independently
maintained Scope/Pool/native-handle counters are reported separately.

## Pool burst, release, and reuse

A child Pool receives one million touched 48-byte allocations, releases them,
then receives the same burst again. Three fresh processes repeat the probe.
It exercises region storage directly, without canonical-table growth or
promotion, so it isolates backing policy rather than application interning.

All repetitions allocate 24,391 burst blocks. Release returns Scope live
allocations/scopes from 25/5 to their baseline 19/4, and active Pool bytes
return to 2,048. However, 49,952,768 bytes remain in the depot; total backing
stays 49,954,816 bytes. The equal second burst reuses all 24,391 blocks and
allocates no new blocks.

This is intentional retained backing, not evidence of unreachable storage.
[Pool._block_return](../../lib/pool.x) transfers ownership to the depot, and
`_block_lease` reuses it. The process registry and page index retain those
addresses until `_storage_shutdown`. A trim cannot safely free depot blocks
without updating both registry and index under the storage lock.

The synthetic burst demonstrates that a transient workload can leave about
50 MB of backing for the process lifetime. It does not establish that an
ordinary compiler/server workload benefits from a retention cap. Repeated
bursts demonstrate the existing reuse benefit; their timing was not measured.

## Torch request-loop attribution

The existing pooled profile runs 100,000 and 400,000 requests in three fresh
processes each. A seventh fresh process runs 400,000 requests with allocator
pressure relief at each existing sample. All runs preserve root pool depth,
return the same checksums at the same request count, and retain exactly 14
native tensor handles, 109 Scope allocations, and seven Scopes after warmup.
Pool active/backing/depot bytes stay 46,592/48,640/2,048 throughout.

| Requests/control | Final footprint, MB | Final malloc live, MB |
| --- | --- | --- |
| 100,000, three fresh runs | 138.51, 139.23, 139.99 | 77.17, 77.21, 77.11 |
| 400,000, three fresh runs | 140.69, 139.25, 142.82 | 77.42, 77.38, 77.71 |
| 400,000, pressure relief | 79.30 | 77.31 |

MB means decimal megabytes. In ordinary runs, malloc live bytes decrease
from their post-warmup levels of 81-91 MB even as physical footprint rises.
Allocator-reserved bytes at the final sample are 161-172 MB for 100,000
requests and 196-202 MB for 400,000. Reserved bytes are not resident bytes,
and none of these byte counters is a count of live tensor storage alone.

Pressure relief directly reduces one post-load physical-footprint sample by
45,776,944 bytes while its malloc live-byte count stays unchanged. Later
request samples also lose residency on relief. The control ends near 79 MB
instead of the ordinary 139-143 MB, with the same live handles, Pool storage,
and numerical output. The helper returns zero relieved bytes on this host
even when Mach reports a drop; attribution uses the observed footprint, not
that return value.

This identifies substantial allocator-reclaimable residency and rules out
the 2 KB Pool depot as owner of the multi-MB residual in this profile. It does
not identify individual allocation stacks or distinguish every native
library cache from allocator fragmentation. The earlier x2c/Python peak
ratio remains historical: Python was not rerun, peak counters cannot decrease,
and this is a single-platform CPU result rather than a GPU/Linux guarantee.
The longer run does not show proportional growth of live storage; it does
not establish an indefinite bound for all workloads.

## Decision and limits

Preserve the current Pool and ownership behavior. There is no reproduced
Pool lifetime defect or evidence that Pool trimming repairs the Torch
residual. A future retention-policy proposal needs an actual workload that
suffers from idle retained backing, a chosen retention budget/lifetime, and
measured repeated-burst allocation and latency costs. Public trim semantics
and ownership changes are not implied by this investigation.

Temporary reproducible probes, build logs, raw measurements, and the summary
are retained at
`/Users/gary/Documents/x2c-evidence/research-20260912/memory-retention/`. Key inputs are `pool.x`, `sample.c`,
`build.py`, `measure.py`, and `summarize.py`; these are optional experiments,
not shipped test infrastructure or recurring validation requirements.

## Plan review

Pool release establishes invalidity of unpromoted child values and moves
empty region blocks to a known depot. Scope and native handles have separate
lifetime counters; process footprint alone cannot override those facts.
The investigation reuses PoolStats and the Torch profiles/counters and adds
no shipped helpers, caches, traversal, representation, validator, diagnostic,
negative fixture, or gate. It changes no canonical identity, promotion,
interior-pointer lookup, or thread-safety contract. No implementation is
proposed without evidence and a separately settled retention policy.
