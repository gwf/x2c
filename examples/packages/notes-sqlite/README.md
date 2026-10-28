# SQLite notes

This variant uses the same HTTP handlers, compile-time note record, JSON API,
page, and Lisp policy as [the core notes service](../../apps/notes/README.md).
The store uses one SQLite table and bound prepared statements. A Mutex
serializes access to its connection.

```sh
make -C examples/packages/notes-sqlite prepare
make -C examples/packages/notes-sqlite test
make -C examples/packages/notes-sqlite run
```

Run from the repository root to use the default page and policy paths. The
program accepts a database filename as its first argument, default `notes.db`.
It serves port 8080 and stops on Ctrl-C. `--check` uses an in-memory database
and verifies create, read, update, and delete without opening a listener.

SQLite is optional and uses the package's pinned dependency. It is outside
`make check`; the package example's own `test` target verifies this store.
