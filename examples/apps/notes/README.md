# Notes

A notes service with JSON persistence, tags, regular-expression search, and a
browser interface. The service uses the optional blocking `net.x` and `http.x`
modules. The HTTP worker pool supplies threads and a bounded channel; each
request has an isolated Context.

From the repository root, after building x2c:

```sh
make -C examples/apps/notes build
examples/apps/notes/builds/notes --host 127.0.0.1 --port 8080 --store notes.json
```

Open <http://127.0.0.1:8080/>. Ctrl-C stops accepting requests, joins the workers,
and closes the listener. The server also accepts `--workers N`, `--public DIR`,
and `--policy FILE`. The defaults are eight workers, this example's `public`
directory, and `policy.xlisp`. Relative paths are relative to the process's
working directory. Bind behind a TLS reverse proxy for deployment; the core
server speaks plain HTTP.

## API

All note bodies are JSON objects. `title` is required nonempty text; `body`
defaults to empty text and `tags` to an empty array of nonempty strings. IDs
are decimal strings. The server owns `id`, `created`, and `updated`; timestamps
are Unix seconds. PUT replaces title, body, and tags and preserves `created`.

| Method | Route | Result |
| --- | --- | --- |
| GET | `/api/notes?tag=work&q=pattern` | Notes matching tag and title/body regex |
| POST | `/api/notes` | Created note, status 201 |
| GET | `/api/notes/:id` | One note, or 404 |
| PUT | `/api/notes/:id` | Updated note, or 404 |
| DELETE | `/api/notes/:id` | `{"deleted":true}`, or 404 |
| GET | `/api/stats` | Note count, title/body bytes, and counts per tag |

```sh
curl -d '{"title":"First note","body":"Hello","tags":["work"]}' \
  http://127.0.0.1:8080/api/notes
curl 'http://127.0.0.1:8080/api/notes?tag=work&q=Hello'
```

Validation and policy failures return status 422 with `{"error":"reason"}`.
The service loads `policy.xlisp` for each mutation. The supplied policy rejects
notes tagged `forbidden` and bodies larger than 65536 bytes. The Lisp function
receives the tags and body and can call the native `body-size` binding. A
missing policy file allows the note. Change the policy without recompiling or
restarting the service.

## Storage and source

`record.x` has one compile-time field table. It generates `struct Note`, the
Map conversion in both directions, field validation, and the SQL column list.
The `match` in its reader generator selects validation by the declared field
type. `service.x` supplies the handlers for either store.

The core `MapStore` serializes access with a Mutex. A mutation writes the full
Map to a sibling temporary file and renames it over the store. A failed write
restores the previous in-memory record. Each stored note owns a private
canonical-value pool through its Map's Scope; replacing or deleting the note
reclaims its text and tags. Reads return request-owned snapshots.

This file store rewrites the complete dataset on each mutation and takes a
snapshot for each read. It is an example for small datasets. The optional
[SQLite variant](../../packages/notes-sqlite/README.md) reuses the handlers and
record table, with prepared statements for persistent operations.

## Check

```sh
make -C examples/apps/notes check
```

`--check` binds loopback port zero, creates three notes, searches, reads tag
counts, exercises validation and the Lisp policy, deletes a note, and removes
its temporary store. The transcript is deterministic. The regular examples
manifest also runs this check.

The optional benchmark is described in [bench/README.md](bench/README.md).
