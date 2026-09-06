/*  varops-hot-paths.x -- representation fast-lane timings */


#include <stdint.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void result(const char *name, uint64_t elapsed, int count) {
  printf("%s,%.3f\n", name, (double) elapsed / count);
}

int main(void) {
  int count = 5000000;
  volatile unsigned long sink = 0;
  Var i32_left = 123, i32_right = 7;
  Var f32_left = Var.new(<f32>, 123.0);
  Var f32_right = Var.new(<f32>, 7.0);
  Var f64_left = 123.0, f64_right = 7.0;
  uint64_t start;
  Var value;

  start = now_ns();
  for (int i = 0; i < count; i++) {
    value = Var.new(<i32>, (int) (i32_left.integer() + i32_right.integer()));
    sink += value.u64;
  }
  result("i32-baseline", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) {
    value = i32_left.binary(<+>, i32_right);
    sink += value.u64;
  }
  result("i32-fast", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) {
    value = Var.new(<f32>, f32_left.floating() + f32_right.floating());
    sink += value.u64;
  }
  result("f32-baseline", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) {
    value = f32_left.binary(<+>, f32_right);
    sink += value.u64;
  }
  result("f32-fast", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) {
    value = Var.new(<f64>, f64_left.floating() + f64_right.floating());
    sink += value.u64;
  }
  result("f64-baseline", now_ns() - start, count);

  start = now_ns();
  for (int i = 0; i < count; i++) {
    value = f64_left.binary(<+>, f64_right);
    sink += value.u64;
  }
  result("f64-fast", now_ns() - start, count);

  int update_count = 1000000;
  Var out, i32_update = 0;
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = Var.update(&i32_update, <+>, 1);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("i32-update", now_ns() - start, update_count);

  Var u32_update = Var.new(<u32>, 0u), u32_one = Var.new(<u32>, 1u);
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = Var.update(&u32_update, <+>, u32_one);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("u32-update", now_ns() - start, update_count);

  Var f32_update = Var.new(<f32>, 0.0f), f32_step = Var.new(<f32>, 0.25f);
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = Var.update(&f32_update, <+>, f32_step);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("f32-update", now_ns() - start, update_count);

  Var f64_update = 0.0, f64_step = 0.25;
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = Var.update(&f64_update, <+>, f64_step);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("f64-update", now_ns() - start, update_count);

  Var mixed_update = 0, mixed_step = Var.new(<u16>, 1);
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = Var.update(&mixed_update, <+>, mixed_step);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("mixed-update", now_ns() - start, update_count);

  int wide_count = 100000;
  Var wide_update = Var.box_long(0), wide_step = Var.box_long(1);
  start = now_ns();
  for (int i = 0; i < wide_count; i++) {
    out = Var.update(&wide_update, <+>, wide_step);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("wide-update", now_ns() - start, wide_count);

  Array array = %[0];
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = array.updateindex(0, <+>, 1);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("array-existing-update", now_ns() - start, update_count);

  Map existing = %{ count: 0 };
  start = now_ns();
  for (int i = 0; i < update_count; i++) {
    out = existing.updateindex(<count>, <+>, 1);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("map-existing-update", now_ns() - start, update_count);

  int missing_count = 100000;
  Map missing = %{};
  start = now_ns();
  for (int i = 0; i < missing_count; i++) {
    out = missing.updateindex(i, <+>, 1);
    if (out is void) return 2;
    sink += out.u64;
  }
  result("map-missing-update", now_ns() - start, missing_count);

  return sink == 0 || i32_update is not <i32> ||
         u32_update is not <u32> || f32_update is not <f32> ||
         f64_update is not <f64> || mixed_update is not <i32> ||
         wide_update is not <long>;
}
