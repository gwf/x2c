# BLIS 2.1 licenses

This directory contains license texts and source information for the
firestorm, static, single-threaded BLIS 2.1 build pinned by this package.
These records cover that build only, not package-manager binaries, arbitrary
addons, other configurations, or newer releases.

## Pinned source

- Upstream release: BLIS 2.1.
- Source URL:
  <https://github.com/flame/blis/archive/refs/tags/2.1.tar.gz>.
- Tag commit: `caf0db6be1202d9c83c79b51e75eceb96aa8b556`.
- Git tree: `1907eb77b75c612221c84fb928d1c6ae1761a6fb`.
- Source archive SHA-256:
  `901752ec596cd63421ea45a6a06a9f34491cf5ae01cea412ece05f97a2690a96`.
- Retained root license SHA-256:
  `6b54dbb27c2aeba07c72084ea948d3d7ec206758b119eef37a1cc4f958ac694c`.

The archive contains one root `LICENSE`. The three files named `license.c`,
`license.h`, and `license.sh` under `build/templates/` carry the same terms as
source templates. There is no upstream `NOTICE` or `COPYING` file.

## Compiled-source notice research

The investigated archive contains 273 members: one archive index and 272
ordinary objects. Its generated configured header had SHA-256
`b9dca9af2c37fc36ff28a6718c529abe0cf16a6162686d2badd74caf162fe9e7`.
The old generated member/source inventory is not kept in Git; regenerate it
from the source pinned by `../dependency.json` if a future review needs that
level of detail.

The profile adds 20 armv8a kernel members to the framework and reference
objects. Their notices additionally name Linaro Limited and The University of
Tokyo; `BLIS-2.1-armv8a-BSD-3-Clause.txt` retains both complete terms. One
framework source has additional CPU-identification notices, and three sources
are derived from LAPACK 3.2. The distinct additional terms remain checked in
below.

`bli_cpuid.o` is built from `frame/base/bli_cpuid.c`, whose SHA-256 is
`3f4339cb05a740a161f2ecb93d12032c0abd3fd428f8412aa82e8804de383445`.
Its first notice additionally names Dave Love, University of Manchester. A
later TBLIS-derived `cpuid.cxx` section has a separate notice naming Devin
Matthews. The compiled source also includes `frame/base/bli_cpuid.h`, SHA-256
`67d4149d5ad4f2c5add3e95020990394f85f689ea32d6fa9ed383783b4a4c8ac`,
whose inline TBLIS-derived `cpuid.hpp` section carries another complete Devin
Matthews notice.

The transitive-input audit found two more notices whose holder is absent from
the root BLIS `LICENSE`:

- `frame/thread/bli_thrcomm_hpx.h`, SHA-256
  `f57340d785d0d98f694b9bfd0d6b37be5bcf0e6baf9e26d372476c8c667e8c4f`;
  and
- `frame/thread/bli_thread_hpx.h`, SHA-256
  `a79c9efc54187abef2611e211ac3de05e95fa955990cb86a92d14204c07a88d3`.

Both name Tactical Computing Laboratories, LLC.
`BLIS-2.1-additional-notices.txt` reproduces the two Tactical notices, all
three relevant `bli_cpuid` source/header notices, and both TBLIS provenance
comments verbatim. The generated umbrella contains exactly those two Tactical
blocks and the expected Devin Matthews block as its three notices with
holders outside the root license.

The three compiled LAPACK-derived sources are:

- `frame/base/noopt/bli_dlamch.c`, SHA-256
  `d7fa9352a691ee3c060f58a5a7096af23675163746d814bc4d858fccd152eff9`;
- `frame/base/noopt/bli_lsame.c`, SHA-256
  `a61b5fca9b49ad8f5ff5af349f98dce051e2ba071e34a0a7ca4fceace7a3fa76`;
  and
- `frame/base/noopt/bli_slamch.c`, SHA-256
  `de8f66376fc00bb102dc84faad937cbf3f11f73f676d82376f624c76c09828b0`.

Each identifies itself as a LAPACK auxiliary routine version 3.2 and names
the University of Tennessee, the University of California Berkeley, and NAG
Ltd. `LAPACK-3.2-BSD-3-Clause.txt` retains the complete license published in
the official LAPACK 3.2 distribution at
<https://www.netlib.org/lapack/lapack-3.2/LICENSE>. Its whitespace-normalized
retained SHA-256 is
`fd725c12cb2d3bbedf0c7bb55fd42ce6ffbc3f82a696051618077808b6b7f3d4`.

## Terms and attribution

The root BLIS 2.1 license is BSD-3-Clause. Its complete retained text is
`BLIS-2.1-BSD-3-Clause.txt`. It identifies these copyright holders:

- The University of Texas at Austin;
- Southern Methodist University;
- Hewlett Packard Enterprise Development LP;
- Advanced Micro Devices, Inc.; and
- Oracle Corporation.

The additional compiled-source notices and LAPACK terms above are retained
alongside it. Source redistributions must retain the applicable copyright
notices, conditions, and disclaimers. Binary redistributions must reproduce
them in accompanying documentation or other materials. Holder and
contributor names cannot be used to endorse a derived product without
permission.

These are permissive dependency terms compatible with the project's
Apache-2.0 code policy. Apache-2.0 applies to the x2c-owned binding, tests,
and examples; it does not replace the upstream terms or accept the current
client design.

## Built profile and closure

The proposed profile is the `firestorm` Apple silicon configuration, static
only, single-threaded, with BLAS compatibility, CBLAS compatibility, shared
libraries, and addons disabled. The build consumes BLIS framework sources,
the firestorm configuration, armv8a kernels, and reference kernels. It does
not consume the `blastest/f2c` test tree or the `addon` tree. The archive
contains no BLAS or CBLAS compatibility exports.

The static archive has 48 unresolved external names. They are C library,
allocation, math, Mach clock, thread-local-storage, and pthread facilities
provided by macOS `libSystem`. There are no Fortran, OpenMP-runtime, or other
third-party library references. `PROFILE.json` retains the complete 48-name
set; `make verify-profile` compares it, and `make verify-linkage` rejects
non-system dynamic libraries in the example and test executables.

Clang, `make`, `ar`, `nm`, `jq`, and `otool` are build and verification tools
rather than distributed runtime dependencies. The integration does not vendor
BLIS source or a built BLIS archive.

## Patent and name review

BSD-3-Clause has no express patent license. Apache-2.0's patent grant covers
contributions to the x2c integration, not BLIS or the LAPACK-derived sources.
Any project-wide implementation pledge therefore needs counsel review before
it can be said to cover use of BLIS.

`BLIS`, `TBLIS`, and `LAPACK` are used only to identify upstream software and
native APIs. The integration must not imply upstream endorsement. x2c branding
and trademarks remain separately owned.
