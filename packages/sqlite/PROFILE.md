# SQLite 3.53.4 profile

- Upstream release: `3.53.4`, version number `3053004`.
- Source: `https://www.sqlite.org/2026/sqlite-autoconf-3530400.tar.gz`.
- Source archive SHA-256:
  `0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c`.
- `sqlite3.h` SHA-256:
  `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d`.
- `sqlite3ext.h` SHA-256:
  `ac9645e5c9ff0cf176efdd6e75cb5e98f46295d38e02db5c4d208826a39ab4be`.
- `sqlite3.c` SHA-256:
  `b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189`.
- License: SQLite's public-domain dedication, reproduced from the pinned
  source in `LICENSES/sqlite-3.53.4.txt`.
- Native build: the unchanged amalgamation, `-O2 -std=c99 -pthread`, with
  `SQLITE_THREADSAFE=1`. No `SQLITE_OMIT_*` or optional `SQLITE_ENABLE_*`
  definitions are added. The upstream JSON functions are included by default.
- Linkage: static `libsqlite3.a`, platform C runtime, math, and pthread
  support.
  No additional library, framework, or loadable module is bundled.
- Native extension loading retains SQLite's default: disabled for a connection
  until explicitly enabled through the raw API. Optional FTS, RTree, session,
  snapshot, and column-metadata builds are not part of this profile.
- Vendored upstream implementation and local patches: none. Source, headers,
  objects, archive, and receipts live in the existing dependency cache.
- Verified platform: macOS. The package interface and applications were
  accepted on September 9, 2026. No additional platform support is claimed.

`dependency.json` owns the reproducible native build and archive checksum.
`make verify-headers` checks both complete public headers. The small
`src/sqlite-3.h` shim includes the pinned real header and rejects a different
version or conflicting explicit thread profile; it does not copy declarations
or forward SQLite functions. The extension author header is installed beside
`sqlite3.h` and can be included as `<sqlite3ext.h>` when building an extension.

The raw API preserves upstream types, constants, callbacks, status codes, and
operations. Some declarations in upstream headers require optional build
features; their presence is not a claim those optional features are linked.
Use `sqlite3_compileoption_used` or `sqlite3_compileoption_get` to inspect the
admitted build. Custom collations, virtual tables, native callbacks and native
extension loading remain raw operations. Their SQLite callback/thread and
ownership obligations continue to apply; the ordinary client does not make
arbitrary native callback entry safe for x2c Errors or runtime state.
