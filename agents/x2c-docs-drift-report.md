# X2C Documentation Drift Report

> Status: reference - documentation checks and authoritative entry points.

## Mechanically checked surface

`make doc-check` builds the current compiler, then runs two read-only
scripts with it: `tools/check-docs` and `tools/gen-llms-txt --check`.
`tools/check-docs` declares the page lists named below.

`tools/gen-llms-txt --check` verifies that `site/public/llms.txt` and
`site/public/llms-full.txt` match the book they are generated from.

`tools/check-docs` verifies that:

- `agents/x2c-module-catalog.md` matches what `tools/gen-module-catalog`
  generates from the compiler and runtime source units;
- the API reference that `tools/gen-api-reference` generates, under
  `docs/src/library/modules/` and `docs/src/internals/compiler-api/` with
  their `docs/src/SUMMARY.md` sections, matches the sources and every row of
  `docs/library-manifest.txt`;
- every page under `docs/src/` is reachable from `docs/src/SUMMARY.md`, and
  every SUMMARY entry names a file that exists;
- no checked page spells the project name as the drug it is pronounced like;
- every local Markdown link in the link-checked pages names a file that
  exists;
- every repository path cited in the path-audited pages exists, and a path
  that cites a line number names a line the file has;
- every compiler flag named in the flag-audited pages is an option in
  `src/cli/parsing.x`;
- the workflow-audited pages do not reintroduce unsupported `V=1`, a missing
  `OVERVIEW.md` entry page, bootstrap output redirected before `debug/`
  exists, or `cc -I include` instead of quote-only runtime-header lookup;
- every example that the example-audited pages cite is executable in the
  manifest harness or labeled with its non-checked manifest category;
- every stated compiler or runtime module count in a checked page matches the
  catalog, and the `src/` module lists in `AGENTS.md` and
  `docs/src/internals/architecture.md` name exactly the compiler units;
- every section under "Partial contracts and open decisions" in
  `agents/x2c-philosophy.md` names a ledger row that is not yet verified.

The checked pages are `README.md`, `AGENTS.md`, the Markdown directly in
`agents/` and `docs/`, and every page below `docs/src/`. The link-checked
pages add the Markdown below `agents/skills/`, `packages/`, and `plans/`,
except fetched or built trees such as `deps/` and `node_modules/`. Links are
resolved without their `#` fragments, so a fragment that names a missing
heading is not reported. URLs are not fetched. `site/` is absent on purpose:
its links are URLs on the rendered site, which `make site-check` resolves
against the built output.

The path-audited entry points are `README.md`, `AGENTS.md`,
`agents/AGENTS.md`, `agents/x2c-code-standard.md`, the philosophy, quick
start, development, code-organization, and debugging guides, the module
catalog, this report, the diagnostics guide, the adapter and AST-walk
references, and six book chapters: architecture, the CLI reference, the
language reference, idioms, the implementation map, and the library overview.
The flag, workflow, and example audits each use a subset of those pages;
the flag audit also reads the lines that name x2c in `agents/quick-start.md`
and `docs/src/guide/scripting.md`.

A module count is a number followed by at most three words and `modules`.
It counts runtime modules when the phrase names `runtime`, or names neither
`runtime` nor `compiler` and the 40 characters before it name `runtime`;
otherwise it counts compiler modules. Both counts follow the catalog.
Compiler modules are the units in `src/` and `src/components/` and each
`src/<m>/<m>.x`, without the generated `src/linked-meta.x`. Runtime modules
are the units in `lib/` and each `lib/<m>/<m>.x`, without the generated
`lib/x2c.x`.

`tools/gate-state.py ensure doc-check` runs `make doc-check`. It also runs
`make -o build doc-outputs` when a page under `docs/src/` has an `x2c` sample
and no gate record in the workspace holds its current content, so a broken
output fence cannot pass as documentation-only.

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
- `agents/x2c-code-standard.md` owns x2c source style.
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
