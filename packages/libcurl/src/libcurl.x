/*  libcurl.x -- bounded synchronous libcurl easy transfers for x2c programs.

    CurlEasy owns one reusable native easy handle and publishes it through
    `easy.native()`, so every libcurl option the ordinary methods do not
    cover stays reachable on the same handle the next request performs.
 */

#include "curl-822.h"

typedef struct CurlEasy *CurlEasy;
typedef struct CurlResponse *CurlResponse;
typedef List CurlHeader;
typedef List CurlResponseBlock;
typedef void (*CurlStreamFn)(Bytes, Var);

typedef enum CurlLisp {
  CURLLISP_NAMESPACE
} CurlLisp;

#pragma private

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef enum CurlBufferFailure {
  CURL_BUFFER_OK,
  CURL_BUFFER_LIMIT,
  CURL_BUFFER_ALLOC,
  CURL_BUFFER_SIZE
} CurlBufferFailure;

typedef struct CurlBuffer {
  unsigned char *bytes;
  size_t length;
  size_t capacity;
  size_t limit;
  size_t attempted;
  CurlBufferFailure failure;
} CurlBuffer;

/*  A download writes the body straight to this stream instead of growing a
    CurlBuffer, so the transfer is not bounded by the in-memory body limit.
*/
typedef struct CurlSink {
  File file;
  size_t written;
  int failed;
} CurlSink;

/*  A streaming callback receives one copied chunk at a time. Any Error it
    raises is caught before control returns to libcurl and reported after the
    transfer has unwound back into x2c. */
typedef struct CurlStream {
  CurlStreamFn consume;
  Var data;
  size_t written;
  Symbol cause;
  List detail;
} CurlStream;

struct CurlEasy {
  CURL *native;
  String url;
  String user_agent;
  String content_type;
  Bytes request_body;
  size_t request_body_size;
  struct curl_slist *headers;
  size_t body_limit;
  int performing;
  char error[CURL_ERROR_SIZE];
};

struct CurlResponse {
  long response_code;
  long elapsed_us;
  long upload_size;
  String effective_url;
  String file;
  List blocks;
  Bytes body;
  size_t body_size;
  int streamed;
  int released;
};

static size_t _curl_collect(
  char *data, size_t size, size_t count, void *context) {
  CurlBuffer *buffer = context;
  if (!buffer || buffer.failure) return 0;
  if (size && count > SIZE_MAX / size) {
    buffer.failure = CURL_BUFFER_SIZE;
    return 0;
  }
  size_t length = size * count;
  if (!length) return 0;
  if (buffer.length > buffer.limit || length > buffer.limit - buffer.length) {
    buffer.failure = CURL_BUFFER_LIMIT;
    buffer.attempted = length;
    return 0;
  }

  size_t required = buffer.length + length;
  if (required > buffer.capacity) {
    size_t capacity = buffer.capacity ? buffer.capacity : 4096;
    if (capacity > buffer.limit) capacity = buffer.limit;
    while (capacity < required) {
      if (capacity > buffer.limit / 2) {
        capacity = buffer.limit;
        break;
      }
      capacity *= 2;
    }
    if (capacity < required) {
      buffer.failure = CURL_BUFFER_SIZE;
      return 0;
    }
    unsigned char *bytes = realloc(buffer.bytes, capacity);
    if (!bytes) {
      buffer.failure = CURL_BUFFER_ALLOC;
      buffer.attempted = capacity;
      return 0;
    }
    buffer.bytes = bytes;
    buffer.capacity = capacity;
  }
  memcpy(buffer.bytes + buffer.length, data, length);
  buffer.length = required;
  return length;
}

/*  The download write callback, native like _curl_collect: stdio only, no
    x2c allocation and no Error can unwind through libcurl.
*/
static size_t _curl_spill(
  char *data, size_t size, size_t count, void *context) {
  CurlSink *sink = context;
  if (!sink || sink.failed) return 0;
  if (size && count > SIZE_MAX / size) {
    sink.failed = 1;
    return 0;
  }
  size_t length = size * count;
  if (!length) return 0;
  if (fwrite(data, 1, length, sink.file) != length) {
    sink.failed = 1;
    return 0;
  }
  sink.written += length;
  return length;
}

