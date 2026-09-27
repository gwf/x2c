# Independent fixed-cost evidence review

Read-only source/data review; no builds or probes. Recomputed aggregate values
from `results.json` using per-process empty-span averages before summing.
Every raw total and calibrated estimate in `fixed-cost-analysis.json` agrees.

- All 67 instrumented translation runs report raw C/H parity and exit zero.
  These are runs, not 67 distinct cases. The separate candidate comparison
  records 62 cases with no changed outcome or raw C/H artifact.
- Each seven-source sample totals 2119 default or 2124 live transactions.
- Raw aggregate medians are 23.457 ms default and 24.098 ms live; calibrated
  estimates are 19.515476 ms and 19.9793803 ms respectively.
- Extended-snapshot timing encloses new snapshot fields and base-binding Map
  copies only. Slot spans end before recursive binding, including the pending
  invocation branch. Preparation spans include cached early returns and target
  lookup but no recursive binding. No recursive binding was charged to these
  three categories.

Qualifications:

1. Empty-span calibration measures two clock reads, not the complete begin/end
   bookkeeping or instrumentation's effects on caching and scheduling. The
   calibrated figures are estimates, not direct uninstrumented measurements.
2. Slot spans include effect consumption and payload replacement when a carrier
   matches. They are not exclusively the cost of failed carrier checks.
3. Fractions of the earlier paired wall-time increase are descriptive ratios
   across runs, not a causal attribution of the remaining increase.
4. Snapshot totals include old and new work; only the explicit extended span
   isolates the proposed added snapshot work. Commit/rollback are not timed by
   this span.
