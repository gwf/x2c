# Permissive dependency intake

This is the project policy for optional packages, not legal advice. It
applies to the complete dependency profile that x2c would build or distribute,
not merely to the license named by the top-level library.

## Default screen

A profile may be admitted when every linked, bundled, or vendored component
has clear non-copyleft terms approved by the project. Common examples are:

- Apache License 2.0;
- MIT and ISC;
- BSD 2-Clause and BSD 3-Clause;
- zlib; and
- the curl license.

This list is illustrative rather than an automatic SPDX allowlist. Unusual
exceptions, generated data, bundled codecs, cryptographic backends, and other
license expressions still require review of their actual terms and notices.

GPL, LGPL, AGPL, MPL, source-available, noncommercial, proprietary, and unclear
terms are rejected by default. A legally possible linking arrangement does
not override that project-policy choice. A new exception requires an explicit
project decision; an integration may not create one implicitly.

## Profile, not project name

An intake decision records one exact build and distribution profile:

- upstream project, version, source origin, and source checksum;
- enabled features and relevant build options;
- every direct and transitive linked component;
- every bundled or vendored source and data component;
- copyright, license, attribution, and `NOTICE` obligations;
- local patches and which license governs them;
- platform-provided dependencies;
- trademark or endorsement language; and
- patent terms or an unresolved counsel question.

Optional TLS, compression, resolver, internationalization, graphics, math, or
threading backends are separate profiles when they change that closure.
Package-manager metadata is evidence, not a substitute for inspecting the
binary or source that will actually be distributed.

## Distribution

Upstream source is not vendored by default. If it is vendored, its license,
notices, provenance, checksum, and local modifications travel with it and
remain visibly separate from x2c-owned code.

A source or binary release retains every required upstream license and notice.
The release review repeats for each target platform because system libraries
and optional backends may differ. Merely passing an integration's local build
does not approve a distributable binary profile.

## x2c-owned material

x2c-owned wrappers, examples, and specifications use the repository's
[Apache License 2.0](../LICENSE). Upstream components retain their own terms.
The project is not accepting external code contributions; see
[the contribution policy](../CONTRIBUTING.md).

Names and logos are covered separately by [the trademark policy](../TRADEMARKS.md).
Dependency names are used descriptively and do not imply sponsorship or
endorsement. Licensing x2c does not change a dependency's license or patent
terms; those remain part of the dependency review.

## Where the record lives

Each package pins source and build facts in
`packages/<name>/dependency.json`, keeps required terms under `LICENSES/`,
and explains accepted behavior or unresolved research in its README. A compact
profile file may retain facts that materially inform review. Generated API or
compiled-source inventories stay outside Git and may be regenerated from the
pinned source when needed. Candidate research keeps concise evidence under
`plans/`, with completed or rejected investigations in `plans/archive/`, so a
later review can distinguish a changed upstream profile from a repeated
investigation.
