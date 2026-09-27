# Remove APE and Cosmopolitan

> Status: active - 2026-09-27. Gary's decision: Cosmopolitan is no longer
> supported by its authors, so x2c drops the APE build, the `x2c bootstrap`
> command, and every Cosmopolitan path. Work lands on `meta-integration`
> before the remaining optional checks are addressed.

## Goal

The repository has no APE build, no Cosmopolitan toolchain, and no code or
documentation that exists only for them. Native builds, `make install`, and
the release workflow are unchanged. Archived plans keep their history.

## Removal

- `etc/cosmopolitan/` (README, build scripts, toolchain setup, libm shim,
  APE verifier).
- Makefile `APE_TARGETS`, `ape-toolchain`, `ape-build`, `ape-verify`;
  the `make ape-build` and `make ape-verify` steps in
  `.github/workflows/release-validation.yml`.
- `src/bootstrap.x` and the `x2c bootstrap` subcommand: `CLI_BOOTSTRAP`
  and its option rows and checks in `src/cli.x`, the bootstrap path in
  `src/main.x`, and the `__COSMOPOLITAN__` block there.
- `etc/x2c-payload.x`: the `support` command, `copy_command_sources`, the
  `sources` flag of `copy_support` that carries `src`, and the Cosmopolitan
  license copy. `install` and `uninstall` stay, and install still ships
  `etc/meta-helper.x`.
- `__COSMOPOLITAN__` in the platform conditions of `src/compiler.x` and
  `src/stage.x`; the Windows and Cygwin terms stay. The Cosmopolitan note
  in `lib/thread-state.x`.
- Tests: `cli-bootstrap.help`, the `bootstrap` line of `cli-top.help`, and
  the bootstrap cases in `unittest/probes/run-cli-boundary.sh`.
- Documentation: README, THIRD_PARTY, AGENTS repo map, agent guides,
  the CLI reference `bootstrap` section, installation and from-C guides,
  architecture, the self-hosting example and slide (keep native
  self-hosting content if any), the site landing page, and the active
  plans that mention the APE seed. Regenerate the compiler API pages,
  module catalog, `site/public/llms-full.txt`, and `bootstrap/`.

## Validation and delivery

`make build`, the CLI fixtures and probes, `git diff --check`, then
`tools/gate-state.py ensure agent-pr-check` on the integrated tree and a
push to `origin/meta-integration`.
