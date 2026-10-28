# Notes

Create notes, organize them with tags, and search their titles and bodies.
The program serves a browser page and a JSON API. It saves notes in SQLite so
changes survive a restart.

From the repository root, after building x2c:

```sh
make -C examples/apps/notes prepare
make -C examples/apps/notes run
```

The first command prepares the optional SQLite dependency. The second builds
the application and prints its URL. Open <http://127.0.0.1:8080/> to create,
edit, search, tag, and delete notes. Ctrl-C stops the server and closes the
database.

The defaults are loopback port 8080, eight workers, `notes.db`, and this
example's `public` directory. To select another database or address, run the
built executable from the repository root:

```sh
examples/apps/notes/builds/notes --host 127.0.0.1 --port 8081 \
  --workers 8 --store /tmp/my-notes.db --public examples/apps/notes/public
```

Relative paths use the process's working directory. The `--store` path names
an SQLite database. Existing JSON store files remain at their current paths.
The server speaks plain HTTP; use a TLS reverse proxy for deployment.

## API

A note has `id`, `title`, `body`, `tags`, `created`, and `updated` fields.
`title` is required nonempty text. `body` defaults to empty text, and `tags`
defaults to an empty array of nonempty strings. IDs are decimal strings.
The server assigns IDs and Unix timestamps. PUT replaces title, body, and
tags while preserving the creation time.

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

Invalid note fields return status 422 with `{"error":"reason"}`. Malformed
JSON returns status 400. A missing note returns status 404.

## Source and checks

[notes.x](notes.x) contains the request handlers, validation, and database
queries. The [public directory](public/) contains the page and its JavaScript.
Queries use bound parameters. The optional `http.x` module supplies routing,
connection handling, and the worker pool.

After preparing SQLite, run the application checks with:

```sh
make -C examples/apps/notes check
```

The Python checks start the executable against temporary databases and send
HTTP requests. They cover note operations, validation, search, tag counts,
persistence across restart, concurrent creation, and the page. They run
outside the application process. The optional application is separate from
`make examples`, which does not fetch SQLite.

See [bench/README.md](bench/README.md) for the separate read-load tool and its
measurement procedure.
