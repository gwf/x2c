# Repository tools

These programs check, generate, measure, and release the repository. Most
run through a `make` target; `make help` lists the targets. Files that start
with `#!/usr/bin/env -S x2c script` are x2c scripts: run them with
`./x2c script tools/NAME`. Each tool's header comment, or its `--help`,
describes its options.

## Contributor checks

- `check-docs` audits documentation paths, cited lines, flags, and links.
- `check-doc-examples` compiles the book's and site's x2c samples.
- `check-gallery-examples` compares gallery slides with their examples.
- `check-conformance-coherence` compares conformance rows across symbol modes.
- `check-cold-collection.sh` compares a cold retranslation with stage 1.
- `check-generated-stages.sh` compares the C output of two compiler stages.
- `check-install-script.sh` runs `site/public/install.sh` on a local release.
- `indent-convert` rewrites brace-form x2c in the indentation syntax.
- `run-make-steps.sh` runs independent `make` targets at the same time.
- `sources.sh` lists compiler or runtime entry units.
- `test-*.py` are offline tests of the Python tools; `make tools-check`
  runs most of them.

## Documentation, site, and source generators

- `gen-api-reference` writes the library and compiler API reference.
- `gen-module-catalog` writes the module and public-function catalog.
- `gen-llms-txt` writes the site's `llms.txt` and `llms-full.txt`.
- `syntax-spec` inspects syntax data and renders its documentation.
- `gen-linked-meta.sh` writes `src/linked-meta.x`.
- `gen-meta-queries.sh` writes `etc/meta-queries.x`.
- `definitions.x` reads the compiler's definition rows for the generators.
- `doc-samples.x` collects the fenced x2c samples of a Markdown page.
- `book-pdf.lua` assembles the book in order for the PDF build.
- `wasm-build` builds one x2c source as a WebAssembly module and loader.

## Measurement

- `repo-metrics.py` prints static size and shape metrics for the tree.
- `performance-snapshot.py` runs and retains the performance snapshot.
- `build-scaling.py` scores stage-build CPU time per source line.
- `build-scaling-history.py` prints retained build-cost rows.
- `c2x2c-benchmark.py` compares c2x2c API costs with native C.
- `x2c_source.py` masks comments and literals for `repo-metrics.py`.
- `record-blis-profile.sh` prints the BLIS profile for this platform.
- `partition/` proposes source responsibility groups; see its README.
- `version-viewer/` compares source versions in a browser; see its README.

## Release tooling

- `release-candidate.py` assembles and transports release candidates.
- `gen-package-index` writes the package index that `x2c install` reads.

[Releasing](../agents/releasing.md) and
[release operations](../etc/release/README.md) describe the release.

## Agent workflow

- `integrate-dev.py` submits work and runs the shared integration queue.
- `land-dev` validates and publishes to `dev`.
- `gate-state.py` reuses or produces publication proof for the tree.
- `agent_context.py` holds the worktree delivery context and shared helpers.
- `hooks/pre-push` applies the delivery context to pushes.
- `agent-failure.py` records one reported agent failure with its evidence.
- `harness-metrics.py` summarizes agent sessions from local transcripts.
- `x2c_reply.py` measures agent replies for `harness-metrics.py`.

[Agent guidance](../agents/README.md) describes these workflows.
