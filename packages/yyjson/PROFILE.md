# yyjson 0.12.0 profile

- Upstream release: `0.12.0`
- Source archive:
  `https://github.com/ibireme/yyjson/archive/refs/tags/0.12.0.tar.gz`
- Source archive SHA-256:
  `b16246f617b2a136c78d73e5e2647c6f1de1313e46678062985bdcf1f40bb75d`
- `src/yyjson.h` SHA-256:
  `175867c5493a5df648cec566717fa1c29aa2f6096f5f0cf1efad0b65e1f6d7b3`
- `src/yyjson.c` SHA-256:
  `ac2e9bbb2e2d9149d90878d40506a1d624fa0b33c979a11b61075c54782c6d6a`
- License: MIT, reproduced verbatim in
  `LICENSES/yyjson-0.12.0.txt`
- Enabled surface: default reader, incremental reader, writer, and utilities;
  no `YYJSON_DISABLE_*` feature macros.
- Linked components: yyjson and the platform C runtime only; yyjson has no
  optional compression, TLS, or other linked backend in this profile.
- Vendored source and local patches: none.

`dependency.json` is the machine-readable source and build record. The client
uses the prepared upstream header directly rather than copying an API
inventory into x2c declarations. `make verify-headers` checks the admitted
header hash before release validation.
