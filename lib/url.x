/*  url.x -- URL references and query strings

    Copyright (c) 2026 Gary William Flake

    `Url.parse` splits a URL or a relative reference into the components
    RFC 3986 names and keeps each as written, percent-encoding included;
    `String.percent_decode` decodes one. `Url.str` joins them again. The
    empty `String` is the null pointer, so an empty query or fragment is
    the same as an absent one, and formatting drops a bare `?` or `#`.
*/

#pragma once
#include "x2c.x"
#include "encoding.x"

/** The components of a URL reference. `host` is written without the
    brackets of an IPv6 literal, `port` is 0 when the reference names none,
    and the other components keep their percent-encoding. A relative
    reference such as `/search?q=x` has no scheme or host.
*/
class Url {
  String scheme, userinfo, host;
  int port;
  String path, query, fragment;
};

#include <string.h>

// references

/** Returns the components of the URL or relative reference `text`.
    `text` must be printable ASCII with each `%` followed by two
    hexadecimal digits, and a scheme must be a letter followed by letters,
    digits, `+`, `-`, or `.`. A port above 65535 is out of range.

    ```x2c
    ~#include "url.x"
    ~int main(void) {
    Url url = Url.parse("https://example.com:8443/a%20b?q=1#top");
    printf("%s %s %d %s\n", url.scheme, url.host, url.port,
           url.path.percent_decode());
    ~  return 0;
    ~}
    ```

    ```text
    https example.com 8443 /a b
    ```

    Raises: `<malformed>` with `reason` and byte `offset` when `text` is not
    a URL reference of that form.
*/
Url Url.parse(String text) {
  _validate(text);
  Url url = {0};
  int at = 0, end = text.len();
  int colon = _first(text, 0, end, ":/?#");
  if (colon < end && text[colon] == ':') {
    url.scheme = _scheme(text, colon);
    at = colon + 1;
  }
  if (text[at] == '/' && text[at + 1] == '/') {
    int stop = _first(text, at + 2, end, "/?#");
    _authority(url, text, at + 2, stop);
    at = stop;
  }
  int question = _first(text, at, end, "?#");
  int hash = _first(text, at, end, "#");
  url.path = text[at:question];
  if (question < hash) url.query = text[question + 1:hash];
  if (hash < end) url.fragment = text[hash + 1:];
  return url;
}

/** Returns `url` as text, in the order RFC 3986 section 5.3 joins the
    components. The authority is written when `url` has a host, userinfo,
    or port, or has a scheme and a path that starts with `/`, so `file:/tmp`
    formats as `file:///tmp`.
*/
String Url.str(Url url) {
  Buffer out = auto Buffer.new(0);
  if (url.scheme) out.write(url.scheme).write_char(':');
  int authority = url.host || url.userinfo || url.port ||
                  (url.scheme && url.path.startswith("/"));
  if (authority) _write_authority(out, url);
  if (authority && url.path && !url.path.startswith("/")) out.write_char('/');
  if (url.path) out.write(url.path);
  if (url.query) out.write_char('?').write(url.query);
  if (url.fragment) out.write_char('#').write(url.fragment);
  return out;
}

// query strings

/** Returns the names and values of the query string `query` as a Map of
    Strings. Pairs are separated by `&` and split at their first `=`; a
    pair without one has the value `""`, and empty pairs are skipped. Each
    `+` becomes a space before percent-decoding, as HTML forms encode. A
    repeated name keeps its last value.
    Raises: `<malformed>` from `String.percent_decode` for an invalid
    escape.
*/
Map Url.parse_query(String query) {
  Map fields = {};
  foreach (String pair in query.split("&")) {
    if (!pair) continue;
    List parts = pair.partition("=");
    fields[_form_decode(parts.car())] = _form_decode(parts.caddr());
  }
  return fields;
}

/** Returns `fields` as a query string of `name=value` pairs joined by
    `&`, in byte order of the names, with names and values percent-encoded
    by `String.percent_encode`. Names and values that are not Strings are
    written with their `str` form.
*/
String Url.format_query(Map fields) {
  Array names = auto [];
  foreach (Var name in fields.keys()) names.push(name);
  names.sort_by(%!(name) => name.str());
  Buffer out = auto Buffer.new(0);
  foreach (Var name in names) {
    if (out.len()) out.write_char('&');
    out.write(%"$(_form_encode(name))=$(_form_encode(fields[name]))");
  }
  return out;
}

// reading references

static void _validate(String text) {
  for (int i = 0; i < text.len(); i++) {
    int c = text[i];
    if (c <= ' ' || c >= 0x7F) _malformed("invalid character", i);
    if (c == '%' && (scan_ascii_hex_value(text[i + 1]) < 0 ||
                     scan_ascii_hex_value(text[i + 2]) < 0))
      _malformed("invalid percent escape", i);
  }
}

/* The index of the first byte from `at` before `stop` that is one of
   `bytes`, or `stop`. */
static int _first(String text, int at, int stop, const char *bytes) {
  while (at < stop && !strchr(bytes, text[at])) at++;
  return at;
}

static String _scheme(String text, int colon) {
  if (!colon) _malformed("invalid scheme", 0);
  for (int i = 0; i < colon; i++) {
    int c = text[i];
    int letter = (c | 32) >= 'a' && (c | 32) <= 'z';
    if (!letter && (!i || !(scan_ascii_digit(c) || strchr("+-.", c))))
      _malformed("invalid scheme", i);
  }
  return text[:colon];
}

static void _authority(Url &url, String text, int at, int stop) {
  int sign = _last(text, at, stop, '@');
  if (sign >= at) {
    url.userinfo = text[at:sign];
    at = sign + 1;
  }
  int colon = stop;
  if (text[at] == '[') {
    int close = _first(text, at, stop, "]");
    if (close == stop) _malformed("unclosed '[' in the host", at);
    url.host = text[at + 1:close];
    colon = close + 1;
    if (colon < stop && text[colon] != ':')
      _malformed("expected ':' after ']'", colon);
  }
  else {
    colon = _first(text, at, stop, ":");
    url.host = text[at:colon];
  }
  if (colon < stop) url.port = _port(text, colon + 1, stop);
}

static int _last(String text, int at, int stop, char byte) {
  while (--stop >= at && text[stop] != byte) {}
  return stop;
}

/* An empty port is absent, as RFC 3986 section 6.2.3 allows. */
static int _port(String text, int at, int stop) {
  int port = 0;
  for (int i = at; i < stop; i++) {
    if (!scan_ascii_digit(text[i])) _malformed("expected a digit", i);
    port = port * 10 + text[i] - '0';
    if (port > 65535) _malformed("port out of range", at);
  }
  return port;
}

static void _malformed(String reason, int offset) {
  raise %(malformed (operation "Url.parse") (reason $reason)
          (offset $offset));
}

// writing references

static void _write_authority(Buffer out, Url url) {
  out.write("//");
  if (url.userinfo) out.write(url.userinfo).write_char('@');
  if (":" in url.host) out.write_char('[').write(url.host).write_char(']');
  else if (url.host) out.write(url.host);
  if (url.port) out.printf(":%d", url.port);
}

// form encoding

static String _form_decode(String text) =>
  text.replace("+", " ").percent_decode();

static String _form_encode(Var value) => value.str().percent_encode();
