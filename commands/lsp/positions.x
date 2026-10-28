/*  positions.x -- LSP file URIs and UTF-16 source positions

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "sourceview.x"
#include "scan.x"

/** Decodes a local file URI to the compiler's logical absolute path. */
String lsp_path(String uri) {
  if (!uri || strncmp(uri, "file://", 7)) return NULL;
  const char *at = uri + 7;
  if (!strncmp(at, "localhost/", 10)) at += 9;
  if (*at != '/') return NULL;
  Buffer out = auto Buffer.new(0);
  while (*at) {
    if (*at == '%') {
      if (!at[1] || !at[2]) return NULL;
      int hi = scan_ascii_hex_value(at[1]), lo = scan_ascii_hex_value(at[2]);
      if (hi < 0 || lo < 0 || !(hi * 16 + lo)) return NULL;
      out.write_char(hi * 16 + lo);
      at += 3;
    }
    else out.write_char(*at++);
  }
  return Path.absolute(out.str());
}

/** Encodes a logical absolute path as a local file URI. */
String lsp_uri(String path) {
  Buffer out = auto Buffer.new(0);
  out.write("file://");
  foreach (int byte, path) {
    if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
        (byte >= '0' && byte <= '9') || strchr("/-._~:", byte))
      out.write_char(byte);
    else out.printf("%%%02X", (unsigned char) byte);
  }
  return out;
}

/** Converts a UTF-8 byte offset to an LSP UTF-16 position. */
Map lsp_position(String text, int offset) {
  int line = 0, column = 0, length = text.len();
  if (offset > length) offset = length;
  for (int at = 0; at < offset;) {
    int byte = (unsigned char) text[at];
    if (byte == '\r' || byte == '\n') {
      int width = byte == '\r' && at + 1 < length && text[at + 1] == '\n' ? 2 : 1;
      if (at + width > offset) break;
      line++;
      column = 0;
      at += width;
    }
    else {
      int width = scan_utf8_length((const unsigned char *) text + at);
      if (width < 1) width = 1;
      if (at + width > offset) break;
      column += width == 4 ? 2 : 1;
      at += width;
    }
  }
  return {line: line, character: column};
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
