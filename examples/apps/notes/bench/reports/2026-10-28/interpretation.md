# Interpretation

The 64-client lookup case favors Go consistently in this run: median
58,905.5 requests/s versus x2c's 41,263.8. Go led all five paired samples,
and the per-server sample-rate ranges did not overlap. This is 42.8% higher
median throughput for Go, using x2c's rate as the baseline.

With one client, x2c's median was 27,616.3 requests/s versus Go's 25,754.0.
x2c led all five pairs. Median per-sample p50 latency was 36 us versus 37 us.
This is a different load condition from 64 concurrent clients.

The durable-update cases do not establish a stable winner. At 64 clients,
the paired winner reversed: Go led the first three pairs and x2c the last
two. At one client, even the ranking changes between the ratio of marginal
medians and the median of paired ratios. Therefore the marginal write rates
in comparison.md must not be read as a reliable write-speed ranking.

The write periods coincided with large changes in host load. The first
matrix's one-minute load ranged from roughly 10 to 38. Background desktop
activity was present, and other development builds were observed around the
measurement window. The samples do not isolate the cause of write variation. The integration
agent kept its own gate and performance work quiet during timing. No user
processes were stopped. The complete matrix is retained without discarding
slow samples or claiming a write-performance winner.

x2c's process-lifetime peak RSS was lower in every sample. For 64-client
lookups, median peak RSS was 11.8 MiB versus Go's 23.2 MiB. For 64-client
updates, it was 16.8 MiB versus 23.5 MiB. This metric includes startup and
warmup and excludes the common load client and operating-system file cache.

The timed load process averaged below 0.6 CPU cores in all case medians;
there is no evidence of aggregate client CPU saturation. This does not
exclude closed-loop scheduling or same-host interference. Server CPU values
include startup, warmup, and shutdown and cannot be called timed-request CPU.

The five paired throughput ratios for each case are in analysis.json. A
ratio is x2c requests/s divided by Go requests/s from the same pair; values
above one favor x2c. These are descriptive observations, not confidence
intervals or a claim about intrinsic language speed. Both executables passed
the same ordinary API tests, and normalized ASCII fixture lookup, list,
stats and update results matched. Standard-library edge-case differences
remain documented in ../../go/README.md.

No channel-based database or response architecture was implemented or timed.