static size_t _curl_stream(
  char *data, size_t size, size_t count, void *context) {
  CurlStream *stream = context;
  if (!stream || !stream.consume || stream.cause) return 0;
  if (size && count > SIZE_MAX / size) {
    stream.cause = <size-limit>;
    return 0;
  }
  size_t length = size * count;
  if (!length) return 0;
  try {
    Bytes chunk = Bytes.new(1).append(data, length);
    defer chunk.free();
    stream.consume(chunk, stream.data);
  }
  catch %(?cause *detail): {
    stream.cause = cause;
    try stream.detail = Error.snapshot(detail);
    catch %(?snapcause *): {
      stream.cause = snapcause;
      stream.detail = NULL;
    }
    return 0;
  }
  stream.written += length;
  return length;
}

static void _curl_raise(CurlEasy easy, String operation, CURLcode code) {
  String message = easy && easy.error[0]
    ? String.new(easy.error) : String.new(curl_easy_strerror(code));
  String url = easy ? easy.url : NULL;
  long response_code = 0;
  char *native_url = NULL;
  if (easy && easy.native) {
    curl_easy_getinfo(easy.native, CURLINFO_RESPONSE_CODE, &response_code);
    curl_easy_getinfo(easy.native, CURLINFO_EFFECTIVE_URL, &native_url);
  }
  String effective_url = native_url ? String.new(native_url) : NULL;
  int native_code = (int) code;
  raise %(io-fail (library "libcurl") (operation $operation)
          (code $native_code) (message $message) (url $url)
          (http-code $response_code)
          (final-url $effective_url));
}

static void _curl_check(CurlEasy easy, String operation, CURLcode result) {
  if (result != CURLE_OK) _curl_raise(easy, operation, result);
}

static void _curl_getinfo(CurlEasy easy, CURLINFO info, void *out) {
  CURLcode result = curl_easy_getinfo(easy.native, info, out);
  if (result != CURLE_OK) _curl_raise(easy, %"easy_getinfo", result);
}

static void _curl_add_header(struct curl_slist **list, String line) {
  struct curl_slist *grown = curl_slist_append(*list, line);
  if (!grown) {
    raise %(alloc-fail (library "libcurl") (operation "slist_append"));
  }
  *list = grown;
}

/*  A request body belongs to one transfer, so the pending body clears here
    whether the transfer completed or raised. So does everything the transfer
    pointed the handle at: the header list `_curl_perform` is about to free,
    and the two callback pairs, whose contexts end with that frame. libcurl
    keeps the slist pointer without copying it and calls a write callback
    with whatever context it was last given, so leaving any of the five set
    would hand `curl_easy_perform(easy.native())` a freed list or a callback
    that aborts the transfer. NULL restores curl's own defaults for the two
    callbacks; CURLOPT_WRITEDATA returns to stdout, which is where curl's
    default fwrite writes when a caller sets no context of its own.
*/
static void _curl_transfer_end(CurlEasy easy) {
  if (!easy) return;
  easy.content_type = NULL;
  if ((void *) easy.request_body != NULL) easy.request_body.free();
  easy.request_body = NULL;
  easy.request_body_size = 0;
  easy.performing = 0;
  if (!easy.native) return;
  curl_easy_setopt(easy.native, CURLOPT_HTTPHEADER, NULL);
  curl_easy_setopt(easy.native, CURLOPT_WRITEFUNCTION, NULL);
  curl_easy_setopt(easy.native, CURLOPT_WRITEDATA, stdout);
  curl_easy_setopt(easy.native, CURLOPT_HEADERFUNCTION, NULL);
  curl_easy_setopt(easy.native, CURLOPT_HEADERDATA, NULL);
}

