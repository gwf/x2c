# Isolated dual-use macro research evidence

Baseline: 1b23aaa7e103461c3b219b9e10546aeb35384b60, 2026-09-27.
Specification and plan: ../../plans/dual-use-syntax-templates.md
(relative to repository root: plans/dual-use-syntax-templates.md).
No production feature, commit, push or merge was performed.

## Reproduction

After the repository-required safe build, these succeeded:

```
builds/0/x2c run --build-dir /tmp/x2c-dual-macro-baseline .context/dual-macro/baseline.x
builds/0/x2c run --build-dir /tmp/x2c-dual-macro-shared .context/dual-macro/shared-list.x
builds/0/x2c run --build-dir /tmp/x2c-dual-macro-shadow unittest/compiler-fixtures/macro-template-lexical-shadow.x
builds/0/x2c run --build-dir /tmp/x2c-dual-macro-datum-verify .context/dual-macro/transport-datum-probe.x
builds/0/x2c run --build-dir /tmp/x2c-dual-macro-helper-verify .context/dual-macro/transport-helper-probe.x
python3 .context/dual-macro/alpha-model.py
python3 .context/dual-macro/cross-capture-model.py
```

Expected negative probe (exit 1 after output directory exists):

```
mkdir -p /tmp/x2c-dual-macro-negative
builds/0/x2c translate --out-dir /tmp/x2c-dual-macro-negative .context/dual-macro/negative-braces.x
```

Logs: debug/dual-macro-{bootstrap,baseline,shared,shadow,negative,alpha,cross-capture,datum-verify,helper-verify}.log.

`macros.md`, `binding.md` and `transport.md` contain independent source traces
and cross-review. Some initial recommendations in those notes were corrected
by their addenda and the integrated specification. The integrated document
owns the recommendation.

The Python models use supplied declaration ownership and relocation maps.
The datum probes contain illustrative local-slot data and dummy positive IDs,
not compiler-approved program bindings. The helper pipeline demonstrates
transparent data, not anonymous literal parsing or domain hydration.
