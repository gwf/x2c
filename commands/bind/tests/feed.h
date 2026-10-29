/* feed.h -- a small C library that the x2c bind smoke test binds. */

#ifndef FEED_H
#define FEED_H

#include <stddef.h>

#define FEED_VERSION 3

typedef struct feed_parser feed_parser;
typedef struct feed_item feed_item;
typedef int (*feed_visitor)(const char *title, void *user);

enum feed_status { FEED_OK, FEED_END, FEED_ERROR = -1 };

typedef struct feed_stats {
  int items;
  size_t bytes;
} feed_stats;

feed_parser *feed_open(const char *bytes, size_t len);
void feed_close(feed_parser *parser);
int feed_count(const feed_parser *parser);
int feed_next(feed_parser *parser, const char **title, size_t *len);
int feed_scan(feed_parser *parser, feed_visitor visit, void *user);
int feed_stats_read(const feed_parser *parser, feed_stats *stats);
int feed_log(feed_parser *parser, const char *format, ...);
int feed_item_new(feed_parser *parser, int index, feed_item **out);
const char *feed_item_title(feed_item *item);
feed_parser *feed_item_parser(feed_item *item);
void feed_item_free(feed_item *item);
const char *feed_strerror(int code);

/* Collection also reads disabled branches; bind leaves this one out. */
#ifdef FEED_INTERNAL
int feed_reset(feed_parser *parser);
#endif

#endif