static void _curl_buffer_failure(
  CurlEasy easy, CurlBuffer *buffer, String channel) {
  size_t limit = buffer.limit, attempted = buffer.attempted;
  if (buffer.failure == CURL_BUFFER_LIMIT) {
    raise %(size-limit (library "libcurl") (operation "easy_perform")
            (channel $channel) (limit $limit) (attempted $attempted)
            (url ${easy.url}));
  }
  if (buffer.failure == CURL_BUFFER_ALLOC) {
    raise %(alloc-fail (library "libcurl")
            (operation "easy_perform") (channel $channel)
            (attempted $attempted) (url ${easy.url}));
  }
  raise %(size-limit (library "libcurl") (operation "easy_perform")
          (channel $channel) (reason "callback size overflow")
          (url ${easy.url}));
}

static String _curl_header_text(
  const unsigned char *bytes, size_t length, String operation) {
  if (length > INT_MAX) {
    raise %(size-limit (library "libcurl") (operation $operation)
            (length $length));
  }
  if (length && memchr(bytes, '\0', length)) {
    raise %(bad-enc (library "libcurl") (operation $operation)
            (reason "HTTP header contains NUL"));
  }
  return String.new_len((char *) bytes, (int) length);
}

static CurlHeader _curl_header(String line) {
  int length = line.len(), colon = -1;
  for (int i = 0; i < length; i++) {
    if (line[i] == ':') {
      colon = i;
      break;
    }
  }
  int parsed = colon > 0;
  String name = NULL, value = NULL;
  if (parsed) {
    name = String.new_len(line, colon);
    int start = colon + 1;
    while (start < length &&
           (line[start] == ' ' || line[start] == '\t')) start++;
    value = String.new_len(line + start, length - start);
  }
  return %($line $parsed $name $value);
}

static CurlResponseBlock _curl_block(String status, List headers) {
  return %($status ${headers.reverse()});
}

static int _curl_status_line(String line) {
  return line.len() >= 5 && !memcmp(line, "HTTP/", 5);
}

static List _curl_blocks(const unsigned char *bytes, size_t length) {
  List blocks = NULL, headers = NULL;
  String status = NULL;
  size_t start = 0;

  for (size_t i = 0; i <= length; i++) {
    if (i < length && bytes[i] != '\n') continue;
    size_t stop = i;
    if (stop > start && bytes[stop - 1] == '\r') stop--;
    size_t line_length = stop - start;
    if (line_length) {
      String line = _curl_header_text(bytes + start, line_length, %"headers");
      if (_curl_status_line(line)) {
        if (status) blocks = cons(_curl_block(status, headers), blocks);
        status = line;
        headers = NULL;
      }
      else if (!status) status = line;
      else headers = cons(_curl_header(line), headers);
    }
    start = i + 1;
  }
  if (status) blocks = cons(_curl_block(status, headers), blocks);
  return blocks.reverse();
}

CurlEasy CurlEasy.new(void) {
  CurlEasy easy = Scope.calloc(1, sizeof(struct CurlEasy));
  easy.native = curl_easy_init();
  if (!easy.native) {
    raise %(alloc-fail (library "libcurl") (operation "easy_init"));
  }
  CurlEasy completed = NULL;
  defer if (!completed) easy.free();
  easy.body_limit = 1024 * 1024;
  _curl_check(easy, %"CURLOPT_ERRORBUFFER",
    curl_easy_setopt(easy.native, CURLOPT_ERRORBUFFER, easy.error));
  _curl_check(easy, %"CURLOPT_NOSIGNAL",
    curl_easy_setopt(easy.native, CURLOPT_NOSIGNAL, 1L));
  _curl_check(easy, %"CURLOPT_PROTOCOLS_STR",
    curl_easy_setopt(easy.native, CURLOPT_PROTOCOLS_STR, "http,https"));
  _curl_check(easy, %"CURLOPT_REDIR_PROTOCOLS_STR",
    curl_easy_setopt(easy.native, CURLOPT_REDIR_PROTOCOLS_STR, "http,https"));
  _curl_check(easy, %"CURLOPT_USERAGENT",
    curl_easy_setopt(easy.native, CURLOPT_USERAGENT, "x2c-libcurl/2"));
  return completed = easy;
}

/** Returns the native easy handle this wrapper owns.
    Every libcurl option, info, and operation the ordinary methods do not
    cover applies to this handle and takes effect on the next request. The
    wrapper keeps ownership: do not call `curl_easy_cleanup` on it, and do
    not set the write, header, or error-buffer options it manages.
*/
CURL *CurlEasy.native(CurlEasy easy) {
  if (!easy || !easy.native) {
    raise %(bad-arg (library "libcurl") (operation "native"));
  }
  return easy.native;
}

