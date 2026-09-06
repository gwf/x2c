# Third-party software and notices

Except where a file or subtree states otherwise, x2c is licensed under the
Apache License 2.0 in [`LICENSE`](LICENSE).

## Language shootout

`examples/shootout/` is separately licensed under the BSD 3-Clause License.
Its [`LICENSE`](examples/shootout/LICENSE) and
[`THIRD_PARTY.md`](examples/shootout/THIRD_PARTY.md) files identify the
applicable terms and attribution for the Computer Language Benchmarks Game
and LangArena-derived material.

## Optional native packages

`packages/` holds optional adapters for third-party C libraries. The
vendored third-party license texts are under `packages/*/LICENSES/`.
Dependency terms are governed by
[`packages/LICENSE-POLICY.md`](packages/LICENSE-POLICY.md) and each
package's README.

## Optional release toolchain

The optional Cosmopolitan release process downloads a checksum-pinned
Cosmopolitan distribution. It is not stored in this repository. Its own
license governs that component, and the x2c release builder copies its
license files into each source-bearing APE release.

## Optional website toolchain

The public website under `site/` is rendered by an npm toolchain pinned in
`site/package.json` and `site/package-lock.json`, and by mdBook for the
embedded book. Those packages are downloaded by `npm ci`, are not stored in
this repository, and remain governed by their own licenses. Nothing in a
compiler, runtime, or release artifact depends on them.

## Licensing contact

Send licensing and provenance questions to
[licensing@flake.org](mailto:licensing@flake.org).

## Hash-table benchmark adaptation

`unittest/benchmarks/hash-table/jackson/string-blueprint.h` adapts Jackson
Allan's `cstring_uint64_fnv1a` blueprint. Its original copyright notice is
retained in the source; the upstream MIT license is included in
[`jackson/LICENSE`](unittest/benchmarks/hash-table/jackson/LICENSE).
The source and license were checked at the benchmark runner's pinned commit
[`71f0e4075b30d3b0e9baadc07bc7e889b04836ea`](https://github.com/JacksonAllan/c_cpp_hash_tables_benchmark/tree/71f0e4075b30d3b0e9baadc07bc7e889b04836ea).
This notice covers that adaptation; other benchmark dependencies are fetched
by their runners and retain their own terms.

## Website fonts

`site/src/layouts/BaseLayout.astro` and `docs/theme/head.hbs` request
Instrument Serif, Archivo, and JetBrains Mono from Google Fonts. These fonts
are served remotely; no font binaries are tracked in this repository. The
website-toolchain notice above does not identify or license those fonts.
Any future distribution of local font files must retain the notices shipped
with the selected font versions.
