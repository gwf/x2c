# PCRE2 10.48 profile

- Upstream release: `10.48`
- Source archive:
  `https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.48/pcre2-10.48.tar.bz2`
- Source archive SHA-256:
  `b6c68fdf6f3ac31388b50aa89ff0fc49c00c987c16e7b5146491d12003f2c8ed`
- `pcre2.h` SHA-256:
  `20d70c58a3b1f205836ceade32af6179a887f24749b8036620f079919d37b11e`
- `pcre2posix.h` SHA-256:
  `4e3f99d21b10f3168fa562c6345e2b387a1a83f8bd2a35784b2832f4dc4d9444`
- Profile: static width-8 and POSIX libraries with JIT enabled; width-16,
  width-32, zlib, bzip2, and readline support are disabled.
- Linked components: PCRE2, its bundled SLJIT JIT compiler, and the platform C
  runtime. No optional compression or readline library is linked.
- Licenses: PCRE2's BSD-3-Clause text is retained as
  `LICENSES/PCRE2-10.48.txt`; bundled SLJIT's BSD-2-Clause text is retained as
  `LICENSES/SLJIT.txt`.
- Vendored source and local patches: none. `dependency.json` fetches the PCRE2
  release, whose `deps/sljit` source is compiled into `libpcre2-8.a` by
  `--enable-jit`.
- Known x2c foreign-declaration limitations: two function results and six
  record fields lose `const` in x2c's semantic type table. The generated C
  declarations still come from the upstream headers; callers must preserve
  those `const` obligations. `../FOREIGN-C-QUALIFIERS.md` records the exact
  rows.

`dependency.json` is the machine-readable source and build record. The client
uses the prepared headers through `src/pcre2-8.h` and `src/pcre2-posix.h`.
`make verify-headers` checks both admitted public-header hashes.