CurlEasy CurlEasy.free(CurlEasy easy) {
  if (!easy) return NULL;
  if (easy.performing) {
    raise %(bad-state (library "libcurl") (operation "easy_cleanup")
            (reason "easy handle is performing a transfer"));
  }
  if (easy.native) {
    curl_easy_cleanup(easy.native);
    easy.native = NULL;
  }
  if (easy.headers) {
    curl_slist_free_all(easy.headers);
    easy.headers = NULL;
  }
  if ((void *) easy.request_body != NULL) {
    easy.request_body.free();
    easy.request_body = NULL;
    easy.request_body_size = 0;
  }
  return NULL;
}

CurlEasy CurlEasy.timeouts(CurlEasy easy, long connect_ms, long total_ms) {
  if (!easy || !easy.native || connect_ms <= 0 || total_ms <= 0) {
    raise %(bad-arg (library "libcurl") (operation "timeouts"));
  }
  _curl_check(easy, %"CURLOPT_CONNECTTIMEOUT_MS",
    curl_easy_setopt(easy.native, CURLOPT_CONNECTTIMEOUT_MS, connect_ms));
  _curl_check(easy, %"CURLOPT_TIMEOUT_MS",
    curl_easy_setopt(easy.native, CURLOPT_TIMEOUT_MS, total_ms));
  return easy;
}

CurlEasy CurlEasy.follow_redirects(CurlEasy easy, long maximum) {
  if (!easy || !easy.native || maximum < 0) {
    raise %(bad-arg (library "libcurl") (operation "follow_redirects"));
  }
  _curl_check(easy, %"CURLOPT_FOLLOWLOCATION",
    curl_easy_setopt(easy.native, CURLOPT_FOLLOWLOCATION, maximum ? 1L : 0L));
  _curl_check(easy, %"CURLOPT_MAXREDIRS",
    curl_easy_setopt(easy.native, CURLOPT_MAXREDIRS, maximum));
  return easy;
}

CurlEasy CurlEasy.max_body(CurlEasy easy, size_t maximum) {
  if (!easy || !easy.native || !maximum) {
    raise %(bad-arg (library "libcurl") (operation "max_body"));
  }
  easy.body_limit = maximum;
  return easy;
}

CurlEasy CurlEasy.user_agent(CurlEasy easy, String value) {
  if (!easy || !easy.native || !value) {
    raise %(bad-arg (library "libcurl") (operation "user_agent"));
  }
  easy.user_agent = value.intern();
  _curl_check(easy, %"CURLOPT_USERAGENT",
    curl_easy_setopt(easy.native, CURLOPT_USERAGENT, easy.user_agent));
  return easy;
}

/** Retains one request-header line for every later request on this handle. */
CurlEasy CurlEasy.header(CurlEasy easy, String line) {
  if (!easy || !easy.native || !line) {
    raise %(bad-arg (library "libcurl") (operation "header"));
  }
  _curl_add_header(&easy.headers, line);
  return easy;
}

/** Sends `user` and `password` as HTTP Basic credentials.
    libcurl copies both values and offers them on the first request rather
    than waiting for a 401 challenge.
*/
CurlEasy CurlEasy.basic_auth(CurlEasy easy, String user, String password) {
  if (!easy || !easy.native || !user || !password) {
    raise %(bad-arg (library "libcurl") (operation "basic_auth"));
  }
  _curl_check(easy, %"CURLOPT_HTTPAUTH",
    curl_easy_setopt(easy.native, CURLOPT_HTTPAUTH, (long) CURLAUTH_BASIC));
  _curl_check(easy, %"CURLOPT_USERNAME",
    curl_easy_setopt(easy.native, CURLOPT_USERNAME, user));
  _curl_check(easy, %"CURLOPT_PASSWORD",
    curl_easy_setopt(easy.native, CURLOPT_PASSWORD, password));
  return easy;
}

