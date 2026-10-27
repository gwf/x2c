# X2C Documentation Drift Report

> Status: reference - documentation checks and authoritative entry points.

## Mechanically checked surface

`make doc-check` currently verifies:

- the generated module catalog matches live `src/*.x` and `lib/*.x` modules;
- the generated library reference matches the runtime sources and every row of
  `docs/library-manifest.txt`;
- every page under `docs/src/` is reachable from `docs/src/SUMMARY.md`, and
  every SUMMARY entry names a file that exists;
- no document spells the project name as the drug it is pronounced like;
- local Markdown links resolve across README and active top-level docs;
- repository paths in the canonical entry-point set resolve, and a path that
  cites a line number names a line the file has;
- compiler flags named by active docs exist in `src/cli/parsing.x`;
- canonical workflow docs do not reintroduce unsupported `V=1`, missing
  `OVERVIEW.md`, or bootstrap redirection before creating `debug/`;
- example compile commands use quote-only runtime-header lookup so generated
  headers do not shadow system headers;
- every example cited by the language/library guides is either executable in
  the manifest harness or labeled with its non-checked manifest category;
- every stated compiler or runtime module count matches `src/*.x` or
  `lib/*.x`, and the `src/` module lists in `AGENTS.md` and
  `docs/src/internals/architecture.md` name exactly those modules;
- every section under "Partial contracts and open decisions" in
  `agents/x2c-philosophy.md` names a ledger row that is not yet verified.

The path-audited entry-point set is declared in `tools/check-docs`. Its
entries include README, the root and `agents/` agent guidance, the philosophy,
quick start, development guide, code-organization guide, debugging guide,
module catalog, this report, the canonical diagnostics guide, the adapter and
AST-walk references, and six book chapters: architecture, the CLI reference,
the language reference, idioms, the implementation map, and the library
overview.

## Executable examples surface

`examples/manifest.txt` records each example's role, validation mode, and
expected output. `make examples` runs or build-checks the entries selected by
that manifest. An example excluded from those checks does not establish
supported behavior merely by appearing in the repository.

## Current authoritative entry points

- `README.md` routes readers without duplicating a language manual.
- `agents/x2c-philosophy.md` owns principles and contract status.
- `agents/quick-start.md` owns the shortest verified build/test path.
- `agents/x2c-development-guide.md` owns less common compiler and build facts;
  the root `AGENTS.md` owns workflow, validation, and publication.
- `agents/x2c-module-catalog.md` is generated from the live module tree.
- `docs/src/reference/language.md` owns implemented syntax and explicit
  limitations.
- `docs/src/guide/idioms.md` owns verified recommended patterns.
- `docs/src/internals/implementation-map.md` owns feature routing across the
  compiler/runtime boundary.
- `docs/src/library/overview.md` owns runtime relationships and contracts.
- `agents/logger-and-diagnostics-guide.md` owns Logger and compiler diagnostic
  contracts.
- `AGENTS.md` and `agents/AGENTS.md` own agent safety and evidence rules;
  `docs/AGENTS.md` owns the book's authoring rules.

The `docs/` entries above are chapters of the mdBook whose spine is
`docs/src/SUMMARY.md`.

## Coverage limit

The [source style examples](x2c-coding-style-guide.md) identify their code as
illustrative fragments. They are not compiled by the book example checks.
`make doc-check` therefore does not establish that every fragment uses current
syntax or APIs. Review the relevant example against source before adopting it.
