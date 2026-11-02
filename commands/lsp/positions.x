/*  positions.x -- LSP file URIs and UTF-16 source positions

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "sourceview.x"
#include "scan.x"
#include "encoding.x"

/** Decodes a local file URI to the compiler's logical absolute path. */
String lsp_path(String uri) {
  if (!uri || strncmp(uri, "file://", 7)) return NULL;
  const char *at = uri + 7;
  if (!strncmp(at, "localhost/", 10)) at += 9;
  if (*at != '/') return NULL;
  String encoded = at;
  try { return Path.absolute(encoded.percent_decode()); }
  catch %(malformed *): return NULL;
}

/** Encodes a logical absolute path as a local file URI. */
String lsp_uri(String path) =>
  "file://" + path.percent_encode().replace("%2F", "/").replace("%3A", ":");

/** Converts a UTF-8 byte offset to an LSP UTF-16 position. */
Map lsp_position(String text, int offset) {
  int at = 0, line = 0, column = 0;
  lsp_advance(text, offset, at, line, column);
  return {line: line, character: column};
}

/** Advances a byte cursor and its UTF-16 position to a later boundary.
    Reusing the cursor visits each byte once across a sorted token stream.
*/
void lsp_advance(
  String text, int end, int &at, int &line, int &column) {
  int length = text.len();
  if (end > length) end = length;
  while (at < end) {
    int byte = (unsigned char) text[at];
    if (byte == '\r' || byte == '\n') {
      int width = byte == '\r' && at + 1 < length && text[at + 1] == '\n' ? 2 : 1;
      if (at + width > end) break;
      line++;
      column = 0;
      at += width;
    }
    else {
      int width = scan_utf8_length((const unsigned char *) text + at);
      if (width < 1) width = 1;
      if (at + width > end) break;
      column += width == 4 ? 2 : 1;
      at += width;
    }
  }
}

/** Converts an LSP UTF-16 position to a UTF-8 byte offset. */
int lsp_offset(String text, Map position) {
  int wanted_line = position.getdefault("line", 0);
  int wanted_column = position.getdefault("character", 0);
  int at = 0, length = text.len(), line = 0, column = 0;
  while (at < length && line < wanted_line) {
    int byte = text[at++];
    if (byte == '\r') {
      if (at < length && text[at] == '\n') at++;
      line++;
    }
    else if (byte == '\n') line++;
  }
  while (at < length && column < wanted_column &&
         text[at] != '\n' && text[at] != '\r') {
    int width = scan_utf8_length((const unsigned char *) text + at);
    if (width < 1) width = 1;
    int units = width == 4 ? 2 : 1;
    if (column + units > wanted_column) break;
    column += units;
    at += width;
  }
  return at;
}

/** Converts a compiler byte range against its source text. */
Map lsp_range(String text, int start, int end) =>
  {start: lsp_position(text, start), end: lsp_position(text, end)};