static CurlEasy _curl_set_body(
  CurlEasy easy, String content_type, const void *content, size_t length,
  String operation) {
  if (!easy || !easy.native || !content_type || (!content && length)) {
    raise %(bad-arg (library "libcurl") (operation $operation));
  }
  String copied_type = String.new(content_type);
  Bytes copied_body = Bytes.new(1).append(content, length);
  if ((void *) easy.request_body != NULL) easy.request_body.free();
  easy.content_type = copied_type;
  easy.request_body = copied_body;
  easy.request_body_size = length;
  return easy;
}

/** Sets the String body the next request sends and its `Content-Type`.
    A body belongs to one transfer: the next `request()` sends it and clears
    it, so a later `get()` on the same handle carries no body. The bytes are
    copied here and again by libcurl, so the caller keeps no obligation.
*/
CurlEasy CurlEasy.body(CurlEasy easy, String content_type, String content) {
  if (!content) {
    raise %(bad-arg (library "libcurl") (operation "body"));
  }
  return _curl_set_body(easy, content_type, content, content.len(), %"body");
}

/** Sets an arbitrary byte body for the next request and its `Content-Type`.
    Embedded NUL bytes are preserved. The bytes are copied immediately.
*/
CurlEasy CurlEasy.body_bytes(
  CurlEasy easy, String content_type, Bytes content) {
  if ((void *) content == NULL) {
    raise %(bad-arg (library "libcurl") (operation "body_bytes"));
  }
  Block block = content;
  return _curl_set_body(
    easy, content_type, content, block.width * block.length, %"body_bytes"
  );
}

/** Percent-encodes `value` for use inside one URL component.
    libcurl escapes everything outside the unreserved set, so the result is
    safe as a path segment or a query value.
*/
String CurlEasy.escape(String value) {
  if (!value) {
    raise %(bad-arg (library "libcurl") (operation "escape"));
  }
  char *escaped = curl_easy_escape(NULL, value, 0);
  if (!escaped) {
    raise %(alloc-fail (library "libcurl") (operation "easy_escape"));
  }
  defer curl_free(escaped);
  return String.new(escaped);
}

/** Decodes one percent-encoded URL component.
    A sequence that decodes to an embedded NUL raises `<bad-enc>`, because
    the result would not be a String.
*/
String CurlEasy.unescape(String value) {
  if (!value) {
    raise %(bad-arg (library "libcurl") (operation "unescape"));
  }
  int length = 0;
  char *plain = curl_easy_unescape(NULL, value, 0, &length);
  if (!plain) {
    raise %(alloc-fail (library "libcurl") (operation "easy_unescape"));
  }
  defer curl_free(plain);
  if (memchr(plain, '\0', length)) {
    raise %(bad-enc (library "libcurl") (operation "unescape")
            (reason "decoded value contains NUL"));
  }
  return String.new_len(plain, length);
}

