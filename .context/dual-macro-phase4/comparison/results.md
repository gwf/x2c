# Final combined candidate comparison

Passed: final frozen candidate `/tmp/x2c-dual-combined-final`, SHA256
fa2fd1f67c31f07c486fb68acc6d1edcb9fdc2d7b23250d812935f28c00c1148,
matches unchanged baseline `/tmp/x2c-dual-compiler-baseline` on all 62
comparison cases: 46 lexical-try fixtures and 16 default/live corpus cases.
The cases have identical exit outcomes and raw generated C/H bytes, with no
normalization. The baseline has 38 passing try fixtures and 8 expected
negative fixtures; all 16 corpus translations pass. The manifest comparator
does not compare diagnostic text, so negative outcomes are not proof of
byte-identical diagnostics. The final timed output contains 32 C/H files,
all identical baseline/candidate. Checksums match before and after timing.

Both processes use identical absolute source paths, explicit common X2C_HOME
agent-dual-transport, flags and output policy. Collector and timing runner
explicitly remove X2C_DUAL_EFFECT_PROBE from each child environment. Their
parameterized scripts, manifests, raw log, sample data and digest lists are
retained here. The baseline manifest is the earlier common-home baseline;
its binary/source paths/settings are unchanged.

Five alternating paired samples after one warmup for each compiler/group/mode:

| Translation workload | Mode | Baseline median s | Candidate median s | Change |
|---|---|---:|---:|---:|
| Seven compiler/tokenizer files | default | 6.263 | 6.347 | +1.34% |
| Seven compiler/tokenizer files | live | 7.864 | 7.611 | -3.21% |
| exception-hot-paths | default | 0.574 | 0.576 | +0.42% |
| exception-hot-paths | live | 0.640 | 0.636 | -0.60% |

Thin performance evidence: sample ranges overlap. Compiler live mode is
particularly noisy: baseline 7.158-9.811 seconds and candidate
7.487-10.753 seconds. The early live pairs were slow for both; later pairs
were faster. A transient ../1/x2c process appeared in a CPU snapshot and
exited before its parent/args could be inspected; no owner was established.
The requested session build window was held, but that observation prevents
claiming strict host isolation. Do not present the -3.21% median as a speedup
or the smaller deltas as precise overhead. These are real combined-candidate
translation measurements, not a runtime substitution proxy. They do not
measure runtime exception execution, cold preparation, allocations, the
whole compiler migration, or every possible slot/effect workload.

Reproduce collection with collect.py --compiler FINAL --source-root
/Users/gary/.codex/worktrees/agent-dual-transport/x2c --x2c-home SAME --out DIR.
compare.py baseline-manifest.json final-manifest.json checks raw parity.
paired.py --baseline BASELINE --candidate FINAL --source-root SAME
--x2c-home SAME --out DIR --samples 5 produces alternating samples.

Failed, pre-existing: native-helper-shadow.x generates identical C on baseline
and prior bound/open control, both rejected by the native compiler because a
caller-local int shadows x2c_exception_push. Original open-shadow-fails.x
builds on both and aborts its injected-call-count assertion. See shadow.md;
these are distinct outcomes and no hygiene repair was attempted.
