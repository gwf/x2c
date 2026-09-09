# Cosmopolitan bootstrap experiment

This experiment is for fun only. It provides a minimal compiler bootstrap,
not a substitute for the full repository. Its bundled source is enough to
rebuild the compiler and runtime, but includes no examples, book, or optional
packages. Use the full repository for normal development.

One command builds `dist/x2c.com`, the portable compiler with bundled source:

```sh
make ape-build
```

This is an optional release operation, not part of the default build or
`make precommit`. On first use it downloads the pinned Cosmopolitan 4.0.2
archive, verifies its SHA-256 checksum, and records the completed SDK in a
versioned cache. Later builds reuse that cache.

In addition to the normal x2c build requirements, the release command needs
`curl`, `unzip`, `tar`, and `zip`. The setup uses POSIX `sh` and `make`.

The cache defaults to `$XDG_CACHE_HOME/x2c/cosmopolitan`, or
`$HOME/.cache/x2c/cosmopolitan` when `XDG_CACHE_HOME` is unset.
`X2C_COSMO_CACHE` selects another location. `make ape-toolchain` prepares
only the cached SDK.

The script first checks that checked-in `bootstrap/` and `builds/0` contain
the same generated C/H bytes. It builds a fat APE, assembles the matching x2c
source and header payload, writes a per-file content manifest, includes the
dependency notices, and appends the payload as an APE ZIP.

The seed is only a portable first compiler. Running:

```sh
./dist/x2c.com bootstrap --prefix /desired/x2c
```

uses the host's GCC- or Clang-compatible `cc` and a compatible `ar` to
produce an ordinary host-native compiler and runtime. Cosmopolitan is not
copied into that installation.

To test the complete bootstrap process on the current host:

```sh
make ape-verify
```

The test verifies the APE ZIP, installs the native compiler with default
`cc` and `ar` discovery, rebuilds the runtime and compiler from the installed
source payload, compares the two native compilers' generated C/H output, and
builds and runs a program with the second installation. Set
`X2C_APE_VERIFY_KEEP=1` to preserve its temporary workspace after the run.
This target remains outside the default build and `make precommit`.

## Expert overrides

`build-ape.sh` assembles the release. Call it directly with
`COSMOCC` and `COSMOAR` to use a manually managed SDK.
`COSMO_LICENSE_DIR` and `OUTPUT` are optional overrides.