/*  Every transfer runs through here. `path` and `consume` select the two
    unbuffered sinks; otherwise the body grows in memory under the handle's
    limit. The verb options are all reset per request, because one handle
    performs many requests and libcurl retains what it was told.
*/
static CurlResponse _curl_perform(
  CurlEasy easy, String method, String url, String path, CurlStreamFn consume,
  Var stream_data) {
  if (!easy || !easy.native || !method || !url) {
    raise %(bad-arg (library "libcurl") (operation "request"));
  }
  if (easy.performing) {
    raise %(bad-state (library "libcurl") (operation "easy_perform")
            (reason "easy handle is not reentrant"));
  }

  easy.performing = 1;
  defer _curl_transfer_end(easy);
  easy.url = url.intern();
  easy.error[0] = '\0';
  String content_type = easy.content_type;
  Bytes request_body = easy.request_body;
  size_t request_body_size = easy.request_body_size;
  int bodyless = !strcmp(method, "GET") || !strcmp(method, "HEAD");

  CurlBuffer body = { .limit = easy.body_limit };
  CurlBuffer headers = { .limit = 256 * 1024 };
  defer free(body.bytes);
  defer free(headers.bytes);
  CurlSink sink = { .file = path ? File.open(path, "wb") : NULL };
  defer if (sink.file) fclose(sink.file);
  CurlStream stream = { .consume = consume, .data = stream_data };

  struct curl_slist *request_headers = NULL;
  defer curl_slist_free_all(request_headers);
  for (struct curl_slist *node = easy.headers; node; node = node->next)
    _curl_add_header(&request_headers, node->data);
  if (content_type)
    _curl_add_header(&request_headers, %"Content-Type: $content_type");

  _curl_check(easy, %"CURLOPT_URL",
    curl_easy_setopt(easy.native, CURLOPT_URL, easy.url));
  _curl_check(easy, %"CURLOPT_POSTFIELDS",
    curl_easy_setopt(easy.native, CURLOPT_POSTFIELDS, NULL));
  _curl_check(easy, %"CURLOPT_HTTPGET",
    curl_easy_setopt(easy.native, CURLOPT_HTTPGET, 1L));
  _curl_check(easy, %"CURLOPT_NOBODY",
    curl_easy_setopt(easy.native, CURLOPT_NOBODY,
                     !strcmp(method, "HEAD") ? 1L : 0L));
  _curl_check(easy, %"CURLOPT_CUSTOMREQUEST",
    curl_easy_setopt(easy.native, CURLOPT_CUSTOMREQUEST,
                     bodyless ? NULL : (const char *) method));
  if (request_body) {
    _curl_check(easy, %"CURLOPT_POSTFIELDSIZE_LARGE",
      curl_easy_setopt(easy.native, CURLOPT_POSTFIELDSIZE_LARGE,
                       (curl_off_t) request_body_size));
    _curl_check(easy, %"CURLOPT_COPYPOSTFIELDS",
      curl_easy_setopt(easy.native, CURLOPT_COPYPOSTFIELDS,
                       (const char *) request_body));
  }
  _curl_check(easy, %"CURLOPT_HTTPHEADER",
    curl_easy_setopt(easy.native, CURLOPT_HTTPHEADER, request_headers));
  _curl_check(easy, %"CURLOPT_WRITEFUNCTION",
    curl_easy_setopt(easy.native, CURLOPT_WRITEFUNCTION,
                     path ? _curl_spill : consume ? _curl_stream
                                                : _curl_collect));
  _curl_check(easy, %"CURLOPT_WRITEDATA",
    curl_easy_setopt(easy.native, CURLOPT_WRITEDATA,
                     path ? (void *) &sink : consume ? (void *) &stream
                                                    : (void *) &body));
  _curl_check(easy, %"CURLOPT_HEADERFUNCTION",
    curl_easy_setopt(easy.native, CURLOPT_HEADERFUNCTION, _curl_collect));
  _curl_check(easy, %"CURLOPT_HEADERDATA",
    curl_easy_setopt(easy.native, CURLOPT_HEADERDATA, &headers));

  CURLcode result = curl_easy_perform(easy.native);
  if (body.failure) _curl_buffer_failure(easy, &body, %"body");
  if (headers.failure) _curl_buffer_failure(easy, &headers, %"headers");
  if (sink.failed || (sink.file && fflush(sink.file))) {
    raise %(io-fail (library "libcurl") (operation "download")
            (reason "writing the response body failed") (path $path)
            (url ${easy.url}));
  }
  if (stream.cause) {
    Symbol cause = stream.cause;
    Error.raise(cause, stream.detail);
  }
  if (result != CURLE_OK) _curl_raise(easy, %"easy_perform", result);

  CurlResponse response = Scope.calloc(1, sizeof(struct CurlResponse));
  CurlResponse completed = NULL;
  defer if (!completed) response.free();
  response.file = path ? path.intern() : NULL;
  response.streamed = consume != NULL;
  if (!path && !consume)
    response.body = Bytes.new(1).append(body.bytes, body.length);
  response.body_size = path ? sink.written
                     : consume ? stream.written : body.length;
  response.blocks = _curl_blocks(headers.bytes, headers.length);

  char *effective_url = NULL;
  curl_off_t elapsed = 0, uploaded = 0;
  _curl_getinfo(easy, CURLINFO_RESPONSE_CODE, &response.response_code);
  _curl_getinfo(easy, CURLINFO_EFFECTIVE_URL, &effective_url);
  _curl_getinfo(easy, CURLINFO_TOTAL_TIME_T, &elapsed);
  _curl_getinfo(easy, CURLINFO_SIZE_UPLOAD_T, &uploaded);
  response.effective_url = String.new(effective_url);
  response.elapsed_us = (long) elapsed;
  response.upload_size = (long) uploaded;
  return completed = response;
}

