#include "protocol-static-owner.x"

int static_consumer_total(StaticItemsChild values) {
  int total = 0;
  foreach(int value, values) total += value;
  return total;
}
