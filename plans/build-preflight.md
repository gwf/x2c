> Status: active
> Approved for publication; follow-up to the build-only package command.

# Build prerequisites

`./configure` reports the core build's missing commands together.
`./configure --packages [name ...]` additionally reports the selected package
requirements; omitting names selects all seven. `make configure` and
`make configure-packages` expose these through Make. No configuration file
or cached report is written.

Core requirements are Make, Python 3, /bin/bash, and the selected CC/AR.
Live preprocessing also uses X2C_CC when set. Git is optional in the core
branch-name code and is not required there. Package dependency caching needs
Git; downloads and extraction already use Python. Existing package profile
rules need shasum and, for BLIS, jq/nm/ar.

A shell probe with two nonexistent compiler/archiver names reported both in
one invocation. Reuse deps.py's cache-completeness decision to skip preparation-only tools
for cached dependencies, and honor explicit native prefix overrides.
OpenSSL's pinned Configure imports FindBin, and OpenSSL/config.pm imports
IPC::Cmd. Check those imports when preparing OpenSSL. Do not require bundled
Text::Template, or Expect for any build-only operation.

## Implementation

1. Add a small shell configure entry point. Run the core report before
   bootstrap-ready and before build-safe can clean. Run the package report
   before the root packages target invokes the compiler build.
2. Extend deps.py's existing dependency preparation with native prerequisite
   reporting before downloads. Reuse that reporting for the package selection
   in configure. Move cache-prefix lookup into dependency.mk's existing
   no-prefix-override branch.
3. Document the interface and its limits. Exercise aggregate failures,
   overrides, cached dependencies, missing Perl modules, and normal macOS
   builds. Fedora execution is explicitly waived. Keep checks/precommit
   targets unchanged and add no recurring test suite.
4. Review and fix the authored diff for duplicate work, unnecessary checks,
   and consistency before final validation. Run final publication checks and publish into main.

## Validation

The core and package builds pass on macOS with the existing native cache.
Three configure tests and eleven dependency tests pass. An actual invocation
with a restricted PATH and a Perl wrapper reported both missing shasum and
FindBin, supplied the two Fedora package names, and created no cache. A
parallel Make probe with missing CC and AR stopped build, build-safe, and
packages before compilation or cleaning. Fedora execution was waived.

## Plan review

Existing manifests own native build steps, deps.py owns cache completeness,
and package Makefiles own profiles. Reuse these facts; do not download,
configure native libraries, or compile probes merely to report missing tools.
The prefix override already selects externally prepared dependencies; moving
its cache lookup removes an unnecessary requirement. The shell entry point
works without Python so the core report can still identify missing Python.
The small transitive native-tool list describes actual pinned upstream script
requirements that manifest argv cannot expose. No new build representation,
cache, or compiler/runtime code is needed. These checks implement the user's
explicitly requested early aggregate prerequisite diagnostics; ordinary
upstream configure and native compilation retain capability/platform checks.
