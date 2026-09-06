# libuv 1.52.1 static profile

The admitted source is `libuv-v1.52.1.tar.gz` from
`https://dist.libuv.org/dist/v1.52.1/`, SHA-256
`66d511b9e6e334c0e62279eb234fbfb2b3110b1479c09b95b44c7afca8cff9e7`.
`dependency.json` runs `autogen.sh`, configures with `--disable-shared` and
`--enable-static`, builds with `make`, and installs into the shared dependency
cache. No source or binary is vendored in Git.

## Admitted build and linkage

Package programs link `lib/libuv.a` by full path. The original macOS arm64
archive has 38 members; archive membership depends on the platform.
`make verify-linkage` inspects the built short example: on macOS it permits
only `/usr/lib/libSystem.B.dylib`; on Linux it reads ELF `NEEDED` entries and
permits only libc, libm, libpthread, libdl, librt, and the system loader.
Inspection failures fail the check. Windows needs separate build and linkage
review. These checks describe the build requirements; release qualification
still requires running the package tests and applications on the target host.

The pinned installed headers have these SHA-256 values:

- `uv.h`:
  `bb9ed99b80cd22c58361bffdfbb2aa7029ce0391cde616745c0072a6f3c03219`
- `uv/errno.h`:
  `4242edf790e4569ef349026ab4c6e31093334ee5fc02b16ed7a0d9fbacdffd16`
- `uv/version.h`:
  `a859f2c21f7887d45b0372109ebc91759a6f8c408c7cbf2a12f9bbe579be403b`
- `uv/threadpool.h`:
  `09ae41099af710289155be012df45c2fce04da6a02e813278b4558935e645938`
- `uv/unix.h`:
  `06ccd9e0f3f312b610a7e7a8ff16596988e02796e7a0c81a62e29d5f6abe4613`
- `uv/darwin.h` (macOS):
  `222b6dd3ce67cfbb735b14b1662f065fc23570d6969acf463b39d946b7590d8c`

- `uv/linux.h` (Linux):
  `adce0ed0821c8466a87a0a4c9e0df9ea7e4a4b24d099c7d7ed196f72a13f669d`

`src/uv-152.h` includes the installed upstream header and rejects a release
other than 1.52.1. `make verify-headers` checks the five common headers and the current platform
header before the package links. The Linux header hash comes directly from
the checksum-verified pinned source archive.

## Retained terms

libuv's main terms are MIT. Its distribution also incorporates BSD-2-Clause,
ISC, and other permissive notices. The complete retained files and hashes are:

- `libuv-1.52.1-MIT.txt`:
  `16de0c32b265cb7d46a6d3bd614f259dd4d693a5e26b3407b04aae8d73041f0c`
- `libuv-1.52.1-BSD-2-Clause.txt`:
  `ba661d1dfdbcb6f30d5f7c583e219f595cd8ae4fefd9f8a45ac5526a1b8e6b75`
- `libuv-1.52.1-ISC-notices.txt`:
  `9c3e698639860bd6c45ff70ed43c0c1bba45f3503e5bf527f67d376e9f3175d5`
- `libuv-1.52.1-extra.txt`:
  `262c44bd2cdba037e6d2a82fba15f5800d292bc993a6f5d6b6ea487744d02836`

`make verify-licenses` checks these exact files.

## Imported qualifier losses

The x2c foreign type table currently drops `const` from seven function
results: `uv_dlerror`, `uv_err_name`, `uv_fs_get_path`,
`uv_handle_type_name`, `uv_req_type_name`, `uv_strerror`, and
`uv_version_string`. It also drops `const` from seven direct fields:
`uv_cpu_info_s.model`, `uv_dirent_s.name`, `uv_fs_s.new_path`, `uv_fs_s.path`,
`uv_pipe_s.pipe_fname`, `uv_process_options_s.cwd`, and
`uv_process_options_s.file`. Raw callers must preserve the upstream
read-only meaning. The measured rows are retained in
`../foreign-qualifier-deltas.json`.
