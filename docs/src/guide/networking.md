# Sockets and HTTP

Networking is optional. Include `net.x` for blocking TCP, or `http.x` for
HTTP/1.1 routing and a server. Both modules ship with the runtime; neither
enters the implicit prelude or `scripting.x`. Use the libuv package when an
application needs an event loop.

## Open a socket

A `Socket` owns two `File` streams: `input` reads and `output` writes.
The streams use separate descriptors because a C update stream cannot safely
switch direction on a socket. Ordinary `File` operations own byte I/O.
Flush `output` when a peer must see buffered data.

```x2c
#include "net.x"

int main(void) {
  Socket peer = auto Socket.connect("127.0.0.1", 8080, 3000);
  peer.set_timeout(5000);
  peer.output.puts("GET / HTTP/1.1\r\nHost: localhost\r\n"
                   "Connection: close\r\n\r\n");
  peer.output.flush();
  String status = peer.input.readline();
  printf("%s", status);
  return 0;
}
```

`Socket.connect` resolves the host, tries its addresses, and uses a timed
nonblocking connect before restoring blocking operation. `set_timeout` sets
receive and send timeouts in milliseconds. A host I/O failure raises
`<io-fail>` with the operation and `errno`; an unresolved host raises
`<not-found>`. Timeout reads normally carry `EAGAIN` or `EWOULDBLOCK`.

`shutdown_write` flushes output and sends EOF in that direction. Reading can
continue until the peer closes its write side. `Socket.close` releases both
streams. `Socket` adopts `Cleanup`, so an `auto` local closes on scope exit.

## Accept connections

```x2c
#include "net.x"

int main(void) {
  Listener listener = auto Listener.bind("127.0.0.1", 0);
  printf("listening on %d\n", listener.port());
  Socket peer = auto listener.accept();
  if (peer) {
    peer.output.puts("hello\n");
    peer.output.flush();
  }
  return 0;
}
```

Port zero asks the host for an available port. A null bind host requests
passive addresses. An IPv6 listener requests dual-stack operation where the
host supports it. Accepted connections use `TCP_NODELAY`.

`Listener.stop` may run on another thread. The accept loop polls every 50 ms
and returns null after a listener stop. A cooperative `Thread.stop` instead
raises the thread cancellation cause. Close the listener only after its
accepting thread has finished.

The first bind or connect ignores `SIGPIPE` process-wide. A write to a
closed peer can then report an I/O error instead of terminating the process.
This also affects other code in the same process.

## Serve HTTP

```x2c
#include "http.x"

int main(void) {
  Router routes = Router.new();
  routes.get("/hello/:name", %!(HttpRequest req, HttpResponse res) => {
    res.json({greeting: req.params["name"]});
  });
  HttpServer server = HttpServer.new(routes, {port: 8080, workers: 8});
  defer server.close();
  server.serve();
  return 0;
}
```

Register routes before starting the server. A handler is an ordinary callable
with an `HttpRequest` and `HttpResponse`; capturing lambdas carry application
state. Shared mutable application data still needs application coordination.

A route pattern matches path segments. `:name` captures one segment;
a final `*rest` captures the remainder. Routes match in registration order
within their method. A missing route gives 404; a known path with another
method gives 405. `get`, `post`, `put`, and `delete` register common methods.

A request holds its method as a lowercase Symbol such as `<get>`, its decoded
`path`, query and header Maps, body String, and captured `params`. Header
names are lowercase. `req.json()` parses the body with `Json.parse`.
Malformed JSON produces a 400 response.

`res.status(code)` selects a status. `header(name, value)` adds a header.
`text`, `json`, and `bytes` fill the response body. JSON responses set
`Content-Type: application/json`; response framing supplies `Content-Length`.
The server buffers the body until the handler returns.

Use `Http.fail(404, "no such note")` for an expected failure. The server
answers with the selected status and `{"error":"no such note"}`. Another
escaping Error produces 500 without exposing its detail. The server logs the
error code and detail at `<error>` level in category `<http>`.

## Limits and connection lifetime

The parser limits a request line to 8 KiB, headers to 64 KiB, and a request
body to 1 MiB by default. Reads enforce the line and header bounds before
accepting more input. Malformed requests give 400, unsupported methods 405,
chunked request bodies 411, oversized bodies 413, and oversized headers 431.
HTTP/1.1 requires `Host`. Transfer-encoding and chunked responses are outside
the server's supported protocol.

HTTP/1.1 keeps a connection unless `Connection: close` is present.
HTTP/1.0 closes unless `Connection: keep-alive` is present. A timeout or
failed read ends the connection. Server options include `host` (default
`"::"`), `port`, `workers` (8), `idle-ms` (5000), `body-limit` (1048576), and
`logger`. For example, use canonical Symbol keys for dashed names:
`{port: 8080, <idle-ms>: 1000}`. The default Logger writes access lines to
stderr at `<info>`.

The acceptor sends descriptors through a bounded `Channel` to a fixed pool
of Threads. The channel bounds queued connections; the kernel backlog holds
additional arrivals. A keep-alive connection occupies one worker while it
waits for another request. Size the pool for the expected persistent clients.

Each request runs inside an isolated `Context`, which reclaims its temporary
collections and text. Store persistent mutable application data in an owner
that outlives the request. Follow [storage ownership](storage-ownership.md)
when sharing or copying values across those lifetimes.

`serve` runs the acceptor on the caller. `start` runs it on a Thread and
returns; `port()` reports the bound port, including a port selected with zero.
`stop` stops acceptance, closes and drains the Channel, joins workers, and
closes the listener. Call `close` after serving to release the Channel and
its default Logger. Workers finish their current connections before joining,
subject to the socket idle timeout. A started acceptor is joined as well.

## Serve files and deploy

`routes.files("/", "public")` registers a static-file fallback. The handler
rejects `..` path segments, serves `index.html` for a directory, and chooses
a content type from the file extension. Keep served files in a dedicated
public directory. File responses are buffered in memory.

Core networking supplies plain TCP. Put a TLS reverse proxy in front of an
HTTP service for deployment. A TLS adapter can instead supply separate
read and write cookie streams through the Socket's File fields; HTTP uses
those streams for all I/O. Creating a TLS package is separate work.

The [notes service](https://github.com/gwf/x2c/tree/dev/examples/apps/notes)
combines routing, JSON, a file-backed store, record generation, and a runtime
Lisp policy. Its `--check` mode runs a deterministic loopback client script.
