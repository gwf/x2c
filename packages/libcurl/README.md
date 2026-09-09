# libcurl client

This experimental package provides an x2c interface to the pinned libcurl
8.22.0 profile. Its entry point is `src/libcurl.x`; one
reusable `CurlEasy` performs bounded synchronous HTTP requests and returns a
copied `CurlResponse` with the status, ordered headers, and body.

```x2c
import "libcurl" with CurlBatch, CurlEasy, CurlResponse;

int main(void) {
  CurlEasy curl = CurlEasy.new().timeouts(1000, 3000);
  defer curl.free();

  CurlResponse response = curl.get(%"https://example.com/guide");
  defer response.free();
  printf("%ld %zu bytes\n", response.response_code(), response.body_size());
  return 0;
}
```

## Requests

`get(url)` is the shorthand; `request(method, url)` sends any other verb.
`HEAD` maps to `CURLOPT_NOBODY`, which libcurl requires and a custom request
string alone does not do. The verb, body, and custom-request options are
reset on every request, so one handle can GET after it POSTed without
carrying anything over.

`body(content_type, content)` sets the body the next request sends, together
with the `Content-Type` header it carries. A body belongs to one transfer:
`request()` sends it and clears it. The bytes are copied here and again by
libcurl, so the caller keeps no obligation.

`body_bytes(content_type, bytes)` is the binary form. It sends every element
the `Bytes` value holds, embedded NUL bytes included, and copies them here.

```x2c
CurlResponse accepted = easy.body(%"application/json", job)
  .request(%"POST", url);
```

`basic_auth(user, password)` sends HTTP Basic credentials on the first
request rather than waiting for a 401 challenge. `header(line)` retains a
request-header line for every later request on the handle. `user_agent`,
`timeouts`, `follow_redirects`, and `max_body` are the other handle settings.

`CurlEasy.escape(value)` and `CurlEasy.unescape(value)` percent-encode and
decode one URL component without needing a handle at all. A decoded value
containing NUL raises `<bad-enc>`, because the result would not be a String.

## Concurrent batches

`easy.get_all(urls, maximum)` performs a bounded batch of GET requests;
`easy.request_all(method, urls, maximum)` supplies another method. Both wait
for every transfer on the caller's thread. `maximum` must be positive;
at most that many duplicate easy handles perform transfers at once.

```x2c
List urls = %("https://example.com/guide" "https://example.com/reference");
CurlBatch batch = easy.get_all(urls, 2);
defer batch.free();
for (int i = 0; i < batch.len(); i++) {
  try {
    CurlResponse response = batch.response(i);
    printf("%ld %s\n", response.response_code(), response.effective_url());
  }
  catch %(io-fail *detail): printf("%s\n", detail.repr());
}
```

Results keep input order even when completion order differs. A transfer
failure is retained independently: `batch.response(i)` re-raises its Error
with the original cause and details, while other responses remain available.
Batch transfer Errors name `multi_info_read` as their operation; native
setup and multi-driver failures name the failing native call. HTTP error
status codes are ordinary responses. The batch owns its responses;
returned pointers and body views are borrowed until `batch.free()`. Do not
free them separately. Freeing the original easy handle after the batch
returns does not invalidate the results. Each body has the template's
`max_body` limit; the batch retains all completed bodies until freed.