/** Performs `method` against `url` and returns the complete response.
    A body set by `body()` is sent with this request and then cleared.
    `HEAD` suppresses the response body, as libcurl needs it to; any other
    method is sent as written.
*/
CurlResponse CurlEasy.request(CurlEasy easy, String method, String url) {
  return _curl_perform(easy, method, url, NULL, NULL, void);
}

/** Performs a GET and buffers the body under the handle's `max_body`. */
CurlResponse CurlEasy.get(CurlEasy easy, String url) {
  return _curl_perform(easy, %"GET", url, NULL, NULL, void);
}

/** Performs a GET and passes copied body chunks to `consume` as they arrive.
    Each Bytes value is read-only and valid only for that callback. An Error
    raised by the callback is caught before returning to libcurl and re-raised
    after the transfer returns to x2c. The response retains
    status, headers, timing, and the streamed byte count, but not its body.
*/
CurlResponse CurlEasy.stream(
  CurlEasy easy, String url, Var data, CurlStreamFn consume) {
  if (!consume) {
    raise %(bad-arg (library "libcurl") (operation "stream"));
  }
  return _curl_perform(easy, %"GET", url, NULL, consume, data);
}

/** Performs a GET whose body is written straight to `path` as it arrives.
    Nothing is buffered, so `max_body` does not apply and the transfer can
    exceed memory. The status, headers, and `body_size()` describe it as
    usual, but `body()` and `text()` raise `<bad-state>` because the bytes
    are in the file. A failed transfer leaves the partial file behind.
*/
CurlResponse CurlEasy.download(CurlEasy easy, String url, String path) {
  if (!path) {
    raise %(bad-arg (library "libcurl") (operation "download"));
  }
  return _curl_perform(easy, %"GET", url, path, NULL, void);
}

static void _curl_response_live(CurlResponse response, String operation) {
  if (response && !response.released) return;
  raise %(bad-state (library "libcurl") (operation $operation)
          (reason "released or null response"));
}

static void _curl_response_buffered(CurlResponse response, String operation) {
  _curl_response_live(response, operation);
  if (!response.file && !response.streamed) return;
  if (response.file) {
    raise %(bad-state (library "libcurl") (operation $operation)
            (reason "response body was written to a file")
            (path ${response.file}));
  }
  raise %(bad-state (library "libcurl") (operation $operation)
          (reason "response body was passed to a callback"));
}

CurlResponse CurlResponse.free(CurlResponse response) {
  if (!response || response.released) return NULL;
  if ((void *) response.body != NULL) {
    response.body.free();
    response.body = NULL;
  }
  response.released = 1;
  return NULL;
}

long CurlResponse.response_code(CurlResponse response) {
  _curl_response_live(response, %"response_code");
  return response.response_code;
}

String CurlResponse.effective_url(CurlResponse response) {
  _curl_response_live(response, %"effective_url");
  return response.effective_url;
}

List CurlResponse.blocks(CurlResponse response) {
  _curl_response_live(response, %"blocks");
  return response.blocks;
}

/** Returns the microseconds libcurl measured for the whole transfer. */
long CurlResponse.elapsed_us(CurlResponse response) {
  _curl_response_live(response, %"elapsed_us");
  return response.elapsed_us;
}

/** Returns the request-body bytes libcurl counted as sent. */
long CurlResponse.upload_size(CurlResponse response) {
  _curl_response_live(response, %"upload_size");
  return response.upload_size;
}

/** Returns response-owned Bytes for read-only use until `response.free()`.
    Callers must not free, resize, or retain the storage beyond that point.
*/
Bytes CurlResponse.body(CurlResponse response) {
  _curl_response_buffered(response, %"body");
  return response.body;
}

/** Returns the body bytes received, whether buffered or written to a file. */
size_t CurlResponse.body_size(CurlResponse response) {
  _curl_response_live(response, %"body_size");
  return response.body_size;
}

