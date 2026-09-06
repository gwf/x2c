#include "x2c.x"
#include "foreign-qualifier-upstream.h"

$x2c.foreign.alias(upstream_monitor_index)
inline int aliased_index(const char *label);

$x2c.foreign.alias(upstream_monitor_width)
inline const int aliased_width(int index);

static const char *left_label(int index) {
  return upstream_monitor_label(index);
}

int main(void) {
  const char *first = upstream_monitor_label(0);
  const char *version = upstream_version;
  const upstream_monitor *second = upstream_monitor_at(1);
  upstream_label_fn callback = left_label;
  String owned = first;
  printf("%s %s %s %d %d %d %d\n",
         version, first, second->label, upstream_count_labels(callback),
         aliased_index(first), aliased_width(1), owned.len());
  return 0;
}