The easy handle's configured options, including raw options set through
`native()`, are duplicated. Borrowed option data must stay valid throughout
the call. [`curl_easy_duphandle`](https://curl.se/libcurl/c/curl_easy_duphandle.html)
does not copy connection, cookie, SSL-session,
or share-handle state. The temporary pool reuses connections within a batch;
the template's original connection is not transferred to it. Do not use or
modify the template during the call. Its pending body is copied to every URL
and cleared when the call ends, including on failure or an empty batch.

A multi-driver error raises from the batch call after detaching and releasing
all active native handles. Transfer callbacks use the same collectors and
error containment as individual requests. The pinned synchronous resolver
can still block DNS lookup; a batch is not an event loop or background worker.
Native multi/socket APIs remain available for those integrations.

## The native handle

`easy.native()` returns the `CURL *` this wrapper owns, so every libcurl
option, info, and operation the ordinary methods do not cover applies to the
same handle the next request performs:

```x2c
curl_easy_setopt(easy.native(), CURLOPT_COOKIEFILE, "");
CurlResponse response = easy.get(url);
```

The wrapper keeps ownership. Do not call `curl_easy_cleanup` on it, and do
not set the error buffer, which the wrapper reads for every `<io-fail>` it
raises. Calling `native()` after `free()` raises `<bad-arg>`.

Every transfer clears the options it set on the way out - the request header
list, both write and header callbacks, and both callback contexts - so a
finished handle is back at libcurl's own defaults for those five. A caller
may therefore perform on it directly with its own callbacks, and the next
ordinary request sets them again for itself:

```x2c
CURL *handle = easy.native();
curl_easy_setopt(handle, CURLOPT_URL, url);
curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, collect);
curl_easy_setopt(handle, CURLOPT_WRITEDATA, &collected);
CURLcode code = curl_easy_perform(handle);
```

## Response data

HTTP status is response data, not a transfer Error. A 404 returns a
`CurlResponse`, as does an empty 204. Transport failures raise `<io-fail>`
with the libcurl operation, `CURLcode`, error-buffer or `curl_easy_strerror`
message, requested URL, response code, and effective URL when available.

`response.body()` returns response-owned `Bytes` for read-only use until
`response.free()`. Callers must not free or resize it, or retain it past
release. `response.text()` is an explicit conversion to `String` and rejects
embedded NUL. `response.body_size()` is the body byte count either way.

`response.elapsed_us()` and `response.upload_size()` are libcurl's own
measurements of the exchange, captured when the response is built, so they
survive the handle being reused.

Each response block keeps its status line and an ordered List of
`CurlHeader` values, so redirects, duplicate fields, and empty fields remain
visible. `block.values(name)` is case-insensitive and returns every value in
order: an empty List means the name is missing, and a one-element List whose
value is the empty String means the header was present and empty.

HTTP/1.1 chunked trailers are appended to the final response block's header
List. Their order is preserved, but the converted value does not distinguish
a trailer from an ordinary header with the same name.

Every response is copied and remains valid after another transfer reuses the
easy handle. `CurlResponse.free` releases its body and is idempotent. Access
after release raises `<bad-state>`.

## Streaming and downloading

`stream(url, data, consume)` performs a GET and passes copied body chunks to
`consume(chunk, data)` as they arrive. Each chunk is read-only and valid only
during that callback; the `Var` data belongs to the caller and makes callback
state explicit. A callback Error is caught before control returns to libcurl,
copied, and re-raised after `curl_easy_perform` returns. The response retains
status, headers, timing, and the body byte count, but `body()` and `text()`
raise `<bad-state>` because no complete body was retained.

`download(url, path)` performs a GET whose body is written straight to
`path` as it arrives. Nothing is buffered, so `max_body` does not apply and
the transfer can exceed memory. The status, headers, and `body_size()`
describe it as usual, but `body()` and `text()` raise `<bad-state>` because
the bytes are in the file rather than in the response. A failed transfer
leaves the partial file behind for the caller to remove.

## Lisp

`CurlLisp.install(lisp)` adds `http-get`, `http-post`, `http-status`,
`http-headers`, and `url-escape` to a ready Lisp session. The bindings are
part of the package, so importing it is enough.

The surface is value-oriented on purpose. Every binding takes and returns
`String`, `List`, and `int`, and each owns and frees its own `CurlEasy` and
`CurlResponse` inside the call, so no native handle and no borrowed storage
ever enters a session. A program that needs a reused connection, its own
timeouts, or the raw handle stays in x2c. A transport failure raises out of
the binding as the same `<io-fail>` an x2c caller would see, while an HTTP
status stays an ordinary returned value.

`examples/inline-lisp.x` (`make lisp-example`) drives that surface: Lisp
measures and slices a returned body, does arithmetic on a returned status,
counts a returned header List, and composes `url-escape` into the next
request.

## Applications

`examples/page-titles.x` is the short application (`make short-example`). It
fetches three pages concurrently, then prints each title in input order. The
batch owns all response cleanup beside its acquisition. Its fixture output is:

```text
guide: x2c Language Guide
reference: x2c Reference
source: x2c Source
```

`examples/endpoint-report.x` is the broader one (`make example`). It surveys
a service with a concurrent GET batch and a HEAD request, reports each
response against a latency budget, shows the response blocks a redirect
leaves behind, handles the body-limit
and transport-failure paths, submits a JSON job with `POST`, reads a
credentials-protected path, round-trips a percent-encoded search term,
streams an artifact through an x2c callback, and downloads it straight to
disk.

`examples/packages/http-json-releases` is the two-package composition:
libcurl fetches the bytes and yyjson parses them.

## Callbacks and reuse

Callbacks run synchronously on the caller's thread. The internal collectors
use only native integer checks, `realloc`, `memcpy`, and `fwrite`. The public
stream callback receives copied `Bytes`; any Error is caught at the callback
edge and re-raised after `curl_easy_perform` returns. No Error can unwind
through libcurl.

One easy handle supports sequential transfers and connection reuse. It is
not reentrant and must not be used concurrently. The synchronous resolver
may block; `CURLOPT_NOSIGNAL=1` does not make DNS timeout reliable in this
standard-resolver profile.

## Native API and deliberate limits

`src/curl-822.h` includes the real pinned upstream header and rejects
another libcurl version. The complete API admitted by the static profile
remains available under upstream names, and the generated package header
publishes it, so a consumer that only says `import "libcurl"` can call
`curl_url_set` or `curl_version_info` directly.

Uploads from a stream, socket-driven transfers, WebSockets, share
handles, cookies, TLS configuration, custom allocators, and native
worker-thread entry stay on the raw surface, reached through
`easy.native()` on the same handle.

## Build and test

`make prepare` downloads, verifies, and builds the pinned static profile in
the shared integration cache. `make build` produces `builds/liblibcurl.a`
and the generated package headers. `make run` and `make test` prepare it
automatically when absent and reuse it when present. Set `X2C_DEPS_DIR` to
move the shared cache, or `CURL_PREFIX` and `OPENSSL_PREFIX` to diagnose
another compatible installation.

```sh
make verify-profile
make test
make run
make run-lisp
```

The applications and tests talk only to the package-local HTTP fixture
started by `tools/run-fixture.py`. They do not depend on the public network.
libcurl and OpenSSL retain the exact terms under `LICENSES/`; see
`../LICENSE-POLICY.md` for the project intake policy.
