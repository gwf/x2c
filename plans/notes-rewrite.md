> Status: ready for shared integration
> Gary requested a complete task-first rewrite on 2026-10-28. SQLite is the
> selected store for a comparable complete notes-service workload.

# A direct notes server

Replace the feature-showcase application with an ordinary SQLite-backed
HTTP notes server. Keep the browser UI and JSON CRUD, tag/search, stats,
validation, and graceful shutdown behavior. Preserve existing JSON files;
the new default is notes.db. Do not load or modify a former JSON store.

## Design

- One notes.x application source owns startup, route registration, request
  validation, prepared SQL operations, and conversion of returned rows to
  response Maps. Use request-local Maps directly; no intermediate Note type.
- Main owns one SQLite Database and one Mutex. The existing HTTP server owns
  its worker pool. Hold the Mutex while using the connection and consuming
  its statements. Close statements before releasing the lock.
- SQLite owns persistent records and write atomicity. Store id, title, body,
  tags (JSON text), created, and updated in one table. IDs remain decimal
  strings in the HTTP API; use SQLite's autoincrement integer key internally.
- Validate user-editable fields once at POST/PUT. The server owns identity
  and timestamps. Keep regular-expression search and the existing HTTP body
  limit. Remove arbitrary forbidden tags and the Lisp size policy.
- Delete record generators, quoted-code templates, Lisp policy, generic store
  protocol/callbacks, long-lived record pools, full-store snapshots, and the
  separate SQLite variant. Shared runtime APIs remain unchanged.
- Move the built-in client/self-check to external Python HTTP/restart tests,
  reached through the existing Notes check target. Classify the example as
  optional because SQLite requires its prepared package dependency; ordinary
  core examples must not fetch it.
- Update docs, site, manifest, and package-check references. Keep benchmark
  load separate from the application. Remove fixed-body C/Go comparisons
  and stale results; those do not implement the same service. A future Go
  comparison must use the same SQLite implementation/configuration, schema,
  queries, connection count, durability and workload.

## Review and validation

SQLite uses existing prepared bindings and copied query rows, so request
values need no persistent ownership adapter. A single connection plus Mutex
has an explicit concurrency cost, which a future Go comparison must match.
A read by id selects only that record. Updates/deletes check their affected
record while holding the connection lock. No compiler/runtime changes or new
framework are needed. Removing the file store changes storage format and the
package dependency; existing files stay untouched and the README names both.

Run the existing Notes check using external HTTP tests for CRUD, malformed
JSON, invalid fields, search, stats, 404s, concurrent IDs and persistence
across restart. Verify the existing UI in a browser. Review the source and
all connected deletions. Submit focused evidence to the shared integrator;
no full author gates. The integrator owns final generated docs and gate.


## Implementation evidence

The server is one 210-line notes.x source. It uses a two-field application
record for the database and mutex, ordinary route handlers, bound SQL,
request-local Maps, and the standard command-line parser. The prior four
application source units and the separate SQLite variant are replaced.
No application meta functions, code generators, Lisp interpreter, generic
store interface, persistent record pools, or whole-store snapshots remain.

The existing core-manifest loopback check and SQLite-variant check are
consolidated into the optional Notes check target. Ordinary core examples
skip this SQLite-dependent app. The build driver owns incremental dependency
checks, including imported native archives.

External HTTP tests pass for CRUD, validation, malformed JSON, tag and regex
search, UTF-8 byte stats, missing IDs, concurrent IDs, static assets, and
restart persistence. Follow-up checks accept the formerly forbidden tag and
a 70,000-byte body, check CLI errors/help, and verify that an old JSON file
is unchanged when rejected as a SQLite database. Desktop/mobile browser
flows and the accessibility scan pass. The site builds. The load-tool smoke
passes against a real SQLite-backed lookup; no cross-language ratio remains.

Independent source review confirms statements finish before mutation
responses, statements finalize before unlocking, and shutdown joins HTTP
workers before freeing the mutex and database. No full author gate ran.
Shared integration owns final generated documentation and publication.
