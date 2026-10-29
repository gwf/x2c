/*  consumer.x -- import a package that x2c bind generated and use it. */

import "feed" with FeedParser, FeedItem;

#include "feed-raw.h"

int main(void) {
  String text = "alpha\nbeta\ngamma\n";
  FeedParser parser = auto feed_open(text, text.len());
  printf("%d items\n", parser.count());
  feed_item *native = NULL;
  parser.item_new(1, &native);
  FeedItem item = auto native;
  printf("%s, %s\n", item.title(), feed_strerror(FEED_OK));
  return item.parser() == parser ? 0 : 1;
}
