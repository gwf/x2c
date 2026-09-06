/* A pinned upstream C header in the shape a package vendors: real names,
   real const declarations, and no x2c in it. It is header only so the one
   generated translation unit compiles and links against it. */

#pragma once

typedef struct upstream_monitor {
  const char *label;
  int width;
} upstream_monitor;

typedef const char *(*upstream_label_fn)(int index);

static const char *const upstream_version = "upstream 1.0";

static const upstream_monitor upstream_monitors[2] = {
  { "left", 1280 }, { "right", 1920 }
};

static inline const char *upstream_monitor_label(int index) {
  return upstream_monitors[index].label;
}

static inline const upstream_monitor *upstream_monitor_at(int index) {
  return &upstream_monitors[index];
}

static inline int upstream_monitor_index(const char *label) {
  for (int index = 0; index < 2; index++)
    if (label == upstream_monitors[index].label) return index;
  return -1;
}

static inline const int upstream_monitor_width(int index) {
  return upstream_monitors[index].width;
}

static inline int upstream_count_labels(upstream_label_fn callback) {
  int total = 0;
  for (int index = 0; index < 2; index++)
    if (callback(index)) total++;
  return total;
}