String CurlResponse.text(CurlResponse response) {
  _curl_response_buffered(response, %"text");
  size_t length = response.body_size;
  if (length && memchr(response.body, '\0', length)) {
    raise %(bad-enc (library "libcurl") (operation "text")
            (reason "response body contains NUL; use body()"));
  }
  if (length > INT_MAX) {
    raise %(size-limit (library "libcurl") (operation "text")
            (length $length));
  }
  return String.new_len(response.body, (int) length);
}

String CurlHeader.line(CurlHeader header) {
  return header ? header.getindex(0).string() : NULL;
}

int CurlHeader.parsed(CurlHeader header) {
  return header && header.getindex(1).truth();
}

String CurlHeader.name(CurlHeader header) {
  return header && header.parsed() ? header.getindex(2).string() : NULL;
}

String CurlHeader.value(CurlHeader header) {
  return header && header.parsed() ? header.getindex(3).string() : NULL;
}

String CurlResponseBlock.status_line(CurlResponseBlock block) {
  return block ? block.getindex(0).string() : NULL;
}

List CurlResponseBlock.headers(CurlResponseBlock block) {
  return block ? block.getindex(1).list() : NULL;
}

List CurlResponseBlock.values(CurlResponseBlock block, String name) {
  List values = NULL;
  foreach(CurlHeader header, block.headers()) {
    String header_name = header.name();
    if (!header.parsed() || header_name.len() != name.len() ||
        strncasecmp(header_name, name, name.len())) continue;
    values = cons(header.value(), values);
  }
  return values.reverse();
}

CurlHeader Var.curlheader(Var value) {
  return (CurlHeader) value.list();
}

CurlResponseBlock Var.curlresponseblock(Var value) {
  return (CurlResponseBlock) value.list();
}

/*  The Lisp surface is value-oriented on purpose: every binding takes and
    returns String, List, and int, and each owns and frees its own CurlEasy
    and CurlResponse, so no native handle and no borrowed storage ever
    enters a Lisp session. A caller that wants a reused connection, a
    timeout of its own, or the raw handle stays in x2c.
*/

static CurlEasy _lisp_easy(void) {
  return CurlEasy.new().timeouts(2000, 10000).follow_redirects(5);
}

$lisp.binding(libcurl_lisp, "http-get")
static String _lisp_http_get(String url) {
  CurlEasy easy = _lisp_easy();
  defer easy.free();
  CurlResponse response = easy.get(url);
  defer response.free();
  return response.text();
}

$lisp.binding(libcurl_lisp, "http-post")
static String _lisp_http_post(String url, String content_type, String body) {
  CurlEasy easy = _lisp_easy();
  defer easy.free();
  CurlResponse response = easy.body(content_type, body).request(%"POST", url);
  defer response.free();
  return response.text();
}

$lisp.binding(libcurl_lisp, "http-status")
static int _lisp_http_status(String url) {
  CurlEasy easy = _lisp_easy();
  defer easy.free();
  CurlResponse response = easy.get(url);
  defer response.free();
  return (int) response.response_code();
}

/*  The final response block's header lines, as the List of Strings that
    Lisp's own car, length, and string operations already handle.
*/
$lisp.binding(libcurl_lisp, "http-headers")
static List _lisp_http_headers(String url) {
  CurlEasy easy = _lisp_easy();
  defer easy.free();
  CurlResponse response = easy.request(%"HEAD", url);
  defer response.free();
  CurlResponseBlock block = response.blocks().last();
  List lines = NULL;
  foreach(CurlHeader header, block.headers())
    lines = cons(header.line(), lines);
  return lines.reverse();
}

$lisp.binding(libcurl_lisp, "url-escape")
static String _lisp_url_escape(String value) {
  return CurlEasy.escape(value);
}

/** Installs http-get, http-post, http-status, http-headers, and url-escape
    into `lisp`. A transport failure raises out of the binding as the same
    `<io-fail>` an x2c caller would see; an HTTP status stays an ordinary
    returned value.
*/
void CurlLisp.install(Lisp lisp) {
  $lisp.install(lisp, libcurl_lisp);
}
