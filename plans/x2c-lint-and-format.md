# Structured lint findings

> Status: active, narrowed 2026-10-24 against `7e9fd0178`.
> Phase 8 was approved on 2026-09-24 and remains unfinished. The existing
> linter and formatter are delivered in experimental `commands/lint`.

## Current remaining work, 2026-10-24

1. Add an option for `x2c-lint` to print findings as x2c List literals.
   Reuse the findings already collected by the linter.
2. Add the approved thin compiler entry point, as a subcommand or directive,
   to run the linter and read those findings without an intermediate JSON
   representation. Report findings or promote them to errors when requested.
3. Keep lint optional. Do not run it on every build or add a recurring gate.

`commands/lint/x2c-lint.x` currently accepts no structured-output option.
`Lint.print` in `commands/lint/lint.x` prints human-readable lines. The
compiler has no current lint-result consumer. This was checked by reading
source; no runtime probe was needed for this interface inventory.

## Distribution and editor boundary

Lint remains experimental and uninstalled, as `commands/manifest.txt`
records. The original editor lint kind was conditional on shipping lint
to users and was not implemented. Preserve that condition rather than
counting it as completed or expanding distribution implicitly.

The existing formatting checks and optional workflow remain available.
JSON for third-party tools is a possible later addition, not required for
the selected List interface. `tools/repo-metrics.py` deliberately remains
Python; the old universal compiler-projection claim did not describe that
exception accurately.

## Delivered work and evidence

The [implementation record](archive/x2c-lint-and-format-implementation.md)
preserves phases 0-7, conditional editor work, measurements, tool migrations,
and earlier decisions. It is not a second backlog. Do not repeat the old
Python-porting or linter implementation campaigns.

## Plan review

Reuse the linter's findings and the existing List reader and diagnostics.
The selected change adds a serialization option and its compiler consumer,
not another parser, analysis engine, or findings model. No new validator,
dedicated diagnostic, negative fixture, or recurring gate is selected here.
Resolve the entry-point spelling within the existing approved scope before
implementation; preserve optional execution and current distribution.
