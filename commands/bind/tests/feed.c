/* feed.c -- the native side of the x2c bind smoke-test library. */

#include <stdlib.h>
#include <string.h>

#include "feed.h"

struct feed_parser {
  char *text;
  size_t len, cursor;
};

struct feed_item {
  feed_parser *parser;
  char *title;
};

feed_parser *feed_open(const char *bytes, size_t len) {
  feed_parser *parser = calloc(1, sizeof *parser);
  parser->text = malloc(len + 1);
  memcpy(parser->text, bytes, len);
  parser->text[len] = 0;
  parser->len = len;
  return parser;
}

void feed_close(feed_parser *parser) {
  if (!parser) return;
  free(parser->text);
  free(parser);
}

int feed_count(const feed_parser *parser) {
  int count = 0;
  for (size_t i = 0; i < parser->len; i++) count += parser->text[i] == '\n';
  return count;
}

int feed_next(feed_parser *parser, const char **title, size_t *len) {
  if (parser->cursor >= parser->len) return FEED_END;
  const char *start = parser->text + parser->cursor;
  const char *end = strchr(start, '\n');
  *title = start;
  *len = end ? (size_t)(end - start) : strlen(start);
  parser->cursor += *len + (end != NULL);
  return FEED_OK;
}

int feed_scan(feed_parser *parser, feed_visitor visit, void *user) {
  const char *title;
  size_t len;
  while (feed_next(parser, &title, &len) == FEED_OK)
    if (!visit(title, user)) return FEED_ERROR;
  return FEED_OK;
}

int feed_stats_read(const feed_parser *parser, feed_stats *stats) {
  stats->items = feed_count(parser);
  stats->bytes = parser->len;
  return FEED_OK;
}

int feed_log(feed_parser *parser, const char *format, ...) {
  (void)parser;
  (void)format;
  return FEED_OK;
}

int feed_item_new(feed_parser *parser, int index, feed_item **out) {
  const char *start = parser->text;
  for (int i = 0; i < index; i++) {
    start = strchr(start, '\n');
    if (!start) return FEED_ERROR;
    start++;
  }
  const char *end = strchr(start, '\n');
  size_t len = end ? (size_t)(end - start) : strlen(start);
  feed_item *item = calloc(1, sizeof *item);
  item->parser = parser;
  item->title = malloc(len + 1);
  memcpy(item->title, start, len);
  item->title[len] = 0;
  *out = item;
  return FEED_OK;
}

const char *feed_item_title(feed_item *item) { return item->title; }

feed_parser *feed_item_parser(feed_item *item) { return item->parser; }

void feed_item_free(feed_item *item) {
  if (!item) return;
  free(item->title);
  free(item);
}

const char *feed_strerror(int code) {
  return code == FEED_OK ? "ok" : code == FEED_END ? "end" : "error";
}
